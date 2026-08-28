import CoreAudio
import Foundation
import LedgeCore

/// Output volume and output-device changes.
///
/// Covers two of the advertised behaviours in one place, because they're the
/// same subsystem: the volume HUD, and "your AirPods just connected".
@MainActor
public final class VolumeProvider: SystemProvider {
    public let identifier = "system.volume"
    public let displayName = "Sound & Output"
    public let summary = "Volume changes and newly connected output devices"
    public var isAvailable: Bool { CoreAudioBridge.defaultOutputDevice() != nil }

    private weak var store: ActivityStore?
    private var deviceID: AudioDeviceID?
    private var listeners: [CoreAudioBridge.ListenerToken] = []
    private var systemListener: CoreAudioBridge.ListenerToken?

    /// Suppresses the HUD for the initial reads that happen at launch.
    private var isPrimed = false
    private var lastVolume: Float = 0
    private var lastMuted = false
    private var lastDeviceName: String?

    public init() {}

    public func start(store: ActivityStore) {
        self.store = store
        attachToCurrentDevice(announce: false)

        systemListener = CoreAudioBridge.addListener(
            object: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDefaultOutputDevice,
            scope: kAudioObjectPropertyScopeGlobal
        ) { [weak self] in
            self?.attachToCurrentDevice(announce: true)
        }

        // Give CoreAudio a beat to settle before we start reacting, so plugging
        // the machine in doesn't fire a volume HUD at login.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            self?.isPrimed = true
        }
    }

    public func stop() {
        listeners.forEach { CoreAudioBridge.removeListener($0) }
        listeners.removeAll()
        if let systemListener { CoreAudioBridge.removeListener(systemListener) }
        systemListener = nil
        store = nil
    }

    // MARK: - Device wiring

    private func attachToCurrentDevice(announce: Bool) {
        listeners.forEach { CoreAudioBridge.removeListener($0) }
        listeners.removeAll()

        guard let device = CoreAudioBridge.defaultOutputDevice() else { return }
        deviceID = device
        lastVolume = CoreAudioBridge.outputVolume(device) ?? lastVolume
        lastMuted = CoreAudioBridge.isMuted(device) ?? false

        let name = CoreAudioBridge.deviceName(device)
        if announce, isPrimed, name != lastDeviceName {
            announceDevice(name: name, device: device)
        }
        lastDeviceName = name

        for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
            if let token = CoreAudioBridge.addListener(
                object: device,
                selector: selector,
                scope: kAudioDevicePropertyScopeOutput,
                handler: { [weak self] in self?.volumeChanged() }
            ) {
                listeners.append(token)
            }
        }
    }

    // MARK: - Events

    private func volumeChanged() {
        guard isPrimed, let store, let device = deviceID else { return }
        let volume = CoreAudioBridge.outputVolume(device) ?? 0
        let muted = CoreAudioBridge.isMuted(device) ?? false
        guard abs(volume - lastVolume) > 0.001 || muted != lastMuted else { return }
        lastVolume = volume
        lastMuted = muted

        let percent = Int((volume * 100).rounded())
        store.flash(
            id: identifier,
            nativeView: .volume,
            module: identifier,
            content: ActivityContent(
                title: muted ? "Muted" : "Volume",
                icon: .symbol(Self.speakerSymbol(volume: volume, muted: muted)),
                trailingText: muted ? "Off" : "\(percent)%",
                tint: LedgeColor.cyan,
                progress: ActivityProgress(fraction: muted ? 0 : Double(volume))
            ),
            // Longer than typical press cadence, so a tap–think–tap rhythm
            // merges into one HUD episode instead of erupting per press.
            dwell: 2.0
        )
    }

    private func announceDevice(name: String?, device: AudioDeviceID) {
        guard let store, let name else { return }
        let isBluetooth = CoreAudioBridge.isBluetooth(device)
        // Only announce devices someone deliberately connected. Docking a
        // laptop reroutes audio to HDMI/USB as a side effect — the user did
        // not "connect headphones", and a HUD for it reads as noise.
        guard isBluetooth else { return }
        store.flash(
            id: "system.audioDevice",
            nativeView: .volume,
            module: identifier,
            content: ActivityContent(
                title: name,
                subtitle: "Connected",
                icon: .symbol(Self.deviceSymbol(name: name, isBluetooth: isBluetooth)),
                tint: LedgeColor.cyan
            ),
            dwell: 2.4
        )
    }

    private static func speakerSymbol(volume: Float, muted: Bool) -> String {
        if muted || volume <= 0.001 { return "speaker.slash.fill" }
        if volume < 0.33 { return "speaker.wave.1.fill" }
        if volume < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private static func deviceSymbol(name: String, isBluetooth: Bool) -> String {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpods.max" }
        if lower.contains("airpods pro") { return "airpodspro" }
        if lower.contains("airpod") { return "airpods" }
        if lower.contains("beats") { return "beats.headphones" }
        if lower.contains("display") || lower.contains("monitor") { return "display" }
        if isBluetooth { return "headphones" }
        return "speaker.wave.2.fill"
    }
}

/// Thin, non-throwing wrappers over the CoreAudio property API.
///
/// CoreAudio's calling convention is verbose enough that inlining it into the
/// provider would bury the actual logic.
enum CoreAudioBridge {
    struct ListenerToken {
        var object: AudioObjectID
        var address: AudioObjectPropertyAddress
        var block: AudioObjectPropertyListenerBlock
    }

    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func defaultOutputDevice() -> AudioDeviceID? {
        device(for: kAudioHardwarePropertyDefaultOutputDevice)
    }

    static func defaultInputDevice() -> AudioDeviceID? {
        device(for: kAudioHardwarePropertyDefaultInputDevice)
    }

    private static func device(for selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var addr = address(selector)
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID
        )
        return status == noErr && deviceID != kAudioObjectUnknown ? deviceID : nil
    }

    static func outputVolume(_ device: AudioDeviceID) -> Float? {
        // Not every device exposes a master volume; fall back to the left
        // channel, which is what the system HUD effectively shows.
        for element in [kAudioObjectPropertyElementMain, 1] {
            var addr = address(
                kAudioDevicePropertyVolumeScalar,
                scope: kAudioDevicePropertyScopeOutput,
                element: AudioObjectPropertyElement(element)
            )
            guard AudioObjectHasProperty(device, &addr) else { continue }
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr {
                return value
            }
        }
        return nil
    }

    static func isMuted(_ device: AudioDeviceID) -> Bool? {
        var addr = address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        guard AudioObjectHasProperty(device, &addr) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value != 0
    }

    static func deviceName(_ device: AudioDeviceID) -> String? {
        var addr = address(kAudioObjectPropertyName)
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(device, &addr, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        return name as String
    }

    static func isBluetooth(_ device: AudioDeviceID) -> Bool {
        var addr = address(kAudioDevicePropertyTransportType)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &transport) == noErr else {
            return false
        }
        return transport == kAudioDeviceTransportTypeBluetooth
    }

    /// True when any process is actively pulling from this device — how we know
    /// the microphone is hot without asking for microphone access ourselves.
    static func isRunningSomewhere(_ device: AudioDeviceID) -> Bool {
        var addr = address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else {
            return false
        }
        return value != 0
    }

    @discardableResult
    static func addListener(
        object: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        handler: @escaping @Sendable @MainActor () -> Void
    ) -> ListenerToken? {
        var addr = address(selector, scope: scope)
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            Task { @MainActor in handler() }
        }
        guard AudioObjectAddPropertyListenerBlock(object, &addr, DispatchQueue.main, block) == noErr
        else { return nil }
        return ListenerToken(object: object, address: addr, block: block)
    }

    static func removeListener(_ token: ListenerToken) {
        var addr = token.address
        AudioObjectRemovePropertyListenerBlock(token.object, &addr, DispatchQueue.main, token.block)
    }
}
