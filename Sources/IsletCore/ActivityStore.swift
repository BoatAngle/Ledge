import Foundation
import Observation

/// Owns every live activity and resolves them into a single `IslandComposition`.
///
/// This is the whole scheduling brain. Providers and socket clients only ever
/// `present`/`end`; deciding who is on screen — and in which slot — happens
/// here, in one place, so the rules stay auditable.
@MainActor
@Observable
public final class ActivityStore {
    /// Live activities keyed by id.
    private(set) public var activities: [String: Activity] = [:]

    /// Whether the user has the panel open. Set by the renderer.
    public var isExpanded: Bool = false {
        didSet { if isExpanded != oldValue { recompose() } }
    }

    /// Which activity the user chose to expand. `nil` means "the primary".
    public var focusedActivityID: String? {
        didSet { if focusedActivityID != oldValue { recompose() } }
    }

    /// The current resolved layout. Observing this is enough to render.
    private(set) public var composition: IslandComposition = .idle

    /// Fires whenever an activity is newly added, so the renderer can play the
    /// attention bounce rather than a silent geometry change.
    private(set) public var lastArrivalID: String?

    private var reaper: Timer?

    public init() {
        startReaper()
    }

    isolated deinit {
        reaper?.invalidate()
    }

    // MARK: - Mutation

    /// Insert a new activity, or merge into an existing one with the same id.
    @discardableResult
    public func present(_ activity: Activity) -> Activity {
        var incoming = activity
        let isNew = activities[activity.id] == nil

        if let existing = activities[activity.id] {
            // Preserve the original creation time so "how long has this been
            // running" stays meaningful across updates.
            incoming.createdAt = existing.createdAt
        }
        incoming.updatedAt = Date()

        // A transient with no explicit lifetime gets the default HUD dwell.
        if incoming.kind == .transient, incoming.expiresAt == nil {
            incoming.expiresAt = Date().addingTimeInterval(Self.transientDwell)
        }

        activities[incoming.id] = incoming
        if isNew { lastArrivalID = incoming.id }
        recompose()
        return incoming
    }

    /// Update just the content of an existing activity, leaving scheduling
    /// metadata alone. Returns false if there is nothing with that id.
    @discardableResult
    public func update(id: String, content: ActivityContent) -> Bool {
        guard var existing = activities[id] else { return false }
        existing.content = content
        existing.updatedAt = Date()
        existing.isExpandable = content.hasExpandedContent
        // Touching a transient restarts its dwell, so a stream of volume taps
        // reads as one continuous HUD rather than a stutter.
        if existing.kind == .transient {
            existing.expiresAt = Date().addingTimeInterval(Self.transientDwell)
        }
        activities[id] = existing
        recompose()
        return true
    }

    @discardableResult
    public func end(id: String) -> Bool {
        guard activities.removeValue(forKey: id) != nil else { return false }
        if focusedActivityID == id { focusedActivityID = nil }
        recompose()
        return true
    }

    /// Ends everything posted by one source — how the CLI cleans up after a
    /// script that died without calling `end`.
    @discardableResult
    public func endAll(source: String? = nil) -> Int {
        let doomed = activities.values.filter { source == nil || $0.source == source }
        for activity in doomed { activities.removeValue(forKey: activity.id) }
        if !doomed.isEmpty { recompose() }
        return doomed.count
    }

    /// Convenience for the built-in modules: post a HUD that retires itself.
    public func flash(
        id: String,
        nativeView: NativeViewKind,
        content: ActivityContent,
        priority: ActivityPriority = .system,
        dwell: TimeInterval = ActivityStore.transientDwell
    ) {
        present(
            Activity(
                id: id,
                source: "system",
                kind: .transient,
                priority: priority,
                content: content,
                nativeView: nativeView,
                expiresAt: Date().addingTimeInterval(dwell),
                isExpandable: false
            )
        )
    }

    // MARK: - Scheduling

    /// How long a HUD sits on screen with no further updates.
    public static let transientDwell: TimeInterval = 1.6

    private func recompose() {
        let now = Date()
        let live = activities.values
            .filter { !$0.isExpired(at: now) }
            .sorted { lhs, rhs in
                if lhs.effectivePriority != rhs.effectivePriority {
                    return lhs.effectivePriority > rhs.effectivePriority
                }
                // Newer first, so the most recent thing to happen leads.
                return lhs.updatedAt > rhs.updatedAt
            }

        guard let primary = live.first else {
            composition = .idle
            if isExpanded { isExpanded = false }
            return
        }

        // The second slot only ever holds an *ongoing* activity. A transient
        // HUD takes the primary slot and pushes the incumbent to minimal — it
        // never appears as the little detached circle itself, which is what
        // makes a volume tap read as an interruption rather than a companion.
        let secondary = live.dropFirst().first { $0.kind == .ongoing }

        let mode: IslandMode
        if isExpanded {
            mode = .expanded
        } else if secondary != nil {
            mode = .split
        } else {
            mode = .compact
        }

        let expanded: Activity? = isExpanded
            ? (focusedActivityID.flatMap { id in live.first { $0.id == id } } ?? primary)
            : nil

        composition = IslandComposition(
            primary: primary,
            secondary: secondary,
            expandedActivity: expanded,
            mode: mode,
            all: live
        )
    }

    // MARK: - Expiry

    private func startReaper() {
        // 4 Hz is plenty: transients live for well over a second, and this
        // costs nothing while idle.
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reap() }
        }
        RunLoop.main.add(timer, forMode: .common)
        reaper = timer
    }

    private func reap() {
        let now = Date()
        let expired = activities.values.filter { $0.isExpired(at: now) }
        guard !expired.isEmpty else { return }
        for activity in expired { activities.removeValue(forKey: activity.id) }
        recompose()
    }
}
