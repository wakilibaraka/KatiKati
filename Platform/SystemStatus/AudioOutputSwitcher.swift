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
    static func devices(input: Bool = false) -> [AudioOutputDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        let current = defaultDevice(input: input)
        return ids.compactMap { id in
            guard hasStreams(id, input: input), let name = name(of: id) else { return nil }
            return AudioOutputDevice(id: id, name: name, isDefault: id == current)
        }
    }

    @discardableResult
    static func setDefault(_ id: AudioObjectID, input: Bool = false) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = id
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &device) == noErr
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

/// A menu of outputs wrapped around any label (the AirPlay glyphs on the Now Playing card).
struct AudioOutputMenu<Glyph: View>: View {
    @State private var devices: [AudioOutputDevice] = []
    let label: () -> Glyph

    var body: some View {
        Menu {
            ForEach(devices) { device in
                Button { AudioOutputSwitcher.setDefault(device.id); devices = AudioOutputSwitcher.devices() } label: {
                    if device.isDefault { Label(device.name, systemImage: "checkmark") } else { Text(verbatim: device.name) }
                }
            }
        } label: { label() }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onAppear { devices = AudioOutputSwitcher.devices() }
        .accessibilityLabel(Text("Audio Output"))
    }
}
