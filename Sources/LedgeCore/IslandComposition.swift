import Foundation

/// What shape the island is currently in.
///
/// These are the states Apple's Dynamic Island actually moves between. Naming
/// them explicitly keeps the renderer honest: every visual is a function of the
/// mode, never of ad-hoc booleans scattered through the view tree.
public enum IslandMode: String, Equatable, Sendable {
    /// Nothing to say. On a notched Mac this is the bare notch; on a notchless
    /// display it is a hairline pill (or nothing, per preference).
    case idle
    /// One activity, hugging both sides of the camera housing.
    case compact
    /// Two concurrent activities: one compact, one detached as a small circle
    /// to the trailing side — the split-pill look.
    case split
    /// The panel is down.
    case expanded
}

/// Which slot a given activity occupies in the current layout.
public enum PresentationSlot: String, Equatable, Sendable {
    case compactLeading
    case compactTrailing
    case minimal
    case expanded
}

/// A resolved snapshot of what the island should be showing right now.
///
/// The scheduler produces this; the renderer consumes it and nothing else.
public struct IslandComposition: Equatable, Sendable {
    /// Owns the compact leading + trailing slots.
    public var primary: Activity?
    /// Detached minimal circle, when a second activity is live.
    public var secondary: Activity?
    /// Whatever is rendered in the drop-down panel.
    public var expandedActivity: Activity?
    public var mode: IslandMode
    /// Everything live, priority-ordered — the expanded panel pages through
    /// these when more than two things are running.
    public var all: [Activity]

    public static let idle = IslandComposition(mode: .idle, all: [])

    public init(
        primary: Activity? = nil,
        secondary: Activity? = nil,
        expandedActivity: Activity? = nil,
        mode: IslandMode,
        all: [Activity] = []
    ) {
        self.primary = primary
        self.secondary = secondary
        self.expandedActivity = expandedActivity
        self.mode = mode
        self.all = all
    }

    public var isIdle: Bool { mode == .idle }

    /// A stable key that changes only when the *structure* changes, so the
    /// renderer can animate geometry separately from content.
    public var structureKey: String {
        "\(mode.rawValue)|\(primary?.id ?? "-")|\(secondary?.id ?? "-")"
    }
}
