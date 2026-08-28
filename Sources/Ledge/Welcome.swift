import AppKit
import LedgeCore

/// The app's first impression, delivered on the island itself.
///
/// Ledge has no Dock icon, no window, and nothing to show until something
/// happens. On a quiet Mac, a first launch is indistinguishable from a failed
/// one — you double-click the app and the screen does not change. The only
/// evidence is a small capsule in the menu bar, which is exactly where a new
/// user is not looking.
///
/// So the island introduces itself, in the medium it is asking to be trusted
/// with: it appears, it opens once on its own, it says what it is and what it
/// will and won't do, and it offers the two things a new user actually needs —
/// a way to turn on the modules that need permission, and a way to make it go
/// away. It happens exactly once, ever.
@MainActor
struct Welcome {
    static let activityID = "ledge.welcome"
    static let setUpAction = "ledge.welcome.setUp"
    static let dismissAction = "ledge.welcome.dismiss"

    /// How long the panel waits before opening itself.
    ///
    /// Long enough for the window server to have the panel on screen and for
    /// the user's eye to have followed the launch, short enough that it still
    /// reads as a consequence of double-clicking the app.
    static let openDelay: Duration = .milliseconds(900)

    /// The welcome retires on its own if nobody touches it. It is an
    /// introduction, not a modal.
    static let lifetime: TimeInterval = 45

    static func activity() -> Activity {
        Activity(
            id: activityID,
            source: "system",
            kind: .ongoing,
            priority: .high,
            content: ActivityContent(
                title: "Ledge is running",
                subtitle: "This strip under the camera is yours now",
                body: """
                Things that happen on your Mac show up here — what's playing, \
                a timer, a download, your next meeting. Drag files onto the \
                notch to park them.
                """,
                icon: .symbol("sparkles"),
                tint: .accent,
                details: [
                    ActivityDetail(label: "Menu bar", value: "The capsule, for settings"),
                    ActivityDetail(label: "Permissions", value: "Asked only when you turn a module on"),
                ],
                actions: [
                    ActivityAction(id: setUpAction, title: "Choose Modules", symbol: "square.grid.2x2"),
                    ActivityAction(id: dismissAction, title: "Got It", symbol: "checkmark"),
                ]
            ),
            // No module: this is not a provider's activity, and marking it one
            // would exempt it from the ordinary clears that should reach it.
            expiresAt: Date().addingTimeInterval(lifetime),
            isExpandable: true
        )
    }
}
