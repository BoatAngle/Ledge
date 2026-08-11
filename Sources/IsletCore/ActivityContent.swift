import Foundation

/// A colour carried across the wire. Kept free of AppKit/SwiftUI so `IsletCore`
/// stays linkable from the CLI.
public struct IsletColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Accepts `#RRGGBB`, `#RRGGBBAA`, or a handful of names so CLI callers can
    /// write `--tint orange` instead of a hex triplet.
    public init?(parsing raw: String) {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if let named = Self.named[s] {
            self = named
            return
        }
        var hex = s
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8, let value = UInt32(hex, radix: 16) else { return nil }
        if hex.count == 6 {
            self.init(
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255
            )
        } else {
            self.init(
                red: Double((value >> 24) & 0xFF) / 255,
                green: Double((value >> 16) & 0xFF) / 255,
                blue: Double((value >> 8) & 0xFF) / 255,
                alpha: Double(value & 0xFF) / 255
            )
        }
    }

    public static let white = IsletColor(red: 1, green: 1, blue: 1)
    public static let accent = IsletColor(red: 0.39, green: 0.55, blue: 0.98)

    public static let red = named["red"]!
    public static let orange = named["orange"]!
    public static let yellow = named["yellow"]!
    public static let green = named["green"]!
    public static let cyan = named["cyan"]!
    public static let teal = named["teal"]!
    public static let mint = named["mint"]!
    public static let blue = named["blue"]!
    public static let indigo = named["indigo"]!
    public static let purple = named["purple"]!
    public static let pink = named["pink"]!
    public static let gray = named["gray"]!

    /// Stable ordering for swatch grids. `named` is a dictionary, so iterating
    /// it directly would shuffle the palette on every launch.
    public static let paletteOrder = [
        "red", "orange", "yellow", "green", "mint", "teal",
        "cyan", "blue", "indigo", "purple", "pink", "gray",
    ]

    /// The palette the `--tint` flag resolves against.
    public static let named: [String: IsletColor] = [
        "red": IsletColor(red: 1.00, green: 0.27, blue: 0.23),
        "orange": IsletColor(red: 1.00, green: 0.58, blue: 0.00),
        "yellow": IsletColor(red: 1.00, green: 0.80, blue: 0.00),
        "green": IsletColor(red: 0.20, green: 0.84, blue: 0.29),
        "mint": IsletColor(red: 0.00, green: 0.78, blue: 0.75),
        "teal": IsletColor(red: 0.19, green: 0.69, blue: 0.78),
        "cyan": IsletColor(red: 0.35, green: 0.78, blue: 0.98),
        "blue": IsletColor(red: 0.00, green: 0.48, blue: 1.00),
        "indigo": IsletColor(red: 0.35, green: 0.34, blue: 0.84),
        "purple": IsletColor(red: 0.69, green: 0.32, blue: 0.87),
        "pink": IsletColor(red: 1.00, green: 0.18, blue: 0.33),
        "gray": IsletColor(red: 0.56, green: 0.56, blue: 0.58),
        "white": .white,
    ]
}

/// How to draw the little glyph that represents an activity.
public enum ActivityIcon: Codable, Hashable, Sendable {
    /// An SF Symbol name, e.g. `"arrow.down.circle.fill"`.
    case symbol(String)
    /// A bundle identifier — the island renders that app's real icon.
    case bundleIdentifier(String)
    /// A PNG/JPEG on disk.
    case file(String)
    /// Raw base64 image data, for callers with no file to point at.
    case data(String)
}

/// Determinate or indeterminate progress.
public struct ActivityProgress: Codable, Hashable, Sendable {
    /// `nil` means indeterminate — the island shows a looping shimmer instead
    /// of a filled track.
    public var fraction: Double?
    /// Optional short label rendered beside the track, e.g. `"3 of 12"`.
    public var label: String?

    public init(fraction: Double? = nil, label: String? = nil) {
        self.fraction = fraction.map { min(max($0, 0), 1) }
        self.label = label
    }

    public var isIndeterminate: Bool { fraction == nil }
}

/// A tappable button rendered in the expanded presentation.
public struct ActivityAction: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var symbol: String?
    /// Opened when the action fires. Lets a CLI caller wire a button to
    /// anything addressable by URL without holding a connection open.
    public var url: String?
    public var isDestructive: Bool

    public init(
        id: String,
        title: String,
        symbol: String? = nil,
        url: String? = nil,
        isDestructive: Bool = false
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.url = url
        self.isDestructive = isDestructive
    }
}

/// A key/value row in the expanded presentation.
public struct ActivityDetail: Codable, Hashable, Sendable {
    public var label: String
    public var value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// Everything needed to draw an activity in every presentation state.
///
/// Deliberately declarative and `Codable`: an external process describes what
/// it wants shown, and the island decides how that maps onto each state. Same
/// content struct drives minimal, compact, and expanded — mirroring how
/// `ActivityKit` asks for one content model and several view builders.
public struct ActivityContent: Codable, Hashable, Sendable {
    public var title: String
    public var subtitle: String?
    public var body: String?

    public var icon: ActivityIcon?
    /// Overrides `icon` on the trailing side of the compact presentation.
    public var trailingIcon: ActivityIcon?
    /// Short text pinned to the trailing side, e.g. a countdown or `"84%"`.
    public var trailingText: String?

    public var tint: IsletColor?
    public var progress: ActivityProgress?
    public var details: [ActivityDetail]
    public var actions: [ActivityAction]

    /// Counts up or down from this instant without further updates from the
    /// client — the island animates it locally at display refresh rate.
    public var countdownTarget: Date?
    public var countUpFrom: Date?

    public init(
        title: String,
        subtitle: String? = nil,
        body: String? = nil,
        icon: ActivityIcon? = nil,
        trailingIcon: ActivityIcon? = nil,
        trailingText: String? = nil,
        tint: IsletColor? = nil,
        progress: ActivityProgress? = nil,
        details: [ActivityDetail] = [],
        actions: [ActivityAction] = [],
        countdownTarget: Date? = nil,
        countUpFrom: Date? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.icon = icon
        self.trailingIcon = trailingIcon
        self.trailingText = trailingText
        self.tint = tint
        self.progress = progress
        self.details = details
        self.actions = actions
        self.countdownTarget = countdownTarget
        self.countUpFrom = countUpFrom
    }

    /// True when there is genuinely more to show than the compact presentation
    /// already carries. Drives whether expanding is offered at all — Apple's
    /// island does not expand for content that has nothing extra to say.
    public var hasExpandedContent: Bool {
        body != nil || !details.isEmpty || !actions.isEmpty || progress != nil || subtitle != nil
    }

    /// Hand-written decoding.
    ///
    /// The synthesized initialiser insists on `details` and `actions` being
    /// present, which would make the smallest valid payload
    /// `{"title":"Hi","details":[],"actions":[]}`. Since the whole point of the
    /// JSON protocol is that a shell script can pipe a literal into `islet
    /// --stdin`, every field except `title` is optional.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        icon = try container.decodeIfPresent(ActivityIcon.self, forKey: .icon)
        trailingIcon = try container.decodeIfPresent(ActivityIcon.self, forKey: .trailingIcon)
        trailingText = try container.decodeIfPresent(String.self, forKey: .trailingText)
        tint = try container.decodeIfPresent(IsletColor.self, forKey: .tint)
        progress = try container.decodeIfPresent(ActivityProgress.self, forKey: .progress)
        details = try container.decodeIfPresent([ActivityDetail].self, forKey: .details) ?? []
        actions = try container.decodeIfPresent([ActivityAction].self, forKey: .actions) ?? []
        countdownTarget = try container.decodeIfPresent(Date.self, forKey: .countdownTarget)
        countUpFrom = try container.decodeIfPresent(Date.self, forKey: .countUpFrom)
    }
}
