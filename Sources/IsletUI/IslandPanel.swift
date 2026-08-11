import AppKit
import IsletCore
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
    var settings: IsletSettings
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

    /// Extra slack around the island so the cursor registers a hover just
    /// before it touches the edge — and, when idle, so the notch is a large
    /// enough target to drag a file onto.
    private let slop: CGFloat = 16

    // MARK: Drag destination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard !urls(from: sender).isEmpty else { return [] }
        shelf?.dragEntered()
        // `.copy` because the shelf only ever references files — it never
        // moves or deletes what you drop on it.
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard !urls(from: sender).isEmpty else { return [] }
        shelf?.dragUpdated()
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        shelf?.dragExited()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        !urls(from: sender).isEmpty
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = urls(from: sender)
        guard !urls.isEmpty else { return false }
        shelf?.accept(urls)
        return true
    }

    private func urls(from sender: any NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let active = footprint.width > 0 && footprint.height > 0 ? footprint : fallbackFootprint
        guard active.width > 0, active.height > 0 else { return nil }
        let rect = CGRect(
            x: (bounds.width - active.width) / 2 - slop,
            y: bounds.height - active.height - slop,
            width: active.width + slop * 2,
            height: active.height + slop * 2
        )
        guard rect.contains(point) else { return nil }
        return super.hitTest(point)
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
    private let store: ActivityStore
    private let settings: IsletSettings
    private var metrics: IslandMetrics

    /// Margin around the island inside the panel, giving the shadow and the
    /// metaball blur room to render.
    private let margin: CGFloat = 90

    public init(store: ActivityStore, settings: IsletSettings = .shared) {
        self.store = store
        self.settings = settings
        self.metrics = NSScreen.islandHost?.isletMetrics
            ?? .synthesized(screenWidth: 1512)
    }

    public func show() {
        guard panel == nil else { return }
        shelf.attach(to: store)
        rebuild()
        observeScreenChanges()
        observeOutsideClicks()
    }

    public func hide() {
        shelf.detach()
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        NotificationCenter.default.removeObserver(self)
    }

    /// True on displays with real hardware to hug.
    public var isOnNotchedDisplay: Bool { metrics.hasPhysicalNotch }

    // MARK: - Construction

    private func rebuild() {
        guard let screen = NSScreen.islandHost else { return }
        metrics = screen.isletMetrics

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
        NotificationCenter.default.addObserver(
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
        }
    }

    /// Collapse when the user clicks anywhere else — the panel's click-through
    /// region means those clicks never reach us otherwise.
    private func observeOutsideClicks() {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.store.isExpanded else { return }
                withAnimation(IslandMotion.expand) {
                    self.store.isExpanded = false
                    self.store.focusedActivityID = nil
                }
            }
        }
    }
}
