import Foundation

/// Where the app listens and the CLI connects.
///
/// A Unix domain socket under Application Support, rather than a TCP port:
/// nothing outside this user account can reach it, there is no port to collide
/// with, and it dies with the machine. An island that anything on the network
/// could write to would be a genuinely bad idea.
public enum IsletSocket {
    public static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Islet", isDirectory: true)
    }

    public static var path: String {
        // Unix socket paths are capped near 104 bytes, so this stays short.
        directory.appendingPathComponent("islet.sock").path
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
public enum IsletCommand: String, Codable, Sendable {
    case present
    case update
    case end
    case endAll
    case list
    case ping
}

public struct IsletRequest: Codable, Sendable {
    public var command: IsletCommand
    public var activity: Activity?
    public var id: String?
    public var content: ActivityContent?
    public var source: String?

    public init(
        command: IsletCommand,
        activity: Activity? = nil,
        id: String? = nil,
        content: ActivityContent? = nil,
        source: String? = nil
    ) {
        self.command = command
        self.activity = activity
        self.id = id
        self.content = content
        self.source = source
    }
}

public struct IsletResponse: Codable, Sendable {
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

    public static func failure(_ message: String) -> IsletResponse {
        IsletResponse(ok: false, message: message)
    }
}

/// One encoder/decoder pair, so the app and CLI can never drift on date format.
public enum IsletCoding {
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
    static let isletActionInvoked = Notification.Name("com.islet.actionInvoked")
}
