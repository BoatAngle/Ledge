import AppKit
import SwiftUI

/// The system's accessibility display preferences, observed live.
///
/// Everything the island does is motion and translucency, which is exactly the
/// set of things these preferences exist to turn down. A single observer keeps
/// the whole app honest: views read the observable, and `IslandMotion` reads
/// the mirrored flag (see below) because animations are also consumed from
/// AppKit callbacks and `ButtonStyle.makeBody`, neither of which has a SwiftUI
/// environment to read from.
@MainActor
@Observable
public final class IslandAccessibility {
    public static let shared = IslandAccessibility()

    /// Replace movement with a cross-fade. Not "remove all animation" — an
    /// instant cut is its own kind of jarring, and Apple's own reduced-motion
    /// transitions still fade.
    public private(set) var reduceMotion = false
    /// Blur and translucency become opaque fills.
    public private(set) var reduceTransparency = false
    /// Borders and separators get the contrast they need to survive.
    public private(set) var increaseContrast = false
    /// Colour alone must not carry meaning — state gets a shape or a symbol.
    public private(set) var differentiateWithoutColor = false

    /// Nonisolated mirror of `increaseContrast`, for `IslandDesign.Ink`.
    ///
    /// The ink ramp is a nonisolated `enum` of static colours consumed from
    /// `ButtonStyle.makeBody` and other places with no actor and no SwiftUI
    /// environment, so it cannot reach the observable. Written only from the
    /// main actor, in `refresh()`.
    ///
    /// Because a plain static can't drive SwiftUI observation, `IslandRootView`
    /// also reads the *observable* property in its `body`; that is what makes
    /// the change appear without a relaunch.
    nonisolated(unsafe) public internal(set) static var prefersIncreasedContrast = false

    private var observer: NSObjectProtocol?

    private init() {
        refresh()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func refresh() {
        let workspace = NSWorkspace.shared
        reduceMotion = workspace.accessibilityDisplayShouldReduceMotion
        reduceTransparency = workspace.accessibilityDisplayShouldReduceTransparency
        increaseContrast = workspace.accessibilityDisplayShouldIncreaseContrast
        differentiateWithoutColor = workspace.accessibilityDisplayShouldDifferentiateWithoutColor
        // Mirror out to the places that can't reach an observable.
        IslandMotion.prefersReducedMotion = reduceMotion
        Self.prefersIncreasedContrast = increaseContrast
    }

    /// Whether VoiceOver is running right now.
    ///
    /// Read on demand rather than observed: it is only ever consulted at the
    /// moment of an announcement, and there is no reason to hold a subscription
    /// for a value that is free to fetch.
    public var isVoiceOverRunning: Bool { NSWorkspace.shared.isVoiceOverEnabled }

    /// Speak something that happened on the island.
    ///
    /// The island is a `nonactivating` panel that never becomes key, so a
    /// VoiceOver user cannot simply focus it and read it — without this, a
    /// timer finishing or a meeting starting is silent. Announcements are the
    /// documented route for exactly this case: state that changes without the
    /// user's focus being anywhere near it.
    ///
    /// Silent unless VoiceOver is actually running, so it costs nothing for
    /// everyone else.
    public func announce(_ message: String, priority: NSAccessibilityPriorityLevel = .medium) {
        guard isVoiceOverRunning, !message.isEmpty else { return }
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: priority.rawValue,
            ]
        )
    }
}

// No environment key: the type is `@Observable`, so a view that reads
// `IslandAccessibility.shared.reduceTransparency` in its `body` registers the
// dependency and re-renders when the setting changes — an environment value
// would add a plumbing layer that buys nothing.
