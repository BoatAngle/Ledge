import AppKit
import Foundation
import IsletCore

/// Caps Lock state confirmation.
///
/// Polls `NSEvent.modifierFlags` rather than installing a global key monitor.
/// That distinction matters: a global monitor for key events would require
/// Accessibility access, and asking a user to hand over "control your computer"
/// so we can draw a little arrow would be an absurd trade. The static property
/// reads current hardware state and needs no permission at all.
@MainActor
public final class CapsLockProvider: SystemProvider {
    public let identifier = "system.capsLock"
    public let displayName = "Caps Lock"
    public let summary = "A brief confirmation when Caps Lock toggles"
    public let isAvailable = true

    private weak var store: ActivityStore?
    private lazy var poller = PollTimer(interval: 1.0 / 15.0) { [weak self] in self?.poll() }
    private var lastState: Bool?

    public init() {}

    public func start(store: ActivityStore) {
        self.store = store
        lastState = NSEvent.modifierFlags.contains(.capsLock)

        poller.start()
    }

    public func stop() {
        poller.stop()
        store = nil
    }

    public func suspend() { poller.suspend() }

    public func resume() {
        lastState = NSEvent.modifierFlags.contains(.capsLock)
        poller.resume()
    }

    private func poll() {
        guard let store else { return }
        let isOn = NSEvent.modifierFlags.contains(.capsLock)
        guard isOn != lastState else { return }
        lastState = isOn

        store.flash(
            id: identifier,
            nativeView: .capsLock,
            content: ActivityContent(
                title: isOn ? "Caps Lock On" : "Caps Lock Off",
                icon: .symbol(isOn ? "capslock.fill" : "capslock"),
                trailingText: isOn ? "ON" : "OFF",
                tint: isOn ? IsletColor.green : IsletColor.gray
            ),
            dwell: 1.1
        )
    }
}
