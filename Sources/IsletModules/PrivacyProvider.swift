import CoreAudio
import CoreMediaIO
import Foundation
import IsletCore

/// Camera and microphone in-use indicators.
///
/// Reads whether *any* process has the device running. Notably this asks for no
/// permissions of its own — we never open the camera or the mic, we only ask
/// the hardware whether someone else has.
@MainActor
public final class PrivacyProvider: SystemProvider {
    public let identifier = "system.privacy"
    public let displayName = "Camera & Microphone"
    public let isAvailable = true

    private weak var store: ActivityStore?
    private var timer: Timer?
    private var lastState = State(camera: false, microphone: false)

    struct State: Equatable {
        var camera: Bool
        var microphone: Bool
        var isActive: Bool { camera || microphone }
    }

    public init() {}

    public func start(store: ActivityStore) {
        self.store = store
        lastState = currentState()
        if lastState.isActive { publish(lastState, announce: false) }

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        store?.end(id: identifier)
        store = nil
    }

    private func poll() {
        let state = currentState()
        guard state != lastState else { return }
        let wasActive = lastState.isActive
        lastState = state

        guard state.isActive else {
            store?.end(id: identifier)
            return
        }
        publish(state, announce: !wasActive)
    }

    private func publish(_ state: State, announce: Bool) {
        guard let store else { return }

        let title: String
        let symbol: String
        let tint: IsletColor
        switch (state.camera, state.microphone) {
        case (true, true):
            title = "Camera & Mic in use"
            symbol = "video.fill"
            tint = IsletColor.orange
        case (true, false):
            title = "Camera in use"
            symbol = "video.fill"
            tint = IsletColor.green
        default:
            title = "Microphone in use"
            symbol = "mic.fill"
            tint = IsletColor.orange
        }

        if announce {
            // The moment access starts is the part worth interrupting for.
            store.flash(
                id: "system.privacyStart",
                nativeView: .privacy,
                content: ActivityContent(title: title, icon: .symbol(symbol), tint: tint),
                priority: .high,
                dwell: 2.0
            )
        }

        // Then a quiet, persistent marker that yields the compact slot to
        // whatever else is going on.
        store.present(
            Activity(
                id: identifier,
                source: "system",
                kind: .ongoing,
                priority: .low,
                content: ActivityContent(
                    title: title,
                    subtitle: "Something is using it right now",
                    icon: .symbol(symbol),
                    tint: tint
                ),
                nativeView: .privacy,
                isExpandable: true
            )
        )
    }

    // MARK: - Hardware queries

    private func currentState() -> State {
        State(camera: Self.isAnyCameraRunning(), microphone: Self.isAnyMicrophoneRunning())
    }

    static func isAnyMicrophoneRunning() -> Bool {
        for device in audioInputDevices() where CoreAudioBridge.isRunningSomewhere(device) {
            return true
        }
        return false
    }

    /// Every audio device that actually has input streams.
    private static func audioInputDevices() -> [AudioDeviceID] {
        var addr = CoreAudioBridge.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &devices
        ) == noErr else { return [] }

        return devices.filter { device in
            var streams = CoreAudioBridge.address(
                kAudioDevicePropertyStreams,
                scope: kAudioDevicePropertyScopeInput
            )
            var streamSize: UInt32 = 0
            let status = AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamSize)
            return status == noErr && streamSize > 0
        }
    }

    static func isAnyCameraRunning() -> Bool {
        var addr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &size
        ) == noErr, size > 0 else { return false }

        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, size, &used, &devices
        ) == noErr else { return false }

        var running = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        for device in devices where device != 0 {
            var value: UInt32 = 0
            let valueSize = UInt32(MemoryLayout<UInt32>.size)
            var valueUsed: UInt32 = 0
            let status = CMIOObjectGetPropertyData(
                device, &running, 0, nil, valueSize, &valueUsed, &value
            )
            if status == noErr, value != 0 { return true }
        }
        return false
    }
}
