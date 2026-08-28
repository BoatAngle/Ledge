import Foundation

/// Whether an activity sticks around or flashes past.
///
/// This is the distinction Apple never exposed as API but clearly implements:
/// a volume change and a food delivery are both "the island doing something",
/// but only one of them owns the island for the next twenty minutes.
public enum ActivityKind: String, Codable, Hashable, Sendable {
    /// Persists until explicitly ended (media, timers, downloads, a build).
    case ongoing
    /// Flashes, then retires on its own (volume, brightness, caps lock).
    case transient
}

/// Ordering for who gets the island when several things want it.
///
/// Higher wins. Transient activities temporarily outrank everything so a volume
/// tap still shows while music is playing, then hands the island straight back.
public struct ActivityPriority: RawRepresentable, Codable, Hashable, Comparable, Sendable {
    public var rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public static let background = ActivityPriority(rawValue: 100)
    public static let low = ActivityPriority(rawValue: 250)
    public static let normal = ActivityPriority(rawValue: 500)
    public static let high = ActivityPriority(rawValue: 750)
    /// Reserved for system HUDs that must never be swallowed.
    public static let system = ActivityPriority(rawValue: 900)
    /// Privacy indicators. Nothing outranks knowing your mic is hot.
    public static let critical = ActivityPriority(rawValue: 1000)
}

/// The kinds of activity the app renders with a purpose-built SwiftUI view
/// rather than the generic declarative layout.
///
/// External clients never set this — it exists so the built-in modules can have
/// album art, waveforms, and battery arcs without pushing that through a
/// serializable content model.
public enum NativeViewKind: String, Codable, Hashable, Sendable {
    case media
    case battery
    case volume
    case brightness
    case focus
    case capsLock
    case privacy
    case calendar
    case timer
    case download
    case weather
    /// The shelf that opens when files are dragged to the notch.
    case dropZone
}

/// One thing the island is currently reporting.
public struct Activity: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var source: String
    public var kind: ActivityKind
    public var priority: ActivityPriority
    public var content: ActivityContent
    public var nativeView: NativeViewKind?
    /// Which built-in module produced this, for per-module appearance.
    ///
    /// Separate from `id` because one module can post many activities — every
    /// running timer is its own activity but they all share the timer module's
    /// colour and size.
    public var module: String?

    /// When the activity was first posted.
    public var createdAt: Date
    /// Last time its content changed — used to re-trigger the attention pulse.
    public var updatedAt: Date
    /// Auto-retire at this instant. Always set for `.transient`.
    public var expiresAt: Date?

    /// Whether a click should expand it. Suppressed for HUDs that have nothing
    /// more to say.
    public var isExpandable: Bool

    /// Opened when the user clicks the activity, the way tapping Apple's island
    /// opens the owning app.
    public var openURL: String?

    public init(
        id: String = UUID().uuidString,
        source: String = "ledge",
        kind: ActivityKind = .ongoing,
        priority: ActivityPriority = .normal,
        content: ActivityContent,
        nativeView: NativeViewKind? = nil,
        module: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        expiresAt: Date? = nil,
        isExpandable: Bool? = nil,
        openURL: String? = nil
    ) {
        self.id = id
        self.source = source
        self.kind = kind
        self.priority = priority
        self.content = content
        self.nativeView = nativeView
        self.module = module
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
        self.isExpandable = isExpandable ?? content.hasExpandedContent
        self.openURL = openURL
    }

    public func isExpired(at now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return now >= expiresAt
    }

    /// True for activities a built-in module owns and keeps up to date.
    ///
    /// The distinction matters wherever "everything" is too blunt an answer:
    /// clearing the island should not cancel a running timer, and nothing
    /// arriving over the socket may claim to be one of these.
    public var isModuleOwned: Bool { module != nil }

    /// Schemes an externally posted activity may ask the island to open.
    ///
    /// Deliberately short. Every entry here hands the URL to LaunchServices,
    /// which is the same trust level as clicking a link anywhere else on the
    /// Mac — but `file:` is not: `file:///Applications/Utilities/Terminal.app`
    /// is a URL, and "click this to see your download" is a plausible enough
    /// label that someone would. A script gets to point the island at the web
    /// and at an email address. It does not get to launch things off disk.
    public static let externallyOpenableSchemes: Set<String> = ["http", "https", "mailto"]

    /// The form an activity may take when it arrives over the socket.
    ///
    /// The socket is owner-only (0600 in a 0700 directory), so this is not a
    /// boundary against another *user* — it is a boundary against any process
    /// running as you, which on a Mac is a much larger set than the programs
    /// you would knowingly grant the island to. Four things a client must not
    /// be able to do:
    ///
    /// 1. **Claim a module.** `module` drives per-module appearance and marks
    ///    an activity as system-owned; a client setting `"module":
    ///    "system.media"` inherits the user's Now Playing colours and becomes
    ///    immune to the clears meant for it.
    /// 2. **Claim a native view.** `nativeView` selects a purpose-built
    ///    renderer — album art, the privacy dot, the waveform. The privacy dot
    ///    in particular is the one thing on the island that must never lie.
    /// 3. **Outrank the system.** Priority is clamped below `.system`, so a
    ///    script cannot bury a privacy indicator or a volume HUD underneath a
    ///    banner of its own.
    /// 4. **Open anything.** See `externallyOpenableSchemes`.
    public func sanitizedForExternalClient() -> Activity {
        var copy = self
        copy.module = nil
        copy.nativeView = nil
        copy.priority = min(priority, .high)
        copy.openURL = Self.sanitizedOpenURL(openURL)
        copy.content.actions = content.actions.map { action in
            var action = action
            action.url = Self.sanitizedOpenURL(action.url)
            return action
        }
        return copy
    }

    private static func sanitizedOpenURL(_ raw: String?) -> String? {
        guard let raw,
              let scheme = URL(string: raw)?.scheme?.lowercased(),
              externallyOpenableSchemes.contains(scheme)
        else { return nil }
        return raw
    }

    /// Effective priority, boosting transients so they cut in front.
    ///
    /// `appearance` folds in the user's per-module nudges. Slot preferences are
    /// expressed as priority bias rather than as a separate placement pass:
    /// "prefer the small circle" *is* "rank below whatever else is live", and
    /// one ordering rule is far easier to reason about than two.
    func effectivePriority(_ appearance: ModuleAppearance? = nil) -> Int {
        var value = priority.rawValue
        if let appearance {
            value += appearance.priorityOffset
            switch appearance.slot {
            case .automatic: break
            case .leading: value += 300
            case .minimal: value -= 300
            }
        }
        return kind == .transient ? value + 10_000 : value
    }
}
