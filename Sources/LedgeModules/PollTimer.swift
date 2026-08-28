import Foundation

/// A repeating main-thread timer that can be suspended and resumed.
///
/// Several modules poll, because macOS offers no notification for what they
/// need. Polling a locked machine is pure waste, so every one of them routes
/// through this and the registry can silence the lot in one call.
@MainActor
final class PollTimer {
    private var timer: Timer?
    private let interval: TimeInterval
    private let tick: @MainActor () -> Void
    private var isRunning = false

    init(interval: TimeInterval, tick: @escaping @MainActor () -> Void) {
        self.interval = interval
        self.tick = tick
    }

    func start() {
        guard timer == nil else { return }
        isRunning = true
        schedule()
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    /// Pause without forgetting that we were running.
    func suspend() {
        timer?.invalidate()
        timer = nil
    }

    func resume() {
        guard isRunning, timer == nil else { return }
        schedule()
    }

    private func schedule() {
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Let the system coalesce our wakeups with everyone else's.
        //
        // Nine pollers each demanding to be woken on their own exact schedule
        // is nine separate trips out of idle; a tolerance lets the kernel line
        // them up and take one. Apple's own guidance is 10% of the interval,
        // and none of these readings is time-critical to the millisecond — the
        // weather can be ninety seconds late, and nobody can see a brightness
        // HUD arrive 10ms early.
        timer.tolerance = interval * 0.1
        // `.common` so the island keeps updating while a menu is open or a
        // window is being resized.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    isolated deinit {
        timer?.invalidate()
    }
}
