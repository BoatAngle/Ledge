import AppKit
import LedgeCore
import SwiftUI

/// Fills the panel and pins the island to the top edge.
///
/// Without this the hosting view centres the island's intrinsic frame inside a
/// 500pt-tall window, which parks it in the middle of the screen instead of
/// against the bezel.
struct IslandHostView: View {
    var store: ActivityStore
    var metrics: IslandMetrics
    var shelf: DropShelf
    var settings: LedgeSettings
    var onFootprintChange: (CGSize) -> Void

    var body: some View {
        VStack(spacing: 0) {
            IslandRootView(
                store: store,
                metrics: metrics,
                shelf: shelf,
                settings: settings,
                onFootprintChange: onFootprintChange
            )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// A hosting view that is transparent to clicks everywhere except the island,
/// and the drag destination for files dropped on the notch.
///
/// The panel has to be large enough to hold the fully expanded island, but a
/// 720×500 always-on-top window that swallowed clicks would make the top of the
/// screen unusable. So the view reports "not me" for anything outside the
/// island's current footprint, and the menu bar keeps working.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    /// Current island footprint. Updated by the controller as the island grows.
    var footprint: CGSize = .zero
    /// Used until SwiftUI reports a real footprint.
    ///
    /// Without it a zero footprint makes `hitTest` reject everything, and the
    /// island goes completely inert — no hover, no clicks, no drops — with no
    /// visible symptom. Falling back to the notch keeps it usable no matter how
    /// the first layout pass is ordered.
    var fallbackFootprint: CGSize = .zero

    /// The shelf that receives files dropped on the island.
    weak var shelf: DropShelf?

    /// Whether the island currently shows nothing. Supplied by the
    /// controller; an idle island must be completely click-transparent.
    var isIdle: () -> Bool = { true }

    /// Extra slack around the island so the cursor registers a hover just
    /// before it touches the edge. HOVER ONLY — clicks are tested against the
    /// exact footprint, because every point of click slack is a menu bar item
    /// or a toolbar button near the notch that stops working.
    private let hoverSlop: CGFloat = 10
    /// Drags get more forgiveness than hovers: a file en route to the notch
    /// is a coarser gesture than a pointer.
    private let dragSlop: CGFloat = 20

    // MARK: Drag destination

    // Every callback is gated on the drag's LOCATION. AppKit routes drags by
    // view geometry, not through the hitTest override below — ungated, the
    // whole invisible 648×510 panel was a drop target, and releasing a file
    // over your own document near the top of the screen fed it to the shelf
    // instead of the app you were aiming at.

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let incoming = urls(from: sender)
        guard !incoming.isEmpty, dragIsOverIsland(sender) else { return [] }
        // The pasteboard is already read to decide whether to accept; passing
        // the count on costs nothing and lets the island say how many.
        shelf?.dragEntered(count: incoming.count)
        // `.copy` because the shelf only ever references files — it never
        // moves or deletes what you drop on it.
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let incoming = urls(from: sender)
        guard !incoming.isEmpty else { return [] }
        guard dragIsOverIsland(sender) else {
            shelf?.dragExited()
            return []
        }
        shelf?.dragEntered(count: incoming.count)
        shelf?.dragUpdated()
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        shelf?.dragExited()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        !urls(from: sender).isEmpty && dragIsOverIsland(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = urls(from: sender)
        guard !urls.isEmpty, dragIsOverIsland(sender) else { return false }
        shelf?.accept(urls)
        return true
    }

    private func dragIsOverIsland(_ sender: any NSDraggingInfo) -> Bool {
        // When idle the visible target is just the notch, so the slop is
        // fatter — a drop target has to be hittable to be discoverable.
        let slack = isIdle() ? 24 : dragSlop
        return interactiveRect(slop: slack, belowBottom: slack)
            .contains(convert(sender.draggingLocation, from: nil))
    }

    private func urls(from sender: any NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let event = NSApp.currentEvent
        let isButtonEvent: Bool
        switch event?.type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp:
            isButtonEvent = true
        default:
            isButtonEvent = false
        }

        if isButtonEvent {
            // An idle island has no tap behavior, so it must not eat the
            // click either — the strip below the menu bar belongs to
            // whatever app is open, not to an invisible pill.
            guard !isIdle() else { return nil }
            // Clicks get the EXACT footprint: no slop, no reach below the
            // bottom edge. Slop on clicks turned menu bar items and toolbar
            // buttons near the notch into island taps.
            guard interactiveRect(slop: 0, belowBottom: 0).contains(point) else { return nil }
        } else {
            guard interactiveRect(slop: hoverSlop, belowBottom: hoverSlop).contains(point) else {
                return nil
            }
        }
        return super.hitTest(point)
    }

    /// The island's current rectangle in view coordinates, inflated by `slop`
    /// on the sides and top, and by `belowBottom` past its lower edge.
    private func interactiveRect(slop: CGFloat, belowBottom: CGFloat) -> CGRect {
        let active = footprint.width > 0 && footprint.height > 0 ? footprint : fallbackFootprint
        guard active.width > 0, active.height > 0 else { return .zero }
        return CGRect(
            x: (bounds.width - active.width) / 2 - slop,
            y: bounds.height - active.height - belowBottom,
            width: active.width + slop * 2,
            height: active.height + belowBottom + slop
        )
    }
}

/// The borderless panel the island lives in.
final class IslandPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false

        // Above the menu bar, and above full-screen apps, so the island behaves
        // like part of the hardware rather than part of any one Space.
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
    }

    // Never steal focus — typing should keep going to whatever the user was
    // actually working in.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns the panel, keeps it glued to the right screen, and tears it down.
@MainActor
public final class IslandWindowController {
    private var panel: IslandPanel?
    private var hostingView: PassthroughHostingView<IslandHostView>?
    public let shelf = DropShelf()
    private var outsideClickMonitor: Any?
    /// Tokens for the two block-based notification observers.
    ///
    /// `removeObserver(self)` does nothing for blocks registered with
    /// `addObserver(forName:object:queue:using:)` — they are owned by the token
    /// the call returns. Without these, a hide/show cycle left the old
    /// observers registered and added a second set, so one screen change
    /// rebuilt the panel twice.
    private var notificationObservers: [NSObjectProtocol] = []
    private let store: ActivityStore
    private let settings: LedgeSettings
    private var metrics: IslandMetrics

    /// Margin around the island inside the panel, giving the shadow and the
    /// metaball blur room to render.
    private let margin: CGFloat = 90

    public init(store: ActivityStore, settings: LedgeSettings = .shared) {
        self.store = store
        self.settings = settings
        self.metrics = NSScreen.islandHost?.ledgeMetrics
            ?? .synthesized(screenWidth: 1512)
    }

    public func show() {
        guard panel == nil else { return }
        shelf.attach(to: store)
        rebuild()
        observeScreenChanges()
        observeDisplayPreference()
        observePanelState()
    }

    public func hide() {
        shelf.detach()
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        setOutsideClickMonitor(active: false)
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
    }

    /// True on displays with real hardware to hug.
    public var isOnNotchedDisplay: Bool { metrics.hasPhysicalNotch }

    // MARK: - Construction

    /// Whether the island belongs on screen at all right now.
    ///
    /// On a Mac with a camera housing this is always true. On everything else
    /// — an external display, a Mac mini, an older MacBook — the island is a
    /// drawn rectangle floating under the menu bar, which is a taste some
    /// people don't share. `showOnNotchlessDisplays` is their answer, and until
    /// now it was a switch wired to nothing: stored, restored, described in the
    /// Settings window, and never once read.
    private func shouldShowIsland(on screen: NSScreen) -> Bool {
        screen.hasNotch || settings.showOnNotchlessDisplays
    }

    private func rebuild() {
        guard let screen = NSScreen.islandHost else { return }

        guard shouldShowIsland(on: screen) else {
            // Take it down, but keep the controller live: plugging the laptop's
            // own display back in has to bring the island straight back, and
            // the shelf must keep its files across the trip.
            panel?.orderOut(nil)
            panel = nil
            hostingView = nil
            metrics = screen.ledgeMetrics
            return
        }

        metrics = screen.ledgeMetrics

        let panelSize = CGSize(
            width: max(IslandGeometry.expandedWidth, metrics.notchSize.width + 240) + margin * 2,
            height: IslandGeometry.expandedMaxHeight + margin
        )
        // Centre on the camera housing rather than the screen. They coincide on
        // every Mac shipped so far, but deriving it from the measured notch
        // means a machine where they don't still lines up.
        let anchorX = screen.notchRect?.midX ?? screen.frame.midX
        let frame = NSRect(
            x: anchorX - panelSize.width / 2,
            y: screen.frame.maxY - panelSize.height,
            width: panelSize.width,
            height: panelSize.height
        )

        let existing = panel
        let panel = existing ?? IslandPanel(contentRect: frame)
        panel.setFrame(frame, display: true)

        if let hostingView {
            hostingView.fallbackFootprint = metrics.notchSize
            hostingView.rootView = makeRootView()
            hostingView.frame = CGRect(origin: .zero, size: panelSize)
        } else {
            // The root view's footprint callback writes through `hostingView`,
            // so that reference has to exist before SwiftUI's first layout pass
            // can fire it. Build with an inert placeholder, publish the
            // reference, then install the real root view.
            let view = PassthroughHostingView(
                rootView: IslandHostView(
                    store: store,
                    metrics: metrics,
                    shelf: shelf,
                    settings: settings,
                    onFootprintChange: { _ in }
                )
            )
            view.frame = CGRect(origin: .zero, size: panelSize)
            view.autoresizingMask = [.width, .height]
            view.shelf = shelf
            view.fallbackFootprint = metrics.notchSize
            view.isIdle = { [weak store] in store?.composition.isIdle ?? true }
            view.registerForDraggedTypes([.fileURL])
            panel.contentView = view
            hostingView = view
            view.rootView = makeRootView()
        }

        self.panel = panel
        panel.orderFrontRegardless()
    }

    private func makeRootView() -> IslandHostView {
        IslandHostView(
            store: store,
            metrics: metrics,
            shelf: shelf,
            settings: settings
        ) { [weak self] footprint in
            self?.hostingView?.footprint = footprint
        }
    }

    // MARK: - Environment changes

    private func observeScreenChanges() {
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Plugging in a display can move the menu bar to another screen
                // or change the notch's measured width; rebuild rather than
                // trying to patch the existing frame.
                self?.rebuild()
            }
        })
    }

    /// React to the notchless-display preference the moment it is flipped.
    ///
    /// The Settings footer used to promise this took effect "the next time
    /// Ledge opens". It doesn't have to: rebuilding is cheap, and a toggle in
    /// front of you that visibly does the thing is worth more than a sentence
    /// explaining why it hasn't yet.
    private func observeDisplayPreference() {
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: .ledgeDisplayPreferenceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        })
    }

    /// Collapse when the user clicks anywhere else — the panel's click-through
    /// region means those clicks never reach us otherwise.
    ///
    /// Installed only while the panel is actually open. A global event monitor
    /// is woken for every mouse-down anywhere on the machine, and this one used
    /// to live for the whole session in order to answer "is the panel open?"
    /// with "no" — for hours at a time, on every click the user makes in every
    /// other app. Now it exists for the seconds the panel does.
    private func setOutsideClickMonitor(active: Bool) {
        guard active != (outsideClickMonitor != nil) else { return }

        guard active else {
            if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
            outsideClickMonitor = nil
            return
        }

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.store.isExpanded else { return }
                withAnimation(IslandMotion.collapse) {
                    self.store.isExpanded = false
                    self.store.focusedActivityID = nil
                }
            }
        }
    }

    /// Keep the monitor's lifetime tied to the panel's open state.
    ///
    /// `withObservationTracking` rather than a notification: `isExpanded` is
    /// already `@Observable` and this needs no new plumbing. The callback
    /// re-registers, which is how a one-shot observation becomes a standing
    /// one.
    private func observePanelState() {
        withObservationTracking {
            _ = store.isExpanded
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.setOutsideClickMonitor(active: self.store.isExpanded)
                self.observePanelState()
            }
        }
    }
}
