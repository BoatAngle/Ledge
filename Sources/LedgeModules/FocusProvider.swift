import Foundation
import LedgeCore

/// Focus / Do Not Disturb state.
///
/// macOS exposes no public API for the active Focus, but it does keep the state
/// in a pair of JSON files under `~/Library/DoNotDisturb`. Watching them is
/// read-only, needs no entitlement, and degrades to "module unavailable" if
/// Apple moves the format again.
@MainActor
public final class FocusProvider: SystemProvider {
    public let identifier = "system.focus"
    public let displayName = "Focus"
    public let summary = "Which Focus is on"
    public var isAvailable: Bool { FileManager.default.fileExists(atPath: Self.databaseDirectory.path) }

    private static var databaseDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/DoNotDisturb/DB", isDirectory: true)
    }

    private weak var store: ActivityStore?
    private var watcher: DispatchSourceFileSystemObject?
    private var directoryDescriptor: CInt = -1
    private lazy var poller = PollTimer(interval: 2.0) { [weak self] in self?.evaluate() }
    private var lastMode: String??
    private var isPrimed = false

    public init() {}

    public func start(store: ActivityStore) {
        self.store = store
        lastMode = .some(activeMode())
        startWatching()

        // The vnode watch misses atomic replaces often enough that a slow poll
        // earns its keep as a backstop.
        poller.start()

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            self?.isPrimed = true
        }
    }

    public func stop() {
        watcher?.cancel()
        watcher = nil
        if directoryDescriptor >= 0 { close(directoryDescriptor) }
        directoryDescriptor = -1
        poller.stop()
        store = nil
    }

    public func suspend() { poller.suspend() }
    public func resume() { poller.resume() }

    // MARK: - Watching

    private func startWatching() {
        let descriptor = open(Self.databaseDirectory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        directoryDescriptor = descriptor

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        source.resume()
        watcher = source
    }

    private func evaluate() {
        guard let store else { return }
        let mode = activeMode()
        guard lastMode != .some(mode) else { return }
        lastMode = .some(mode)
        guard isPrimed else { return }

        guard let mode else {
            store.end(id: identifier)
            store.flash(
                id: "system.focusChange",
                nativeView: .focus,
                module: identifier,
                content: ActivityContent(
                    title: "Focus Off",
                    icon: .symbol("moon.slash.fill"),
                    tint: LedgeColor.gray
                ),
                dwell: 1.6
            )
            return
        }

        let name = friendlyName(for: mode)
        // Ongoing, because "am I still silenced?" is a question you ask hours
        // later — but low priority so it yields the compact slot to anything
        // actually happening.
        store.present(
            Activity(
                id: identifier,
                source: "system",
                kind: .ongoing,
                priority: .low,
                content: ActivityContent(
                    title: name,
                    subtitle: "Notifications silenced",
                    icon: .symbol(symbol(for: mode)),
                    tint: LedgeColor.indigo
                ),
                nativeView: .focus,
                module: identifier,
                isExpandable: true
            )
        )
    }

    // MARK: - Parsing

    /// The active Focus mode identifier, or `nil` when no Focus is on.
    private func activeMode() -> String? {
        let url = Self.databaseDirectory.appendingPathComponent("Assertions.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["data"] as? [[String: Any]]
        else { return nil }

        for entry in entries {
            guard let records = entry["storeAssertionRecords"] as? [[String: Any]] else { continue }
            for record in records {
                if let details = record["assertionDetails"] as? [String: Any],
                   let identifier = details["assertionDetailsModeIdentifier"] as? String {
                    return identifier
                }
            }
        }
        return nil
    }

    /// Resolves a mode identifier to the name the user gave it, falling back to
    /// a sensible label for the built-in modes.
    private func friendlyName(for identifier: String) -> String {
        let url = Self.databaseDirectory.appendingPathComponent("ModeConfigurations.json")
        if let data = try? Data(contentsOf: url),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let entries = root["data"] as? [[String: Any]] {
            for entry in entries {
                guard let configurations = entry["modeConfigurations"] as? [String: Any],
                      let configuration = configurations[identifier] as? [String: Any],
                      let mode = configuration["mode"] as? [String: Any],
                      let name = mode["name"] as? String
                else { continue }
                return name
            }
        }
        return Self.builtInNames[identifier] ?? "Focus"
    }

    private func symbol(for identifier: String) -> String {
        if identifier.contains("sleep") { return "bed.double.fill" }
        if identifier.contains("work") { return "briefcase.fill" }
        if identifier.contains("personal") { return "person.fill" }
        if identifier.contains("fitness") { return "figure.run" }
        if identifier.contains("gaming") { return "gamecontroller.fill" }
        if identifier.contains("mindfulness") { return "brain.head.profile" }
        if identifier.contains("reading") { return "book.fill" }
        if identifier.contains("driving") { return "car.fill" }
        return "moon.fill"
    }

    private static let builtInNames: [String: String] = [
        "com.apple.donotdisturb.mode.default": "Do Not Disturb",
        "com.apple.sleep.sleep-mode": "Sleep",
        "com.apple.focus.work": "Work",
        "com.apple.focus.personal": "Personal",
        "com.apple.focus.fitness": "Fitness",
        "com.apple.focus.gaming": "Gaming",
        "com.apple.focus.mindfulness": "Mindfulness",
        "com.apple.focus.reading": "Reading",
        "com.apple.focus.driving": "Driving",
    ]
}
