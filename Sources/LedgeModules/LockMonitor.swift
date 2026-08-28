import AppKit
import Foundation

/// Tracks whether the machine is locked or its display is asleep.
///
/// This replaces the "lockscreen presence" feature other notch apps advertise.
/// That one isn't buildable: the macOS login window runs in a separate session
/// and third-party processes cannot draw into it. What *is* real — and worth
/// more — is noticing the lock and shutting every poll down until the user is
/// back.
@MainActor
public final class LockMonitor {
    /// The two reasons to stand down are tracked SEPARATELY, and either one is
    /// enough.
    ///
    /// A single Bool looks like it works and doesn't: lock the Mac, let the
    /// display sleep, then nudge the mouse. The display wakes to the lock
    /// screen and posts `screensDidWake`, which cleared the one flag and
    /// resumed every poller — brightness at 10 Hz, downloads scanning the
    /// folder — for a machine the user isn't even signed into. Two flags, one
    /// derived answer.
    private var screenLocked = false
    private var screensAsleep = false

    /// True while either condition holds.
    public var isLocked: Bool { screenLocked || screensAsleep }

    /// What the last callback reported, so a change that doesn't move the
    /// derived value stays silent.
    private var lastReported = false

    private var observers: [NSObjectProtocol] = []
    private let onChange: @MainActor (Bool) -> Void

    public init(onChange: @escaping @MainActor (Bool) -> Void) {
        self.onChange = onChange
    }

    public func start() {
        // Screen lock arrives on the *distributed* notification center, not the
        // workspace one — a detail that costs an hour if you miss it.
        let distributed = DistributedNotificationCenter.default()
        observers.append(
            distributed.addObserver(
                forName: Notification.Name("com.apple.screenIsLocked"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.setLocked(true) }
            }
        )
        observers.append(
            distributed.addObserver(
                forName: Notification.Name("com.apple.screenIsUnlocked"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.setLocked(false) }
            }
        )

        // Display sleep counts too: nothing is visible, so nothing needs polling.
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(
            workspace.addObserver(
                forName: NSWorkspace.screensDidSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.setScreensAsleep(true) }
            }
        )
        observers.append(
            workspace.addObserver(
                forName: NSWorkspace.screensDidWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.setScreensAsleep(false) }
            }
        )
    }

    public func stop() {
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in observers {
            distributed.removeObserver(observer)
            workspace.removeObserver(observer)
        }
        observers.removeAll()
    }

    private func setLocked(_ locked: Bool) {
        screenLocked = locked
        publish()
    }

    private func setScreensAsleep(_ asleep: Bool) {
        screensAsleep = asleep
        publish()
    }

    private func publish() {
        let suspended = isLocked
        guard suspended != lastReported else { return }
        lastReported = suspended
        onChange(suspended)
    }
}
