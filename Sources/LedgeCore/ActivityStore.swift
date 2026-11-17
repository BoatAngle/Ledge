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
        didSet { if isExpanded != oldValue, !isRecomposing { recompose() } }
    }

    /// Which activity the user chose to expand. `nil` means "the primary".
    public var focusedActivityID: String? {
        didSet { if focusedActivityID != oldValue, !isRecomposing { recompose() } }
    }

    /// When true the island presents nothing at all, whatever is live.
    ///
    /// Set by the app layer from the screen's actual state — today that means
    /// "a full-screen app owns the island's display". Activities keep running
    /// underneath: timers still fire, downloads still track, the privacy
    /// indicator still knows. Only the *presentation* stands down, so leaving
    /// full screen brings back the truth rather than a gap.
    ///
    /// It lives here, rather than in the renderer, because of the rule this
    /// file exists to enforce: one place decides what appears.
    public var isSuppressed: Bool = false {
        didSet { if isSuppressed != oldValue, !isRecomposing { recompose() } }
    }

    /// Guards the two `didSet` hooks above while a pass is already running.
    ///
    /// `recompose` can decide the panel has to close — the activity it was
    /// pinned to ended — and writing that decision back through the properties
    /// would re-enter the very function making it. One pass, one answer.
    private var isRecomposing = false

    /// The current resolved layout. Observing this is enough to render.
    private(set) public var composition: IslandComposition = .idle

    /// Fires whenever an activity is newly added, so the renderer can play the
    /// attention bounce rather than a silent geometry change.
    private(set) public var lastArrivalID: String?

    /// Per-module appearance lookup, supplied by the app.
    ///
    /// Injected rather than read from settings directly so `LedgeCore` stays
    /// free of any particular settings implementation, and so tests can drive
    /// the scheduler without touching `UserDefaults`.
    public var appearanceForModule: (@MainActor (String) -> ModuleAppearance)?

    private var reaper: Timer?

    public init() {}

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
        // Only ongoing work earns the attention bounce. A transient HUD —
        // volume, brightness — should appear, not celebrate: each spaced key
        // press re-creates its expired activity as "new", and bouncing the
        // island for every one of those reads as the island demanding
        // attention it wasn't owed.
        if isNew, incoming.kind == .ongoing { lastArrivalID = incoming.id }
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
        // The pin is deliberately NOT cleared here. Dropping it was what let
        // the open panel re-target to whatever led the sort; `recompose` now
        // sees a pin with nothing behind it and closes the panel instead.
        recompose()
        return true
    }

    /// End everything, or everything from one source — also how the CLI cleans
    /// up after a script that died without calling `end`.
    ///
    /// `includingModules` defaults to false, and that default is the whole
    /// point: `ledge end-all` and the "Clear the Notch" shortcut are reflexes —
    /// "get this off my screen" — and they were silently cancelling running
    /// timers, which is not a display action but a destructive one. Clearing
    /// the island now clears what scripts put there and leaves the modules to
    /// their own state.
    @discardableResult
    public func endAll(source: String? = nil, includingModules: Bool = false) -> Int {
        let doomed = activities.values.filter { activity in
            guard source == nil || activity.source == source else { return false }
            return includingModules || !activity.isModuleOwned
        }
        for activity in doomed { activities.removeValue(forKey: activity.id) }
        if !doomed.isEmpty { recompose() }
        return doomed.count
    }

    /// Convenience for the built-in modules: post a HUD that retires itself.
    public func flash(
        id: String,
        nativeView: NativeViewKind? = nil,
        module: String? = nil,
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
                module: module,
                expiresAt: Date().addingTimeInterval(dwell),
                isExpandable: false
            )
        )
    }

    /// Re-resolve the composition without any activity having changed.
    ///
    /// Needed when the *rules* change rather than the data — per-module slot
    /// and priority preferences feed the sort, so editing them has to trigger a
    /// pass or nothing moves until the next activity arrives.
    public func refresh() {
        recompose()
    }

    // MARK: - Scheduling

    /// How long a HUD sits on screen with no further updates.
    public static let transientDwell: TimeInterval = 1.6

    private func recompose() {
        isRecomposing = true
        defer { isRecomposing = false }
        // Every mutation lands here, so this is the one place that always knows
        // when the next expiry is. Re-arming from here means the reaper exists
        // exactly when something is due and not one moment longer.
        defer { scheduleReaper() }
        let now = Date()
        let live = activities.values
            .filter { !$0.isExpired(at: now) }
            .sorted { lhs, rhs in
                let left = effectivePriority(of: lhs)
                let right = effectivePriority(of: rhs)
                if left != right { return left > right }
                // Newer first, so the most recent thing to happen leads.
                return lhs.updatedAt > rhs.updatedAt
            }

        // Suppressed takes precedence over everything, including an open
        // panel: going full screen while the panel is down has to put it away,
        // not leave it hanging over the film.
        guard !isSuppressed, let primary = live.first else {
            composition = .idle
            if isExpanded { isExpanded = false }
            if focusedActivityID != nil { focusedActivityID = nil }
            return
        }

        // The second slot only ever holds an *ongoing* activity. A transient
        // HUD takes the primary slot and pushes the incumbent to minimal — it
        // never appears as the little detached circle itself, which is what
        // makes a volume tap read as an interruption rather than a companion.
        let secondary = live.dropFirst().first { $0.kind == .ongoing }

        // What the open panel is showing.
        //
        // When the user pinned something by opening it, that pin is absolute:
        // if the thing ENDS — the download finishes, the timer is cancelled —
        // the panel closes rather than quietly becoming a different activity
        // under a cursor already on its way to a button. Falling back to
        // `primary` here meant the buttons under your finger could belong to
        // something else by the time you pressed one.
        var expanded: Activity?
        if isExpanded {
            if let focusedActivityID {
                expanded = live.first { $0.id == focusedActivityID }
            } else {
                // Opened without a pin (`ledge expand` with no id): whatever
                // leads is the right answer.
                expanded = primary
            }
            if expanded == nil {
                isExpanded = false
                focusedActivityID = nil
            }
        }

        let mode: IslandMode
        if isExpanded {
            mode = .expanded
        } else if secondary != nil {
            mode = .split
        } else {
            mode = .compact
        }

        composition = IslandComposition(
            primary: primary,
            secondary: secondary,
            expandedActivity: expanded,
            mode: mode,
            all: live
        )
    }

    private func effectivePriority(of activity: Activity) -> Int {
        guard let module = activity.module, let appearanceForModule else {
            return activity.effectivePriority()
        }
        return activity.effectivePriority(appearanceForModule(module))
    }

    // MARK: - Expiry

    /// Arm a single timer for the next expiry, if there is one.
    ///
    /// This used to be a 4 Hz repeating timer, running for the life of the
    /// process. The comment said it "costs nothing while idle", and per tick
    /// that is nearly true — but it also meant the app woke the main thread
    /// four times a second, forever, to look at an empty dictionary. Nothing
    /// expires unpredictably: every `expiresAt` is known the moment it is set,
    /// so the right shape is one timer aimed at the earliest of them, re-armed
    /// whenever the set changes.
    ///
    /// A dwell measured in seconds tolerates 50ms of slack easily, and the
    /// tolerance lets the kernel fold this wakeup in with someone else's.
    private func scheduleReaper() {
        reaper?.invalidate()
        reaper = nil

        let now = Date()
        guard let next = activities.values.compactMap(\.expiresAt).min() else { return }

        let timer = Timer(
            timeInterval: max(0.05, next.timeIntervalSince(now)),
            repeats: false
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reap() }
        }
        timer.tolerance = 0.05
        // `.common` so a HUD still retires while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        reaper = timer
    }

    private func reap() {
        let now = Date()
        let expired = activities.values.filter { $0.isExpired(at: now) }
        guard !expired.isEmpty else {
            // Fired early (timer slack, a clock adjustment). Re-arm rather than
            // dropping the expiry on the floor.
            scheduleReaper()
            return
        }
        for activity in expired { activities.removeValue(forKey: activity.id) }
        recompose()
    }
}
