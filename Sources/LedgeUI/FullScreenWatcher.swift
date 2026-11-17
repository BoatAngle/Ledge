import AppKit

/// Whether a full-screen app currently owns the island's display.
///
/// The island draws above everything, including full-screen windows, which is
/// what makes it feel like hardware — and what makes it intolerable over a
/// film. A notch app that keeps announcing downloads across the top of a movie
/// is not ambient, it's an interruption with no dismiss button.
///
/// Detecting this honestly turned out to be the whole problem.
@MainActor
@Observable
public final class FullScreenWatcher {
    public static let shared = FullScreenWatcher()

    /// True while a full-screen app owns the screen the island lives on.
    public private(set) var isActive = false

    /// Called whenever `isActive` flips, for the AppKit side that can't observe.
    public var onChange: ((Bool) -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var poll: Timer?

    private init() {}

    // MARK: Lifecycle

    public func start() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter

        // Entering or leaving native full screen moves the user to a different
        // Space, so this fires for the case that matters, immediately.
        for name: NSNotification.Name in [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
        ] {
            observers.append(
                workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.evaluate() }
                }
            )
        }
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            }
        )
        evaluate()
    }

    public func stop() {
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in observers {
            workspace.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        setPolling(false)
    }

    /// Backstop for apps that fake full screen with a borderless window instead
    /// of taking a Space — those change nothing the notifications above can
    /// hear. Runs ONLY while the island has something it would otherwise be
    /// showing, so an idle Mac pays nothing for it.
    public func setPolling(_ wanted: Bool) {
        guard wanted != (poll != nil) else { return }
        guard wanted else {
            poll?.invalidate()
            poll = nil
            return
        }
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
    }

    // MARK: Detection

    public func evaluate() {
        let value = NSScreen.islandHost.map(Self.isFullScreen) ?? false
        guard value != isActive else { return }
        isActive = value
        onChange?(value)
    }

    /// A screen's frame in CoreGraphics coordinates, which are flipped and
    /// anchored to the top-left of the primary display.
    private static func cgFrame(of screen: NSScreen) -> CGRect {
        guard let primary = NSScreen.screens.first else { return screen.frame }
        return CGRect(
            x: screen.frame.minX,
            y: primary.frame.maxY - screen.frame.maxY,
            width: screen.frame.width,
            height: screen.frame.height
        )
    }

    /// Whether a full-screen app owns `screen` right now.
    ///
    /// Two signals, and it needs both — each alone is wrong:
    ///
    /// 1. **An ordinary (layer 0) window spanning the screen.** Necessary, not
    ///    sufficient: a window merely zoomed with the green button has exactly
    ///    the same bounds. On a notched Mac a full-screen window does NOT cover
    ///    the camera housing by default — measured at top=39 on this machine,
    ///    the same as a maximized window — so bounds can never tell them apart.
    ///
    /// 2. **No desktop backing on that screen.** A full-screen app gets its own
    ///    Space, and in that Space the Finder wallpaper window and the Dock's
    ///    screen-sized window are simply *gone* from the window list. On a
    ///    normal desktop, zoomed or not, both are present. That absence is the
    ///    thing that actually means "full screen".
    ///
    /// Requiring the covering window too means a Finder that has crashed or
    /// been relaunched can't blank the island on its own.
    ///
    /// What this deliberately does NOT use is `visibleFrame`: the obvious test,
    /// "the menu bar has given up its strip", is simply false inside a
    /// full-screen Space — measured, not assumed. The previous guard here was
    /// written that way and therefore never once fired.
    ///
    /// Needs no permissions. `CGWindowListCopyWindowInfo` redacts window
    /// *titles* without Screen Recording access; bounds, layer and owner come
    /// back regardless, and titles are not consulted.
    public static func isFullScreen(_ screen: NSScreen) -> Bool {
        let frame = cgFrame(of: screen)
        guard
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]]
        else { return false }

        var bundles: [pid_t: String] = [:]
        var hasCoveringWindow = false
        var hasDesktopBacking = false

        for window in windows {
            guard
                let raw = window[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: raw)
            else { continue }
            // Spans this screen: full width, flush to its bottom edge.
            guard bounds.width >= frame.width - 2,
                  bounds.minX <= frame.minX + 2,
                  bounds.maxY >= frame.maxY - 2
            else { continue }

            if (window[kCGWindowLayer as String] as? Int) == 0 { hasCoveringWindow = true }

            let pid = window[kCGWindowOwnerPID as String] as? pid_t ?? 0
            let bundle = bundles[pid] ?? {
                let identifier = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
                bundles[pid] = identifier
                return identifier
            }()
            if bundle == "com.apple.finder" || bundle == "com.apple.dock" {
                hasDesktopBacking = true
            }
        }

        return hasCoveringWindow && !hasDesktopBacking
    }
}
