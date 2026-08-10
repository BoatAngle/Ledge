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
    public private(set) var isLocked = false

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
                MainActor.assumeIsolated { self?.set(true) }
            }
        )
        observers.append(
            distributed.addObserver(
                forName: Notification.Name("com.apple.screenIsUnlocked"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.set(false) }
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
                MainActor.assumeIsolated { self?.set(true) }
            }
        )
        observers.append(
            workspace.addObserver(
                forName: NSWorkspace.screensDidWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.set(false) }
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

    private func set(_ locked: Bool) {
        guard locked != isLocked else { return }
        isLocked = locked
        onChange(locked)
    }
}
