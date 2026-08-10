import AppKit
import Foundation
import IsletCore

/// Display brightness HUD.
///
/// macOS has never shipped a public API for *reading* display brightness. The
/// one function that works reliably on Apple silicon lives in a private
/// framework, so it is loaded by name at runtime: if it ever disappears, this
/// module reports itself unavailable and the rest of the app is unaffected.
/// Nothing here can crash the island.
@MainActor
public final class BrightnessProvider: SystemProvider {
    public let identifier = "system.brightness"
    public let displayName = "Display Brightness"
    public var isAvailable: Bool { DisplayServicesBridge.shared.isAvailable }

    private weak var store: ActivityStore?
    private var timer: Timer?
    private var lastValue: Float?
    private var isPrimed = false

    public init() {}

    public func start(store: ActivityStore) {
        self.store = store
        lastValue = currentBrightness()

        // 10 Hz. The read is a single function call into a cached IOKit
        // property, so this is far cheaper than it looks, and anything slower
        // makes the HUD feel laggy against the keyboard's own repeat rate.
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            self?.isPrimed = true
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        store = nil
    }

    private func currentBrightness() -> Float? {
        guard let screen = NSScreen.main,
              let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
              ] as? NSNumber
        else { return nil }
        return DisplayServicesBridge.shared.brightness(for: CGDirectDisplayID(number.uint32Value))
    }

    private func poll() {
        guard let store, let value = currentBrightness() else { return }
        defer { lastValue = value }
        guard isPrimed, let previous = lastValue else { return }
        // Ignore sub-percent drift so ambient auto-brightness doesn't spam the
        // island while you sit still.
        guard abs(value - previous) > 0.008 else { return }

        let percent = Int((value * 100).rounded())
        store.flash(
            id: identifier,
            nativeView: .brightness,
            content: ActivityContent(
                title: "Brightness",
                icon: .symbol(value < 0.34 ? "sun.min.fill" : "sun.max.fill"),
                trailingText: "\(percent)%",
                tint: IsletColor.yellow,
                progress: ActivityProgress(fraction: Double(value))
            ),
            dwell: 1.3
        )
    }
}

/// Runtime binding to `DisplayServices`, isolated so the unsafe part is one
/// small, auditable file rather than scattered `dlsym` calls.
final class DisplayServicesBridge: @unchecked Sendable {
    static let shared = DisplayServicesBridge()

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32

    private let handle: UnsafeMutableRawPointer?
    private let getBrightness: GetBrightness?

    var isAvailable: Bool { getBrightness != nil }

    private init() {
        handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_LAZY
        )
        if let handle, let symbol = dlsym(handle, "DisplayServicesGetBrightness") {
            getBrightness = unsafeBitCast(symbol, to: GetBrightness.self)
        } else {
            getBrightness = nil
        }
    }

    func brightness(for display: CGDirectDisplayID) -> Float? {
        guard let getBrightness else { return nil }
        var value: Float = 0
        guard getBrightness(display, &value) == 0 else { return nil }
        return value
    }
}
