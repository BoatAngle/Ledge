import IsletCore
import SwiftUI

/// The island. Everything visible lives under this view.
///
/// The view is a pure function of `store.composition` — it never decides *what*
/// to show, only how. All scheduling stays in `ActivityStore`.
public struct IslandRootView: View {
    public var store: ActivityStore
    public var metrics: IslandMetrics
    /// Files parked on the island, rendered in place of the generic panel when
    /// the shelf is what's showing.
    public var shelf: DropShelf?
    /// Interaction preferences. Injected rather than reached for, so the view
    /// stays testable.
    public var settings: IsletSettings
    /// Called when the island's interactive footprint changes, so the window
    /// can keep its click-through region in sync.
    public var onFootprintChange: (CGSize) -> Void

    @State private var goo = GooDriver()
    @State private var isHovering = false
    @State private var hoverTask: Task<Void, Never>?
    /// Where the pointer was when the current dwell timer started. The timer
    /// restarts whenever the pointer strays far from this anchor, so only a
    /// pointer that actually RESTS on the island opens the panel.
    @State private var dwellAnchor: CGPoint?
    @State private var measuredPanelHeight: CGFloat = IslandGeometry.expandedMinHeight

    public init(
        store: ActivityStore,
        metrics: IslandMetrics,
        shelf: DropShelf? = nil,
        settings: IsletSettings = .shared,
        onFootprintChange: @escaping (CGSize) -> Void = { _ in }
    ) {
        self.store = store
        self.metrics = metrics
        self.shelf = shelf
        self.settings = settings
        self.onFootprintChange = onFootprintChange
    }

    // MARK: Derived geometry

    private var composition: IslandComposition { store.composition }
    private var mode: IslandMode { composition.mode }

    private var theme: IslandTheme { .preset(settings.theme) }

    /// Colour and size for an activity, after the user's per-module overrides.
    private func style(for activity: Activity?) -> ActivityStyle {
        // Read the revision so `@Observable` registers a dependency: the
        // appearance itself lives in UserDefaults, which observation can't see,
        // and without this the island keeps its old colours until something
        // else forces a redraw.
        _ = settings.appearanceRevision
        guard let activity else { return .placeholder }
        let appearance = activity.module.map { settings.appearance(for: $0) }
        return ActivityStyle.resolve(activity, appearance: appearance)
    }

    /// The panel's height, taken from what the content actually measured.
    ///
    /// Estimating this from a table of constants was always going to drift the
    /// moment anyone changed a font; the panel reports its own natural height
    /// through a preference and the island grows to match.
    private var expandedHeight: CGFloat {
        guard composition.expandedActivity != nil else {
            return IslandGeometry.expandedMinHeight
        }
        // Plus the strip that keeps the compact glyphs beside the camera.
        return measuredPanelHeight + metrics.notchSize.height
    }

    private var totalSize: CGSize {
        IslandGeometry.size(mode: mode, metrics: metrics, expandedHeight: expandedHeight)
    }

    /// The notch-shaped body, which in `.split` excludes the detached circle.
    private var bodySize: CGSize {
        mode == .split
            ? IslandGeometry.size(mode: .compact, metrics: metrics)
            : totalSize
    }

    private var minimalFrame: CGRect? {
        IslandGeometry.minimalFrame(mode: mode, metrics: metrics, in: totalSize)
    }

    private var fillet: CGFloat {
        mode == .idle && metrics.hasPhysicalNotch ? 0 : IslandGeometry.topFillet
    }

    /// Blank width reserved on the leading side in `.split`.
    ///
    /// Without it the whole footprint gets centred in the window, which drags
    /// the compact body left by half the detached circle's width — so the
    /// island's notch gap stops lining up with the actual camera. Reserving the
    /// same space on the left keeps the body centred on the hardware and lets
    /// the circle hang off to the right, which is what Apple's does.
    private var leadingReserve: CGFloat {
        mode == .split ? IslandGeometry.splitGap + IslandGeometry.minimalDiameter : 0
    }

    /// Idle casts nothing — a shadow under the camera housing would give the
    /// whole illusion away.
    private var shadowSpec: IslandDesign.ShadowSpec {
        switch mode {
        case .idle: return .none
        case .expanded: return .raised
        case .compact, .split: return .resting
        }
    }

    private var footprint: CGSize {
        CGSize(
            width: totalSize.width + fillet * 2 + leadingReserve,
            height: totalSize.height
        )
    }

    // MARK: Body

    public var body: some View {
        // Top-leading throughout. Centring would work for the symmetric compact
        // state but silently mis-places everything in `.split`, where the body
        // is narrower than the footprint.
        ZStack(alignment: .topLeading) {
            IslandSilhouette(
                bodySize: bodySize,
                minimalFrame: minimalFrame,
                topFillet: fillet,
                bottomRadius: IslandGeometry.bottomRadius(for: mode, metrics: metrics)
                    * theme.bottomRadiusScale,
                goo: goo.radius,
                hasDepth: mode != .idle,
                opaqueTopHeight: metrics.notchSize.height
            )
            .islandShadow(shadowSpec)
            .offset(x: leadingReserve)

            content
                .frame(width: bodySize.width, height: bodySize.height, alignment: .top)
                .offset(x: fillet + leadingReserve)

            if let minimalFrame, let secondary = composition.secondary {
                MinimalView(
                    activity: secondary,
                    diameter: minimalFrame.width,
                    style: style(for: secondary)
                )
                    .offset(x: fillet + leadingReserve + minimalFrame.minX, y: minimalFrame.minY)
                    // Scale stays — the circle births out of the metaball
                    // merge — but the fade softens into a blur.
                    .transition(ScaleTransition(0.3).combined(with: BlurReplaceTransition(configuration: .downUp)))
            }
        }
        .frame(width: footprint.width, height: footprint.height, alignment: .topLeading)
        // Retrigger-safe by construction: a second arrival inside the first
        // pulse restarts the keyframes instead of fighting a sleeping Task.
        .keyframeAnimator(initialValue: 1.0, trigger: store.lastArrivalID) { view, scale in
            view.scaleEffect(scale, anchor: .top)
        } keyframes: { _ in
            // A flat 1.0 → 1.0 track when arrivals are muted — and while the
            // panel is open: bouncing 468pt of content someone is reading is
            // not a nudge, it's a shove.
            let peak = settings.animateArrivals && mode != .expanded ? 1.045 : 1.0
            KeyframeTrack(\.self) {
                SpringKeyframe(peak, duration: 0.14, spring: Spring(response: 0.28, dampingRatio: 0.85))
                SpringKeyframe(1.0, duration: 0.50, spring: Spring(response: 0.40, dampingRatio: 0.60))
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location): handleHoverMove(location)
            case .ended: handleHoverExit()
            }
        }
        .onTapGesture { handleTap() }
        .animation(IslandMotion.shape, value: composition.structureKey)
        // Open carries overshoot (an invitation); close settles dead (an
        // acknowledgment). The asymmetry is deliberate, not a mirrored reverse.
        .animation(mode == .expanded ? IslandMotion.expand : IslandMotion.collapse, value: mode)
        .animation(IslandMotion.content, value: composition.expandedActivity?.id)
        .animation(IslandMotion.shape, value: measuredPanelHeight)
        .onChange(of: mode) { old, new in
            // The metaball is for the silhouette changing SHAPE — growing off
            // the notch, splitting, merging. Keyed to mode rather than
            // structureKey so a transient seizing primary (a volume tap during
            // music) no longer fires blur for what is really a content swap,
            // and the expand morph is left to its spring.
            guard old != .expanded, new != .expanded else { return }
            goo.pulse()
        }
        .onChange(of: footprint) { _, new in
            onFootprintChange(new)
        }
        .onAppear { onFootprintChange(footprint) }
        .onPreferenceChange(ExpandedHeightKey.self) { height in
            guard height > 0 else { return }
            measuredPanelHeight = height
        }
        .islandTheme(theme)
    }

    // MARK: Content per mode

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .idle:
            Color.clear
        case .compact, .split:
            compactStrip(height: bodySize.height)
        case .expanded:
            VStack(spacing: 0) {
                compactStrip(height: metrics.notchSize.height)
                if let activity = composition.expandedActivity,
                   activity.nativeView == .dropZone, let shelf, !shelf.files.isEmpty {
                    DropShelfView(shelf: shelf)
                        .transition(Self.panelTransition)
                } else if let activity = composition.expandedActivity {
                    ExpandedView(
                        activity: activity,
                        siblings: composition.all,
                        style: style(for: activity),
                        onSelect: { store.focusedActivityID = $0 },
                        onAction: { perform($0) },
                        onDismiss: { collapse() },
                        onOpen: {
                            if let url = activity.openURL {
                                open(url)
                                collapse()
                            }
                        }
                    )
                    // Identity keyed to the activity, so paging between
                    // siblings is a real swap rather than an in-place teleport.
                    .id(activity.id)
                    .transition(Self.panelTransition)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Shape leads, content follows: panel content blurs in one beat behind
    /// the island's growth, and on close it clears quickly so the shrinking
    /// shape never crops live text.
    private static var panelTransition: some Transition {
        AsymmetricTransition(
            // A whisker behind the shape, not a beat — the original 80ms
            // stagger read as the panel arriving in two pieces.
            insertion: BlurReplaceTransition(configuration: .downUp)
                .combined(with: OffsetTransition(CGSize(width: 0, height: -10)))
                .animation(IslandMotion.content.delay(0.03)),
            removal: BlurReplaceTransition(configuration: .downUp)
                .animation(.smooth(duration: 0.14))
        )
    }

    /// Leading glyph, a gap the width of the camera housing, trailing glyph.
    private func compactStrip(height: CGFloat) -> some View {
        HStack(spacing: 0) {
            Group {
                if let primary = composition.primary {
                    CompactLeadingView(
                        activity: primary,
                        height: height,
                        style: style(for: primary)
                    )
                }
            }
            .frame(width: sidePadding(for: bodySize.width), height: height)

            Color.clear.frame(width: metrics.notchSize.width, height: height)

            Group {
                if let primary = composition.primary {
                    CompactTrailingView(
                        activity: primary,
                        height: height,
                        style: style(for: primary)
                    )
                }
            }
            .frame(width: sidePadding(for: bodySize.width), height: height)
        }
        .frame(height: height)
        .animation(IslandMotion.content, value: composition.primary?.id)
    }

    private func sidePadding(for width: CGFloat) -> CGFloat {
        max(0, (width - metrics.notchSize.width) / 2)
    }

    // MARK: Interaction

    /// How far the pointer may drift before it no longer counts as resting.
    private static let dwellSlack: CGFloat = 8

    /// True when the island's screen has no menu bar — a full-screen app.
    ///
    /// Checked on demand at hover time rather than observed: no polling, no
    /// plumbing, and worst case (letterboxed full screen reporting oddly) the
    /// guard simply doesn't engage. Users who auto-hide the menu bar
    /// permanently lose hover-expand and keep click-to-expand — a fair trade
    /// for never opening a panel over a film.
    private static var hostScreenIsFullScreen: Bool {
        guard let screen = NSScreen.islandHost else { return false }
        return screen.frame.maxY - screen.visibleFrame.maxY < 1
    }

    /// The dwell only runs while the pointer is RESTING. A pointer in transit
    /// — heading for the menu bar, a tab, a window control — keeps moving, so
    /// its timer keeps restarting and nothing ever opens in its path. That,
    /// not the delay value, is what keeps the island out of the way.
    private func handleHoverMove(_ location: CGPoint) {
        isHovering = true
        guard settings.expandOnHover, !store.isExpanded else { return }
        guard !composition.isIdle, composition.primary?.isExpandable == true else { return }
        // Full screen: shoving the pointer to the top edge is the "reveal the
        // menu bar" gesture, and it rests there — exactly a dwell. Opening a
        // panel over someone's movie on that gesture is the definition of
        // being in the way. (Clicking the island still expands it.)
        guard !Self.hostScreenIsFullScreen else { return }

        if let anchor = dwellAnchor,
           hypot(location.x - anchor.x, location.y - anchor.y) <= Self.dwellSlack {
            return // Still resting; let the running timer finish.
        }

        dwellAnchor = location
        hoverTask?.cancel()
        hoverTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(settings.hoverDelay)))
            guard !Task.isCancelled, isHovering else { return }
            expand()
        }
    }

    private func handleHoverExit() {
        isHovering = false
        dwellAnchor = nil
        hoverTask?.cancel()
        guard store.isExpanded else { return }
        // Leaving closes, after a beat, so a cursor clipping the corner on
        // its way somewhere else doesn't slam the panel shut.
        hoverTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, !isHovering else { return }
            collapse()
        }
    }

    private func handleTap() {
        if store.isExpanded {
            // A background tap on the open panel just puts it away. Opening
            // the owning app lives on the header row — an accidental
            // hover-expansion used to punish the reflex "get out of my way"
            // click with an app switch.
            collapse()
            return
        }
        if composition.primary?.isExpandable == true {
            expand()
        } else if let url = composition.primary?.openURL {
            open(url)
        }
    }

    private func expand() {
        guard !store.isExpanded else { return }
        withAnimation(IslandMotion.expand) {
            store.isExpanded = true
            // Pin what the user opened. Without this the expanded slot tracks
            // primary, and a volume tap mid-read teleports the panel's content
            // to the HUD and back.
            store.focusedActivityID = composition.primary?.id
        }
    }

    private func collapse() {
        guard store.isExpanded else { return }
        withAnimation(IslandMotion.collapse) {
            store.isExpanded = false
            store.focusedActivityID = nil
        }
    }

    private func perform(_ action: ActivityAction) {
        if let url = action.url { open(url) }
        NotificationCenter.default.post(
            name: .isletActionInvoked,
            object: nil,
            userInfo: ["actionID": action.id]
        )
    }

    private func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

}

