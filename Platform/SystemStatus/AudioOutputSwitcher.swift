import AudioToolbox
import SwiftUI

// Phase 36e — list the Mac's audio outputs and make one the default. CoreAudio calls run only when the
// menu is shown or an item is picked; there is no listener, so a closed menu costs nothing.

struct AudioOutputDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let name: String
    let isDefault: Bool
}

enum AudioOutputSwitcher {
    private static let cacheLock = NSLock()
    private static var deviceCache: [Bool: (timestamp: TimeInterval, devices: [AudioOutputDevice])] = [:]
    private static let cacheTTL: TimeInterval = 3.0

    static func invalidateCache() {
        cacheLock.withLock { deviceCache.removeAll() }
    }

    static func cachedDefaultOutputName() -> String? {
        devices(input: false).first(where: \.isDefault)?.name
    }

    static func devices(input: Bool = false) -> [AudioOutputDevice] {
        let now = ProcessInfo.processInfo.systemUptime
        if let hit = cacheLock.withLock({ () -> [AudioOutputDevice]? in
            guard let entry = deviceCache[input], now - entry.timestamp < cacheTTL else { return nil }
            return entry.devices
        }) {
            return hit
        }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        let current = defaultDevice(input: input)
        let resolved: [AudioOutputDevice] = ids.compactMap { id in
            guard hasStreams(id, input: input), let name = name(of: id) else { return nil }
            return AudioOutputDevice(id: id, name: name, isDefault: id == current)
        }
        cacheLock.withLock {
            deviceCache[input] = (timestamp: ProcessInfo.processInfo.systemUptime, devices: resolved)
        }
        return resolved
    }

    @discardableResult
    static func setDefault(_ id: AudioObjectID, input: Bool = false) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = id
        let ok = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &device) == noErr
        if ok { invalidateCache() }
        return ok
    }

    private static func defaultDevice(input: Bool) -> AudioObjectID {
        var address = AudioObjectPropertyAddress(mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }

    private static func hasStreams(_ id: AudioObjectID, input: Bool) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func name(of id: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }
}

// MARK: - ML-4: volume + AirPods listening mode

extension AudioOutputSwitcher {
    /// System output volume (0...1), read on demand — no listener, no polling.
    static func outputVolume() -> Double? {
        let device = defaultDevice(input: false)
        guard device != AudioObjectID(kAudioObjectUnknown) else { return nil }
        for element in [kAudioObjectPropertyElementMain, 1, 2] as [AudioObjectPropertyElement] {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                     mScope: kAudioObjectPropertyScopeOutput,
                                                     mElement: element)
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr {
                return Double(min(max(value, 0), 1))
            }
        }
        return nil
    }

    @discardableResult
    static func setOutputVolume(_ value: Double) -> Bool {
        let device = defaultDevice(input: false)
        guard device != AudioObjectID(kAudioObjectUnknown) else { return false }
        let clamped = Float32(min(max(value, 0), 1))
        var wrote = false
        for element in [kAudioObjectPropertyElementMain, 1, 2] as [AudioObjectPropertyElement] {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                     mScope: kAudioObjectPropertyScopeOutput,
                                                     mElement: element)
            var v = clamped
            if AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr {
                wrote = true
            }
        }
        return wrote
    }

    /// Resolves the current system-audio `AVOutputDevice` through the ObjC runtime, so this file compiles
    /// against every SDK and the feature simply disappears when the class/selector is not there.
    private static func systemAudioOutputDevice() -> NSObject? {
        guard let contextClass = NSClassFromString("AVOutputContext") as? NSObject.Type else { return nil }
        let shared = NSSelectorFromString("sharedSystemAudioContext")
        guard contextClass.responds(to: shared),
              let context = contextClass.perform(shared)?.takeUnretainedValue() as? NSObject else { return nil }
        return context.value(forKey: "outputDevice") as? NSObject
    }

    /// The AirPods' current listening mode, or nil when this Mac/these headphones cannot report one. The
    /// UI renders the whole Listening Mode control only when this is non-nil.
    static func bluetoothListeningMode() -> String? {
        guard let device = systemAudioOutputDevice(),
              device.responds(to: NSSelectorFromString("currentBluetoothListeningMode")),
              let mode = device.value(forKey: "currentBluetoothListeningMode") as? String,
              !mode.isEmpty else { return nil }
        return mode
    }

    /// True when a *callable* setter exists. Toggling stays hidden otherwise; there is no private fallback.
    static func canSetBluetoothListeningMode() -> Bool {
        systemAudioOutputDevice()?.responds(to: NSSelectorFromString("setCurrentBluetoothListeningMode:")) == true
    }

    static func setBluetoothListeningMode(_ mode: String) -> Bool {
        guard let device = systemAudioOutputDevice(),
              device.responds(to: NSSelectorFromString("setCurrentBluetoothListeningMode:")) else { return false }
        device.perform(NSSelectorFromString("setCurrentBluetoothListeningMode:"), with: mode as NSString)
        return true
    }
}

/// The Calm/Transparency/ANC labels shown in the output popover, keyed by the AVFoundation raw value.
enum BluetoothListeningMode: String, CaseIterable, Identifiable {
    case off = "AVBluetoothListeningModeOff"
    case transparency = "AVBluetoothListeningModeTransparency"
    case adaptive = "AVBluetoothListeningModeAdaptive"
    case noiseCancellation = "AVBluetoothListeningModeActiveNoiseCancellation"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return String(localized: "Off")
        case .transparency: return String(localized: "Transparency")
        case .adaptive: return String(localized: "Adaptive")
        case .noiseCancellation: return String(localized: "Noise Cancellation")
        }
    }

    var symbolName: String {
        switch self {
        case .off: return "ear"
        case .transparency: return "ear.badge.waveform"
        case .adaptive: return "waveform.path.ecg"
        case .noiseCancellation: return "ear.badge.checkmark"
        }
    }
}

/// A menu of outputs wrapped around any label (the AirPlay glyphs on the Now Playing card).
struct AudioOutputMenu<Glyph: View>: View {
    @State private var devices: [AudioOutputDevice] = []
    @State private var inputDevices: [AudioOutputDevice] = []
    let label: () -> Glyph

    var body: some View {
        Menu {
            Section("Audio Output") {
                ForEach(devices) { device in
                    Button { AudioOutputSwitcher.setDefault(device.id, input: false); refreshDevices() } label: {
                        if device.isDefault { Label(device.name, systemImage: "checkmark") } else { Text(verbatim: device.name) }
                    }
                }
            }
            if !inputDevices.isEmpty {
                Divider()
                Section("Microphone") {
                    ForEach(inputDevices) { device in
                        Button { AudioOutputSwitcher.setDefault(device.id, input: true); refreshDevices() } label: {
                            if device.isDefault { Label(device.name, systemImage: "checkmark") } else { Text(verbatim: device.name) }
                        }
                    }
                }
            }
        } label: { label() }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onAppear { refreshDevices() }
        .accessibilityLabel(Text("Audio Output"))
    }

    private func refreshDevices() {
        devices = AudioOutputSwitcher.devices(input: false)
        inputDevices = AudioOutputSwitcher.devices(input: true)
    }
}
