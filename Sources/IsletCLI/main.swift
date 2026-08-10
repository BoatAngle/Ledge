import Foundation
import IsletCore

// MARK: - Entry

let arguments = Array(CommandLine.arguments.dropFirst())
let parsed = Arguments(arguments)
let client = IsletClient()

if parsed.switches.contains("version") {
    print("islet \(isletVersion)")
    exit(0)
}

guard let subcommand = parsed.positional.first, !parsed.switches.contains("help") else {
    printUsage()
    exit(parsed.switches.contains("help") ? 0 : 1)
}

do {
    switch subcommand {
    case "start", "post":   try start()
    case "update":          try update()
    case "end":             try end()
    case "end-all":         try endAll()
    case "flash":           try flash()
    case "list":            try list()
    case "ping":            try ping()
    case "run":             try run()
    case "timer":           try timer()
    case "shelf":           try shelf()
    case "help":            printUsage()
    default:
        FileHandle.standardError.write(Data("Unknown command \"\(subcommand)\".\n\n".utf8))
        printUsage()
        exit(1)
    }
} catch let error as IsletClient.ClientError {
    fail(error.description)
} catch {
    fail("\(error)")
}

// MARK: - Commands

func start() throws {
    let activity = try buildActivity(kind: .ongoing)
    let response = try client.send(IsletRequest(command: .present, activity: activity))
    emit(["id": response.id ?? activity.id], plain: response.id ?? activity.id)
}

func flash() throws {
    var activity = try buildActivity(kind: .transient)
    let dwell = parsed.double("dwell") ?? 2.0
    activity.expiresAt = Date().addingTimeInterval(dwell)
    let response = try client.send(IsletRequest(command: .present, activity: activity))
    emit(["id": response.id ?? activity.id], plain: response.id ?? activity.id)
}

func update() throws {
    guard let id = identifier() else { fail("`update` needs an id: islet update <id> --progress 0.5") }
    // Only fields the caller actually passed should change, so read the current
    // content first and patch it.
    let existing = try client.send(IsletRequest(command: .list)).activities?
        .first { $0.id == id }
    var content = existing?.content ?? ActivityContent(title: parsed.string("title") ?? id)
    applyContentFlags(to: &content)
    try client.send(IsletRequest(command: .update, id: id, content: content))
    emit(["id": id], plain: id)
}

func end() throws {
    guard let id = identifier() else { fail("`end` needs an id: islet end <id>") }
    try client.send(IsletRequest(command: .end, id: id))
    emit(["id": id], plain: id)
}

func endAll() throws {
    let response = try client.send(
        IsletRequest(command: .endAll, source: parsed.string("source"))
    )
    let count = response.count ?? 0
    emit(["ended": count], plain: "\(count)")
}

func list() throws {
    let activities = try client.send(IsletRequest(command: .list)).activities ?? []
    if parsed.switches.contains("json") {
        let data = (try? IsletCoding.encoder.encode(activities)) ?? Data("[]".utf8)
        print(String(decoding: data, as: UTF8.self))
        return
    }
    guard !activities.isEmpty else {
        print("Nothing on the island.")
        return
    }
    for activity in activities {
        let progress = activity.content.progress?.fraction
            .map { " \(Int($0 * 100))%" } ?? ""
        print("\(activity.id)\t[\(activity.source)]\t\(activity.content.title)\(progress)")
    }
}

/// `islet shelf a.png b.png` — park files on the island, or clear it.
func shelf() throws {
    let paths = Array(parsed.positional.dropFirst())
    let response = try client.send(IsletRequest(command: .shelf, paths: paths))
    let count = response.count ?? 0
    emit(["count": count], plain: count == 0 ? "shelf cleared" : "\(count) on the shelf")
}

/// `islet timer 25m` — a real timer the app owns, so it rings.
func timer() throws {
    guard let raw = parsed.positional.count > 1 ? parsed.positional[1] : parsed.string("for") else {
        fail("`timer` needs a duration: islet timer 25m")
    }
    guard let seconds = IsletDuration.parse(raw) else {
        fail("Couldn't read \"\(raw)\" as a duration. Try 25m, 90s, 1h30m, or 25:00.")
    }
    let label = parsed.string("label") ?? parsed.string("title")
    let response = try client.send(
        IsletRequest(
            command: .startTimer,
            content: label.map { ActivityContent(title: $0) },
            duration: seconds
        )
    )
    emit(["id": response.id ?? ""], plain: response.id ?? "")
}

func ping() throws {
    _ = try client.send(IsletRequest(command: .ping))
    emit(["ok": true], plain: "islet is running")
}

/// Wraps a command: shows an activity while it runs, then reports how it went.
///
/// This is the shape most people actually want — no ids to track, no cleanup to
/// forget, and the island is correct even if the command fails.
func run() throws {
    let command = parsed.passthrough
    guard !command.isEmpty else {
        fail("`run` needs a command: islet run --title \"Build\" -- make all")
    }

    let id = parsed.string("id") ?? "cli.run.\(ProcessInfo.processInfo.processIdentifier)"
    let title = parsed.string("title") ?? command.joined(separator: " ")

    var content = ActivityContent(
        title: title,
        subtitle: parsed.string("subtitle") ?? "Running…",
        icon: icon() ?? .symbol("terminal"),
        tint: tint() ?? .accent,
        progress: ActivityProgress(),
        countUpFrom: Date()
    )

    var activity = Activity(
        id: id,
        source: parsed.string("source") ?? "cli",
        kind: .ongoing,
        priority: priority(),
        content: content
    )
    _ = try? client.send(IsletRequest(command: .present, activity: activity))

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = command

    // If the user interrupts, take the island down with us rather than leaving
    // a ghost activity pinned to their screen.
    let cleanup = { _ = try? client.send(IsletRequest(command: .end, id: id)) }
    signal(SIGINT, SIG_IGN)
    let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    interrupt.setEventHandler { cleanup(); exit(130) }
    interrupt.resume()

    do {
        try process.run()
    } catch {
        cleanup()
        fail("Couldn't run \(command[0]): \(error.localizedDescription)")
    }
    process.waitUntilExit()

    let status = process.terminationStatus
    content = ActivityContent(
        title: title,
        subtitle: status == 0 ? "Finished" : "Failed (exit \(status))",
        icon: .symbol(status == 0 ? "checkmark.circle.fill" : "xmark.octagon.fill"),
        tint: status == 0 ? .green : .red
    )
    activity.content = content
    activity.kind = .transient
    activity.expiresAt = Date().addingTimeInterval(parsed.double("dwell") ?? 4)
    _ = try? client.send(IsletRequest(command: .present, activity: activity))

    exit(status)
}

// MARK: - Building

func identifier() -> String? {
    parsed.string("id") ?? (parsed.positional.count > 1 ? parsed.positional[1] : nil)
}

func buildActivity(kind: ActivityKind) throws -> Activity {
    // `--stdin` lets a caller hand over a full activity as JSON, for anything
    // the flags don't cover.
    if parsed.has("stdin") {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        if let activity = try? IsletCoding.decoder.decode(Activity.self, from: data) {
            return activity
        }
        if let content = try? IsletCoding.decoder.decode(ActivityContent.self, from: data) {
            return Activity(
                id: parsed.string("id") ?? UUID().uuidString,
                source: parsed.string("source") ?? "cli",
                kind: kind,
                priority: priority(),
                content: content
            )
        }
        fail("Couldn't parse JSON on stdin as an activity or content object.")
    }

    guard let title = parsed.string("title") else {
        fail("Needs at least --title.")
    }

    var content = ActivityContent(title: title)
    applyContentFlags(to: &content)

    return Activity(
        id: parsed.string("id") ?? UUID().uuidString,
        source: parsed.string("source") ?? "cli",
        kind: kind,
        priority: priority(),
        content: content,
        openURL: parsed.string("open")
    )
}

func applyContentFlags(to content: inout ActivityContent) {
    if let value = parsed.string("title") { content.title = value }
    if let value = parsed.string("subtitle") { content.subtitle = value }
    if let value = parsed.string("body") { content.body = value }
    if let value = parsed.string("trailing") { content.trailingText = value }
    if let value = icon() { content.icon = value }
    if let value = tint() { content.tint = value }

    if parsed.switches.contains("indeterminate") {
        content.progress = ActivityProgress(label: parsed.string("progress-label"))
    } else if let fraction = parsed.double("progress") {
        content.progress = ActivityProgress(fraction: fraction, label: parsed.string("progress-label"))
    }

    if let seconds = parsed.double("countdown") {
        content.countdownTarget = Date().addingTimeInterval(seconds)
    }
    if parsed.has("count-up") {
        content.countUpFrom = Date()
    }
    if let raw = parsed.string("detail") {
        // `--detail "Label=Value,Other=Thing"`
        content.details = raw.split(separator: ",").compactMap { pair in
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return ActivityDetail(
                label: parts[0].trimmingCharacters(in: .whitespaces),
                value: parts[1].trimmingCharacters(in: .whitespaces)
            )
        }
    }
}

func icon() -> ActivityIcon? {
    guard let raw = parsed.string("icon") else { return nil }
    if raw.hasPrefix("symbol:") { return .symbol(String(raw.dropFirst(7))) }
    if raw.hasPrefix("app:") { return .bundleIdentifier(String(raw.dropFirst(4))) }
    if raw.hasPrefix("file:") { return .file(String(raw.dropFirst(5))) }
    // Bare values: a path if it exists on disk, otherwise an SF Symbol name.
    if FileManager.default.fileExists(atPath: raw) { return .file(raw) }
    return .symbol(raw)
}

func tint() -> IsletColor? {
    guard let raw = parsed.string("tint") else { return nil }
    guard let color = IsletColor(parsing: raw) else {
        fail("Unrecognised --tint \"\(raw)\". Use a name (blue, green…) or #RRGGBB.")
    }
    return color
}

func priority() -> ActivityPriority {
    switch parsed.string("priority")?.lowercased() {
    case "background": return .background
    case "low": return .low
    case "high": return .high
    case "critical": return .critical
    default: return .normal
    }
}

// MARK: - Output

func emit(_ payload: [String: Any], plain: String) {
    if parsed.switches.contains("json") {
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
        print(String(decoding: data, as: UTF8.self))
    } else if !parsed.switches.contains("quiet") {
        print(plain)
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("islet: \(message)\n".utf8))
    exit(1)
}

func printUsage() {
    print("""
    islet \(isletVersion) — post live activities to your Mac's notch.

    USAGE
      islet <command> [options]

    COMMANDS
      start        Post an ongoing activity. Prints its id.
      flash        Post a transient activity that retires itself.
      update <id>  Change an existing activity's content.
      end <id>     Remove an activity.
      end-all      Remove everything (optionally --source <name>).
      list         Show what's currently on the island.
      run -- <cmd> Run a command, showing progress; reports success or failure.
      timer <dur>  Start a countdown that rings. 25m, 90s, 1h30m, or 25:00.
      shelf [files] Park files on the island to drag out later. No args clears.
      ping         Check that Islet.app is running.

    CONTENT
      --title <text>            Required for start/flash.
      --subtitle <text>
      --body <text>
      --trailing <text>         Short text for the compact right-hand slot.
      --icon <spec>             symbol:<sf.symbol> | app:<bundle.id> | file:<path>
      --tint <color>            Name (blue, green, orange…) or #RRGGBB.
      --progress <0-1|50%>      Determinate progress.
      --indeterminate           Progress with no known end.
      --progress-label <text>
      --countdown <seconds>     Counts down locally, no updates needed.
      --count-up                Counts up from now.
      --detail "K=V,K2=V2"      Rows in the expanded panel.
      --open <url>              Opened when the activity is clicked.

    BEHAVIOUR
      --id <id>                 Reuse an id to update in place.
      --source <name>           Group activities for `end-all --source`.
      --priority <level>        background | low | normal | high | critical
      --dwell <seconds>         How long a flash stays up.
      --stdin                   Read a full activity as JSON from stdin.
      --json                    Machine-readable output.
      --quiet                   Print nothing on success.

    EXAMPLES
      islet run --title "Build" -- swift build
      id=$(islet start --title "Uploading" --indeterminate --tint blue)
      islet update $id --progress 60%
      islet end $id
      islet flash --title "Deployed" --icon symbol:checkmark.seal.fill --tint green
      islet timer 25m --label Pomodoro
      islet shelf ~/Desktop/*.png
    """)
}

