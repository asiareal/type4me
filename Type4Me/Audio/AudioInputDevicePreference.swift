import AudioToolbox
@preconcurrency import AVFoundation
import CoreAudio
import Foundation

enum AudioInputDeviceCategory: String, CaseIterable, Codable, Equatable {
    case bluetooth
    case builtIn
    case external
    case virtual
    case other

    var displayName: String {
        switch self {
        case .bluetooth:
            return L("蓝牙设备", "Bluetooth")
        case .builtIn:
            return L("内置麦克风", "Built-in")
        case .external:
            return L("外接/USB", "External/USB")
        case .virtual:
            return L("虚拟设备", "Virtual")
        case .other:
            return L("其他设备", "Other")
        }
    }
}

struct AudioInputDevice: Identifiable, Equatable {
    var id: String { uid }
    let uid: String
    let name: String
    let category: AudioInputDeviceCategory
}

enum AudioInputDevicePreferenceStore {
    static let selectedUIDKey = "tf_selectedMicrophoneUID"
    static let backupUIDKey = "tf_backupMicrophoneUID"

    private static let obsoleteSelectionModeKey = "tf_microphoneSelectionMode"
    private static let obsoletePriorityOrderKey = "tf_microphonePriorityOrder"

    static func migrateIfNeeded() {
        UserDefaults.standard.removeObject(forKey: obsoleteSelectionModeKey)
        UserDefaults.standard.removeObject(forKey: obsoletePriorityOrderKey)
    }

    static func resolvedDeviceUID(devices: [AudioInputDevice] = AudioInputDeviceDiscovery.availableInputDevices()) -> String? {
        resolvedDevice(devices: devices)?.uid
    }

    static func resolvedCachedDeviceUID() -> String? {
        let devices = cachedDevicesOrRefresh()
        return resolvedDevice(devices: devices)?.uid
    }

    static func selectedUID() -> String {
        UserDefaults.standard.string(forKey: selectedUIDKey) ?? ""
    }

    static func backupUID() -> String {
        UserDefaults.standard.string(forKey: backupUIDKey) ?? ""
    }

    static func resolvedDevice(devices: [AudioInputDevice]) -> AudioInputDevice? {
        let primaryUID = selectedUID()
        guard !primaryUID.isEmpty else {
            return nil
        }

        if let primary = devices.first(where: { $0.uid == primaryUID }) {
            return primary
        }

        let fallbackUID = backupUID()
        if !fallbackUID.isEmpty {
            return devices.first { $0.uid == fallbackUID }
        }

        return nil
    }

    private static func cachedDevicesOrRefresh() -> [AudioInputDevice] {
        let cached = AudioInputDeviceMonitor.shared.currentDevices()
        if !cached.isEmpty {
            return cached
        }
        return AudioInputDeviceMonitor.shared.refreshSynchronously()
    }
}

enum AudioInputDeviceDiscovery {
    static func availableInputDevices() -> [AudioInputDevice] {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        return discoverySession.devices.map {
            AudioInputDevice(
                uid: $0.uniqueID,
                name: $0.localizedName,
                category: category(for: $0)
            )
        }
    }

    private static func category(for device: AVCaptureDevice) -> AudioInputDeviceCategory {
        let transport = coreAudioDeviceID(forUID: device.uniqueID).map { transportType(device: $0) }
        return category(forName: device.localizedName, uid: device.uniqueID, transportType: transport)
    }

    static func category(forName deviceName: String, uid: String, transportType: UInt32?) -> AudioInputDeviceCategory {
        let name = deviceName.lowercased()
        if name.contains("airpods") || name.contains("bluetooth") || name.contains("蓝牙") {
            return .bluetooth
        }

        switch transportType {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return .bluetooth
        case kAudioDeviceTransportTypeBuiltIn:
            return .builtIn
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate:
            return .virtual
        case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypePCI, kAudioDeviceTransportTypeFireWire:
            return .external
        case .some:
            return .other
        case .none:
            if uid == "BuiltInMicrophoneDevice" || name.contains("macbook") || name.contains("内置") {
                return .builtIn
            }
            return .external
        }
    }

    private static func coreAudioDeviceID(forUID uid: String) -> AudioDeviceID? {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr else {
            return nil
        }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(0), count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceIDs
        ) == noErr else {
            return nil
        }

        return deviceIDs.first { deviceUID($0) == uid }
    }

    private static func deviceUID(_ deviceID: AudioDeviceID) -> String? {
        var uid = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = withUnsafeMutablePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        return uid as String
    }

    private static func transportType(device: AudioDeviceID) -> UInt32 {
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport)
        guard status == noErr else { return 0 }
        return transport
    }
}

extension Notification.Name {
    static let audioInputDevicesDidChange = Notification.Name("Type4MeAudioInputDevicesDidChange")
}

final class AudioInputDeviceMonitor {
    static let shared = AudioInputDeviceMonitor()

    private let queue = DispatchQueue(label: "com.type4me.audio.input-devices", qos: .utility)
    private let lock = NSLock()
    private var started = false
    private var cachedDevices: [AudioInputDevice] = []

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        refreshSynchronously()
        addListener(selector: kAudioHardwarePropertyDevices)
        addListener(selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    func currentDevices() -> [AudioInputDevice] {
        lock.lock()
        defer { lock.unlock() }
        return cachedDevices
    }

    func replaceCachedDevices(_ devices: [AudioInputDevice]) {
        lock.lock()
        cachedDevices = devices
        lock.unlock()
    }

    private func addListener(selector: AudioObjectPropertySelector) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            queue
        ) { _, _ in
            self.refreshAsynchronously()
        }
    }

    @discardableResult
    func refreshSynchronously() -> [AudioInputDevice] {
        let devices = AudioInputDeviceDiscovery.availableInputDevices()
        replaceCachedDevices(devices)
        return devices
    }

    private func refreshAsynchronously() {
        let devices = AudioInputDeviceDiscovery.availableInputDevices()
        replaceCachedDevices(devices)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .audioInputDevicesDidChange, object: nil)
        }
    }
}
