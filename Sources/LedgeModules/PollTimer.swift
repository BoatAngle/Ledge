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
        // `.common` so the island keeps updating while a menu is open or a
        // window is being resized.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    isolated deinit {
        timer?.invalidate()
    }
}
