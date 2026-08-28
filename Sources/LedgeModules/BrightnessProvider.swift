import AppKit
import Foundation
import LedgeCore

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
    public let summary = "Display brightness changes"
    public var isAvailable: Bool { DisplayServicesBridge.shared.isAvailable }

    private weak var store: ActivityStore?
    private lazy var poller = PollTimer(interval: 0.1) { [weak self] in self?.poll() }
    private var lastValue: Float?
    private var isPrimed = false

    public init() {}

    public func start(store: ActivityStore) {
        self.store = store
        lastValue = currentBrightness()

        // 10 Hz. The read is a single function call into a cached IOKit
        // property, so this is far cheaper than it looks, and anything slower
        // makes the HUD feel laggy against the keyboard's own repeat rate.
        poller.start()

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            self?.isPrimed = true
        }
    }

    public func stop() {
        poller.stop()
        store = nil
    }

    public func suspend() { poller.suspend() }

    public func resume() {
        // Re-baseline: brightness may well have changed while we weren't
        // looking, and we don't want to flash a HUD for that.
        lastValue = currentBrightness()
        poller.resume()
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
        // Keyboard steps are 1/16 (0.0625) or 1/64 (0.0156); ambient
        // auto-brightness ramps move far finer per poll. 0.012 catches every
        // key press including the fine Opt+Shift step and ignores the room
        // getting brighter — the system's own HUD never shows for ambient
        // changes, and neither should the island.
        guard abs(value - previous) > 0.012 else { return }

        let percent = Int((value * 100).rounded())
        store.flash(
            id: identifier,
            nativeView: .brightness,
            module: identifier,
            content: ActivityContent(
                title: "Brightness",
                icon: .symbol(value < 0.34 ? "sun.min.fill" : "sun.max.fill"),
                trailingText: "\(percent)%",
                tint: LedgeColor.yellow,
                progress: ActivityProgress(fraction: Double(value))
            ),
            dwell: 2.0
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
