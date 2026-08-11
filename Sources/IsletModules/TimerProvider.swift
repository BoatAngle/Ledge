import AppKit
import Foundation
import IsletCore

/// Countdown timers.
///
/// The island can already animate a countdown from a target date without any
/// further messages, so this provider deliberately posts each timer *once* and
/// then leaves it alone. Its only ongoing job is noticing zero and ringing —
/// which is exactly the part a caller faking a timer with `--countdown` can't
/// do for itself.
@MainActor
public final class TimerProvider: SystemProvider {
    public let identifier = "system.timer"
    public let displayName = "Timers"
    public let summary = "Countdowns that chime and survive a restart"
    public let isAvailable = true

    public struct RunningTimer: Codable, Sendable, Identifiable {
        public var id: String
        public var label: String
        public var fireDate: Date
        public var duration: TimeInterval

        public var remaining: TimeInterval { max(0, fireDate.timeIntervalSinceNow) }
    }

    private weak var store: ActivityStore?
    private var timers: [String: RunningTimer] = [:]
    private var actionObserver: NSObjectProtocol?
    /// Half-second granularity is plenty: the visible countdown is drawn from
    /// the target date, so this only decides when the chime fires.
    private lazy var poller = PollTimer(interval: 0.5) { [weak self] in self?.tick() }

    private static let defaultsKey = "system.timer.running"

    public init() {}

    public func start(store: ActivityStore) {
        self.store = store
        restore()
        poller.start()

        actionObserver = NotificationCenter.default.addObserver(
            forName: .isletActionInvoked,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let id = note.userInfo?["actionID"] as? String else { return }
            MainActor.assumeIsolated { self?.handleAction(id) }
        }
    }

    public func stop() {
        poller.stop()
        if let actionObserver { NotificationCenter.default.removeObserver(actionObserver) }
        actionObserver = nil
        for id in timers.keys { store?.end(id: id) }
        store = nil
    }

    // Timers keep running while the machine is locked — that's the whole point
    // of setting one — so the poller is never suspended.

    // MARK: - Public API

    public var running: [RunningTimer] {
        timers.values.sorted { $0.fireDate < $1.fireDate }
    }

    @discardableResult
    public func startTimer(label: String?, duration: TimeInterval) -> String {
        let id = "timer.\(UUID().uuidString.prefix(8))"
        let timer = RunningTimer(
            id: id,
            label: label?.isEmpty == false ? label! : IsletDuration.describe(duration),
            fireDate: Date().addingTimeInterval(duration),
            duration: duration
        )
        timers[id] = timer
        present(timer)
        persist()
        return id
    }

    @discardableResult
    public func cancel(id: String) -> Bool {
        guard timers.removeValue(forKey: id) != nil else { return false }
        store?.end(id: id)
        persist()
        return true
    }

    @discardableResult
    public func cancelAll() -> Int {
        let count = timers.count
        for id in timers.keys { store?.end(id: id) }
        timers.removeAll()
        persist()
        return count
    }

    // MARK: - Presentation

    private func present(_ timer: RunningTimer) {
        store?.present(
            Activity(
                id: timer.id,
                source: "system",
                kind: .ongoing,
                priority: .normal,
                content: ActivityContent(
                    title: timer.label,
                    subtitle: "Timer",
                    icon: .symbol("timer"),
                    tint: .orange,
                    actions: [
                        ActivityAction(
                            id: "timer.cancel.\(timer.id)",
                            title: "Cancel",
                            symbol: "xmark",
                            isDestructive: true
                        )
                    ],
                    countdownTarget: timer.fireDate
                ),
                nativeView: .timer,
                module: identifier,
                isExpandable: true
            )
        )
    }

    private func tick() {
        guard let store else { return }
        let now = Date()

        for timer in timers.values {
            // Cancelled out from under us — someone ran `islet end <id>`.
            if store.activities[timer.id] == nil, timer.fireDate > now {
                timers.removeValue(forKey: timer.id)
                persist()
                continue
            }
            guard now >= timer.fireDate else { continue }
            fire(timer)
        }
    }

    private func fire(_ timer: RunningTimer) {
        timers.removeValue(forKey: timer.id)
        persist()
        store?.end(id: timer.id)

        NSSound(named: "Glass")?.play()
        store?.flash(
            id: "timer.finished.\(timer.id)",
            nativeView: .timer,
            module: identifier,
            content: ActivityContent(
                title: timer.label,
                subtitle: "Timer finished",
                icon: .symbol("timer.circle.fill"),
                tint: .orange
            ),
            priority: .high,
            dwell: 8
        )
    }

    private func handleAction(_ actionID: String) {
        guard actionID.hasPrefix("timer.cancel.") else { return }
        cancel(id: String(actionID.dropFirst("timer.cancel.".count)))
    }

    // MARK: - Persistence

    /// Timers outlive the app. Quitting with 20 minutes left on a laundry timer
    /// and having it silently vanish would be worse than not offering timers.
    private func persist() {
        let data = try? JSONEncoder().encode(Array(timers.values))
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let saved = try? JSONDecoder().decode([RunningTimer].self, from: data)
        else { return }

        let now = Date()
        for timer in saved where timer.fireDate > now {
            timers[timer.id] = timer
            present(timer)
        }
        // Anything that elapsed while we were gone is dropped rather than
        // ringing late — a chime for a timer that ended an hour ago is noise.
        persist()
    }

}
