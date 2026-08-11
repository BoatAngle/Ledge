import Foundation
import IOKit.ps
import IsletCore

/// Charging and low-battery events.
///
/// Deliberately event-driven rather than persistent: Apple's island reports the
/// *moment* you plug in and then gets out of the way. A permanent battery
/// readout is what the menu bar is for.
@MainActor
public final class BatteryProvider: SystemProvider {
    public let identifier = "system.battery"
    public let displayName = "Battery & Charging"
    public let summary = "Charging, low battery, and full charge"

    /// Desktops have no internal battery, so there is nothing to report.
    public private(set) lazy var isAvailable: Bool = Self.readSnapshot() != nil

    private weak var store: ActivityStore?
    private var runLoopSource: CFRunLoopSource?
    private var last: Snapshot?

    /// Thresholds we announce once each on the way down.
    private static let lowThresholds: [Int] = [20, 10, 5]
    private var announcedThresholds: Set<Int> = []

    public init() {}

    public func start(store: ActivityStore) {
        self.store = store
        last = Self.readSnapshot()

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ raw in
            guard let raw else { return }
            let provider = Unmanaged<BatteryProvider>.fromOpaque(raw).takeUnretainedValue()
            MainActor.assumeIsolated { provider.refresh() }
        }, context)?.takeRetainedValue() else { return }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source
    }

    public func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        runLoopSource = nil
        store = nil
    }

    // MARK: - Reading

    struct Snapshot: Equatable {
        var percent: Int
        var isCharging: Bool
        var isPluggedIn: Bool
        var minutesRemaining: Int?
    }

    static func readSnapshot() -> Snapshot? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in list {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let state = description[kIOPSPowerSourceStateKey] as? String
            let plugged = state == kIOPSACPowerValue

            let remainingKey = charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            let raw = description[remainingKey] as? Int
            // IOKit reports -1 while it is still working the estimate out.
            let minutes = (raw ?? -1) > 0 ? raw : nil

            return Snapshot(
                percent: max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : 0,
                isCharging: charging,
                isPluggedIn: plugged,
                minutesRemaining: minutes
            )
        }
        return nil
    }

    // MARK: - Reacting

    private func refresh() {
        guard let store, let now = Self.readSnapshot() else { return }
        defer { last = now }

        guard let previous = last else { return }

        if now.isPluggedIn != previous.isPluggedIn {
            announcedThresholds.removeAll()
            announce(now, store: store, reason: now.isPluggedIn ? .pluggedIn : .unplugged)
            return
        }

        // Crossing a threshold on battery power, announced once per discharge.
        if !now.isPluggedIn {
            for threshold in Self.lowThresholds
            where now.percent <= threshold && previous.percent > threshold {
                guard !announcedThresholds.contains(threshold) else { continue }
                announcedThresholds.insert(threshold)
                announce(now, store: store, reason: .low)
                return
            }
        }

        // Charge complete.
        if now.percent >= 100, previous.percent < 100, now.isPluggedIn {
            announce(now, store: store, reason: .full)
        }
    }

    private enum Reason { case pluggedIn, unplugged, low, full }

    private func announce(_ snapshot: Snapshot, store: ActivityStore, reason: Reason) {
        let tint: IsletColor
        let title: String
        let symbol: String

        switch reason {
        case .pluggedIn:
            tint = snapshot.isCharging ? IsletColor.green : IsletColor.yellow
            title = snapshot.isCharging ? "Charging" : "Power connected"
            symbol = "bolt.fill"
        case .unplugged:
            tint = IsletColor.gray
            title = "On battery"
            symbol = "battery.100"
        case .low:
            tint = snapshot.percent <= 10 ? IsletColor.red : IsletColor.orange
            title = "Low battery"
            symbol = "battery.25"
        case .full:
            tint = IsletColor.green
            title = "Fully charged"
            symbol = "battery.100.bolt"
        }

        var subtitle: String?
        if let minutes = snapshot.minutesRemaining {
            let hours = minutes / 60
            let mins = minutes % 60
            let duration = hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
            subtitle = snapshot.isCharging ? "\(duration) until full" : "\(duration) remaining"
        }

        store.flash(
            id: identifier,
            nativeView: .battery,
            content: ActivityContent(
                title: title,
                subtitle: subtitle,
                icon: .symbol(symbol),
                trailingText: "\(snapshot.percent)%",
                tint: tint
            ),
            priority: reason == .low ? .high : .system,
            dwell: reason == .low ? 3.4 : 2.2
        )
    }
}
