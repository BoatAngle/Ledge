import CoreAudio
import CoreMediaIO
import Foundation
import LedgeCore

/// Camera and microphone in-use indicators.
///
/// Reads whether *any* process has the device running. Notably this asks for no
/// permissions of its own — we never open the camera or the mic, we only ask
/// the hardware whether someone else has.
@MainActor
public final class PrivacyProvider: SystemProvider {
    public let identifier = "system.privacy"
    public let displayName = "Camera & Microphone"
    public let summary = "When something starts using the camera or microphone"
    public let isAvailable = true

    private weak var store: ActivityStore?
    private lazy var poller = PollTimer(interval: 0.5) { [weak self] in self?.poll() }
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

        poller.start()
    }

    public func stop() {
        poller.stop()
        store?.end(id: identifier)
        store = nil
    }

    public func suspend() { poller.suspend() }
    public func resume() { poller.resume() }

    private func poll() {
        let state = currentState()

        // Self-healing, deliberately.
        //
        // The short-circuit below is a real optimisation — the hardware state
        // changes a handful of times a day and this runs twice a second — but
        // on its own it made the indicator *removable*: anything that took the
        // activity off the island left it off until the camera physically
        // turned on or off again, which on a video call means the rest of the
        // call. This is the one mark on the island that has to be true, so an
        // active state re-publishes itself whenever it finds its activity gone.
        if state == lastState {
            guard state.isActive, store?.activities[identifier] == nil else { return }
            publish(state, announce: false)
            return
        }

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
        let tint: LedgeColor
        // A second symbol, present only when BOTH devices are live.
        //
        // Colour was carrying this distinction alone, and failing at it: camera
        // + microphone and microphone-only were both an orange dot, pixel for
        // pixel. The compact mark now grows a second dot when both are in use,
        // which is a difference in shape rather than in hue — visible to
        // someone who can't separate green from orange, and visible at 5pt.
        //
        // The colours follow macOS's own convention rather than the previous
        // mapping: green means the camera is on, orange means the microphone
        // is. Camera-and-microphone therefore leads green, the same as Control
        // Centre, instead of reading as a microphone.
        let secondarySymbol: String?
        switch (state.camera, state.microphone) {
        case (true, true):
            title = "Camera & Microphone in use"
            symbol = "video.fill"
            secondarySymbol = "mic.fill"
            tint = LedgeColor.green
        case (true, false):
            title = "Camera in use"
            symbol = "video.fill"
            secondarySymbol = nil
            tint = LedgeColor.green
        default:
            title = "Microphone in use"
            symbol = "mic.fill"
            secondarySymbol = nil
            tint = LedgeColor.orange
        }

        if announce {
            // The moment access starts is the part worth interrupting for.
            store.flash(
                id: "system.privacyStart",
                nativeView: .privacy,
                module: identifier,
                content: ActivityContent(
                    title: title,
                    icon: .symbol(symbol),
                    trailingIcon: secondarySymbol.map(ActivityIcon.symbol),
                    tint: tint
                ),
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
                    subtitle: state.camera && state.microphone
                        ? "Something is using them right now"
                        : "Something is using it right now",
                    icon: .symbol(symbol),
                    trailingIcon: secondarySymbol.map(ActivityIcon.symbol),
                    tint: tint
                ),
                nativeView: .privacy,
                module: identifier,
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
