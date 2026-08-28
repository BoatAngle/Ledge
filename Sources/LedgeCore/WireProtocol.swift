import Foundation

/// Where the app listens and the CLI connects.
///
/// A Unix domain socket under Application Support, rather than a TCP port:
/// nothing outside this user account can reach it, there is no port to collide
/// with, and it dies with the machine. An island that anything on the network
/// could write to would be a genuinely bad idea.
public enum LedgeSocket {
    public static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Ledge", isDirectory: true)
    }

    public static var path: String {
        // Unix socket paths are capped near 104 bytes, so this stays short.
        directory.appendingPathComponent("ledge.sock").path
    }

    public static func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }
}

/// Commands a client can send. Newline-delimited JSON, one request per line.
public enum LedgeCommand: String, Codable, Sendable {
    case present
    case update
    case end
    case endAll
    case list
    case ping
    /// Starts a real timer the app owns, so it can alert at zero.
    ///
    /// A caller *could* fake one with `present` plus `countdownTarget`, but
    /// nothing would ring — the island would just quietly reach 0:00. Timers
    /// need an owner with a run loop.
    case startTimer
    /// Put files on the shelf without dragging them there.
    ///
    /// The shelf is most useful as the tail of a pipeline — `ledge shelf
    /// out/*.png` and then drag them straight into a message — so it would be
    /// a shame to make dragging the only way in.
    case shelf
    /// Show current conditions on the island now.
    case weather
    /// Bring up the settings window.
    case settings
    /// Open or close the expanded panel.
    ///
    /// Hovering is the normal way in, but a script wanting to *show* something
    /// — a Shortcut, a demo, a screenshot — shouldn't have to synthesise mouse
    /// movement to do it.
    case expand
    case collapse
}

public struct LedgeRequest: Codable, Sendable {
    public var command: LedgeCommand
    public var activity: Activity?
    public var id: String?
    public var content: ActivityContent?
    public var source: String?
    /// Seconds. Only meaningful for `.startTimer`.
    public var duration: Double?
    /// File paths. Only meaningful for `.shelf`; empty clears it.
    public var paths: [String]?
    /// Only meaningful for `.endAll`: also clear activities the built-in
    /// modules own — a running timer, what's playing, a download in progress.
    ///
    /// Off unless asked for. Clearing the island is a display gesture, and it
    /// should not quietly cancel work.
    public var includeModules: Bool?

    public init(
        command: LedgeCommand,
        activity: Activity? = nil,
        id: String? = nil,
        content: ActivityContent? = nil,
        source: String? = nil,
        duration: Double? = nil,
        paths: [String]? = nil,
        includeModules: Bool? = nil
    ) {
        self.command = command
        self.activity = activity
        self.id = id
        self.content = content
        self.source = source
        self.duration = duration
        self.paths = paths
        self.includeModules = includeModules
    }

    /// Hand-written so every field but `command` is optional — the same
    /// courtesy `ActivityContent` extends to scripts writing JSON by hand.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decode(LedgeCommand.self, forKey: .command)
        activity = try container.decodeIfPresent(Activity.self, forKey: .activity)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        content = try container.decodeIfPresent(ActivityContent.self, forKey: .content)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        paths = try container.decodeIfPresent([String].self, forKey: .paths)
    }
}

public struct LedgeResponse: Codable, Sendable {
    public var ok: Bool
    public var id: String?
    public var message: String?
    public var activities: [Activity]?
    public var count: Int?

    public init(
        ok: Bool,
        id: String? = nil,
        message: String? = nil,
        activities: [Activity]? = nil,
        count: Int? = nil
    ) {
        self.ok = ok
        self.id = id
        self.message = message
        self.activities = activities
        self.count = count
    }

    public static func failure(_ message: String) -> LedgeResponse {
        LedgeResponse(ok: false, message: message)
    }
}

/// One encoder/decoder pair, so the app and CLI can never drift on date format.
public enum LedgeCoding {
    /// ISO 8601 *with* fractional seconds.
    ///
    /// Plain `.iso8601` truncates to whole seconds, which silently rounds
    /// `--dwell 1.5` down to 1 and drifts every expiry that crosses the wire.
    /// Writing fractional seconds costs four characters and removes the class
    /// of bug entirely. Fidelity is milliseconds, which is far finer than
    /// anything the island animates.
    ///
    /// A format *style* rather than an `ISO8601DateFormatter`: the class isn't
    /// `Sendable`, and these are shared across the socket's I/O queue.
    private static let precise = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    /// Fallback for hand-written JSON, which rarely bothers with milliseconds.
    private static let whole = Date.ISO8601FormatStyle()

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(precise.format(date))
        }
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            // Accept both shapes: anything we wrote, and anything a person did.
            if let date = (try? precise.parse(raw)) ?? (try? whole.parse(raw)) { return date }
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected an ISO 8601 date, got \"\(raw)\"."
                )
            )
        }
        return decoder
    }()

    /// Encodes to a single line — the framing the socket protocol relies on.
    public static func line<T: Encodable>(_ value: T) throws -> Data {
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }
}

public extension Notification.Name {
    /// Posted when the user taps an action button in the expanded panel.
    ///
    /// Lives in Core so providers can listen for their own buttons without
    /// depending on the UI layer.
    static let ledgeActionInvoked = Notification.Name("com.ledge.actionInvoked")

    /// Posted when per-module appearance changes, so the scheduler can re-sort.
    ///
    /// Slot and priority preferences feed into ordering, and ordering is only
    /// recomputed when activities change — without this, dragging the position
    /// slider would do nothing until the next thing happened.
    static let ledgeAppearanceChanged = Notification.Name("com.ledge.appearanceChanged")

    /// Posted when a preference changes what display the island belongs on, so
    /// the window controller can put it there — or take it away — immediately
    /// rather than at the next launch.
    static let ledgeDisplayPreferenceChanged = Notification.Name("com.ledge.displayPreferenceChanged")
}
