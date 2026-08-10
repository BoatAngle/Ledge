import AppKit
import IsletCore
import SwiftUI

/// A hosting view that is transparent to clicks everywhere except the island.
///
/// The panel has to be large enough to hold the fully expanded island, but a
/// 720×500 always-on-top window that swallowed clicks would make the top of the
/// screen unusable. So the view reports "not me" for anything outside the
/// island's current footprint, and the menu bar keeps working.
/// Fills the panel and pins the island to the top edge.
///
/// Without this the hosting view centres the island's intrinsic frame inside a
/// 500pt-tall window, which parks it in the middle of the screen instead of
/// against the bezel.
struct IslandHostView: View {
    var store: ActivityStore
    var metrics: IslandMetrics
    var onFootprintChange: (CGSize) -> Void

    var body: some View {
        VStack(spacing: 0) {
            IslandRootView(
                store: store,
                metrics: metrics,
                onFootprintChange: onFootprintChange
            )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    /// Current island footprint. Updated by the controller as the island grows.
    var footprint: CGSize = .zero

    /// Extra slack around the island so the cursor registers a hover just
    /// before it touches the edge.
    private let slop: CGFloat = 6

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard footprint.width > 0, footprint.height > 0 else { return nil }
        let rect = CGRect(
            x: (bounds.width - footprint.width) / 2 - slop,
            y: bounds.height - footprint.height - slop,
            width: footprint.width + slop * 2,
            height: footprint.height + slop * 2
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
    private var outsideClickMonitor: Any?
    private let store: ActivityStore
    private var metrics: IslandMetrics

    /// Margin around the island inside the panel, giving the shadow and the
    /// metaball blur room to render.
    private let margin: CGFloat = 90

    public init(store: ActivityStore) {
        self.store = store
        self.metrics = NSScreen.islandHost?.isletMetrics
            ?? .synthesized(screenWidth: 1512)
    }

    public func show() {
        guard panel == nil else { return }
        rebuild()
        observeScreenChanges()
        observeOutsideClicks()
    }

    public func hide() {
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
            hostingView.rootView = makeRootView()
            hostingView.frame = CGRect(origin: .zero, size: panelSize)
        } else {
            let view = PassthroughHostingView(rootView: makeRootView())
            view.frame = CGRect(origin: .zero, size: panelSize)
            view.autoresizingMask = [.width, .height]
            panel.contentView = view
            hostingView = view
        }

        self.panel = panel
        panel.orderFrontRegardless()
    }

    private func makeRootView() -> IslandHostView {
        IslandHostView(store: store, metrics: metrics) { [weak self] footprint in
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
