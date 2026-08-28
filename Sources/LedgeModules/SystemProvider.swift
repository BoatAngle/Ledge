import Foundation
import LedgeCore

/// Where a module stands with the system permission it depends on.
public enum ModulePermissionState: Equatable, Hashable, Sendable {
    /// No system permission involved.
    case notNeeded
    /// The permission exists and hasn't been granted; a user gesture should
    /// trigger the request. This is the one-and-done rule: a module may raise
    /// its consent dialog on its own exactly once, ever — after that the
    /// prompt appears only when the user explicitly asks, from Settings.
    case needsRequest
    case granted
    /// Actively declined. The only road back is System Settings.
    case denied
}

/// A source of system state that posts activities into the island.
///
/// Every provider degrades quietly. If the API it needs isn't available — a
/// private framework moved, the user declined a permission, the hardware has no
/// battery — it reports `isAvailable == false` and the island simply never
/// shows that module. Nothing should ever be a hard failure.
@MainActor
public protocol SystemProvider: AnyObject {
    /// Stable identifier, also used as the activity id so updates coalesce.
    var identifier: String { get }
    /// Human-readable name for settings.
    var displayName: String { get }
    /// False when this machine or this user can't support the module.
    var isAvailable: Bool { get }
    /// One line explaining what it does, shown in Settings.
    var summary: String { get }

    /// Where this module stands with its system permission, if it has one.
    @MainActor var permissionState: ModulePermissionState { get }
    /// Raise the consent dialog now, on the user's explicit gesture.
    /// Returns whether access ended up granted.
    @MainActor func requestPermission() async -> Bool

    func start(store: ActivityStore)
    func stop()

    /// Pause work because the machine is locked or the display is asleep.
    /// Event-driven providers can ignore this; pollers should stand down.
    func suspend()
    func resume()
}

public extension SystemProvider {
    @MainActor var permissionState: ModulePermissionState { .notNeeded }
    @MainActor func requestPermission() async -> Bool { true }
    func suspend() {}
    func resume() {}
    var summary: String { "" }
}

/// Starts and stops the built-in providers as a group.
@MainActor
public final class ProviderRegistry {
    public private(set) var providers: [any SystemProvider] = []
    private weak var store: ActivityStore?

    public init() {}

    /// Every module that ships with the app, in the order they should be
    /// offered in settings.
    public static func standard() -> [any SystemProvider] {
        [
            MediaProvider(),
            TimerProvider(),
            CalendarProvider(),
            DownloadsProvider(),
            WeatherProvider(),
            BatteryProvider(),
            VolumeProvider(),
            BrightnessProvider(),
            FocusProvider(),
            CapsLockProvider(),
            PrivacyProvider(),
        ]
    }

    public func start(_ providers: [any SystemProvider], store: ActivityStore) {
        self.store = store
        for provider in providers where provider.isAvailable {
            provider.start(store: store)
            self.providers.append(provider)
        }
    }

    public func stop() {
        for provider in providers {
            provider.stop()
            store?.end(id: provider.identifier)
        }
        providers.removeAll()
    }

    /// Stand every provider down. Activities already on the island stay put —
    /// a running timer must survive the lock.
    public func suspendAll() {
        providers.forEach { $0.suspend() }
    }

    public func resumeAll() {
        providers.forEach { $0.resume() }
    }

    /// Names of modules that couldn't run here, for the settings UI to explain.
    public func unavailable(from all: [any SystemProvider]) -> [String] {
        all.filter { !$0.isAvailable }.map(\.displayName)
    }
}
