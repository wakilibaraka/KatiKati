import AudioToolbox
import CoreAudio
import Darwin
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

// MARK: - MB-10: opt-in per-app audio mixer

/// One process the audio HAL knows about. Read-only: listing never creates a tap, so opening the
/// module cannot change what the Mac is playing.
struct AppAudioProcess: Identifiable, Equatable {
    let id: AudioObjectID
    let pid: Int32
    let bundleID: String?
    let name: String
    let isRunningOutput: Bool

    /// One identity rule for levels, routes and persisted-free state: bundle id when there is one,
    /// so helper processes and renames don't split a row; the display name otherwise.
    var storageKey: String {
        if let bundleID, !bundleID.isEmpty { return bundleID }
        return name
    }
}

/// The Tier B mixer. Built only by its card (`HubAudioMixerCard`), which exists only while the module
/// is switched on, so an off module owns no CoreAudio objects and prompts for nothing.
///
/// Routing model: a private tap of exactly one process, muted at the source, rendered back to the
/// current default output through a private aggregate device. Gain 100 % (and no mute) tears the
/// route down instead of passing audio through untouched — a 1:1 tap only adds latency. Any failure
/// destroys the whole session, which restores the app's normal output path.
@MainActor
final class PerAppAudioEngine: ObservableObject {
    @Published private(set) var processes: [AppAudioProcess] = []
    @Published private(set) var routing: Set<Int32> = []
    @Published private(set) var failures: [Int32: PerAppAudioFailure] = [:]

    /// True while at least one app's level cannot be applied; the card shows `Volume Unavailable`.
    var unavailable: Bool { !failures.isEmpty }

    func failure(for process: AppAudioProcess) -> PerAppAudioFailure? {
        failures[process.pid]
    }

    /// Levels live only as long as the card. Closing the hub tears every route down and restores the
    /// app to unity, so a remembered level that is not being enforced would be a lie — nothing is
    /// written to disk, and reopening starts from an honest 100 %.
    private var mixes: [String: PerAppAudioMix] = [:]
    private var sessions: [Int32: MixSession] = [:]

    func start() { refresh() }

    /// Called when the card leaves the hub: every route is torn down, so closing the panel can never
    /// leave an app muted behind a view that no longer exists.
    func stop() {
        for pid in Array(sessions.keys) { teardown(pid: pid) }
        mixes = [:]
        processes = []
        failures = [:]
    }

    func refresh() { processes = Self.readProcesses() }

    func gain(for process: AppAudioProcess) -> Double {
        mixes[process.storageKey]?.gain ?? 1
    }

    func isMuted(_ process: AppAudioProcess) -> Bool {
        mixes[process.storageKey]?.isMuted ?? false
    }

    func isRouted(_ process: AppAudioProcess) -> Bool {
        routing.contains(process.pid)
    }

    func setGain(_ value: Double, for process: AppAudioProcess) {
        var mix = mix(for: process)
        mix.gain = PerAppAudioRules.clamped(value)
        if mix.gain > 0 { mix.isMuted = false }
        commit(mix, to: process)
    }

    func setMuted(_ muted: Bool, for process: AppAudioProcess) {
        var mix = mix(for: process)
        mix.isMuted = muted
        commit(mix, to: process)
    }

    private func mix(for process: AppAudioProcess) -> PerAppAudioMix {
        mixes[process.storageKey]
            ?? PerAppAudioMix(bundleID: process.bundleID, name: process.name, gain: 1, isMuted: false)
    }

    private func commit(_ mix: PerAppAudioMix, to process: AppAudioProcess) {
        var current = mix
        current.bundleID = process.bundleID
        current.name = process.name
        mixes[process.storageKey] = current
        apply(current, to: process)
    }

    // MARK: Routing

    private func apply(_ mix: PerAppAudioMix, to process: AppAudioProcess) {
        guard PerAppAudioRules.needsRouting(mix) else { teardown(pid: process.pid); return }
        if let session = sessions[process.pid], session.key == process.storageKey {
            session.setGain(PerAppAudioRules.effectiveGain(mix))
            routing.insert(process.pid)
            return
        }
        teardown(pid: process.pid)
        do {
            sessions[process.pid] = try MixSession(process: process, gain: PerAppAudioRules.effectiveGain(mix))
            routing.insert(process.pid)
        } catch let reason as PerAppAudioFailure {
            // Nothing is routed, so the row must not keep showing a level that is not running.
            failures[process.pid] = reason
            mixes[process.storageKey] = nil
        } catch {
            failures[process.pid] = .tap
            mixes[process.storageKey] = nil
        }
    }

    private func teardown(pid: Int32) {
        sessions.removeValue(forKey: pid)?.teardown()
        routing.remove(pid)
        failures[pid] = nil
    }

    // MARK: HAL discovery (read-only)

    nonisolated static func readProcesses() -> [AppAudioProcess] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var pidAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID,
                                                        mScope: kAudioObjectPropertyScopeGlobal,
                                                        mElement: kAudioObjectPropertyElementMain)
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(id, &pidAddress, 0, nil, &pidSize, &pid) == noErr, pid > 0 else { return nil }

            var bundleAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID,
                                                           mScope: kAudioObjectPropertyScopeGlobal,
                                                           mElement: kAudioObjectPropertyElementMain)
            var bundle: Unmanaged<CFString>?
            var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let bundleID: String? = AudioObjectGetPropertyData(id, &bundleAddress, 0, nil, &bundleSize, &bundle) == noErr
                ? (bundle?.takeRetainedValue() as String?) : nil

            var runningAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningOutput,
                                                            mScope: kAudioObjectPropertyScopeGlobal,
                                                            mElement: kAudioObjectPropertyElementMain)
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            let isRunning = AudioObjectGetPropertyData(id, &runningAddress, 0, nil, &runningSize, &running) == noErr && running != 0

            guard let name = Self.appName(pid: pid) else { return nil }
            return AppAudioProcess(id: id, pid: pid, bundleID: bundleID, name: name, isRunningOutput: isRunning)
        }
        .filter { $0.pid != getpid() }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Only processes that live inside an `.app` belong in the card: daemons and audio HAL helpers are
    /// skipped, so a level can never be offered for something that is not the user's app. Electron
    /// helpers take their outermost bundle name, so “YouTube Music Helper” still reads as the app.
    nonisolated private static func appName(pid: pid_t) -> String? {
        if let name = NSRunningApplication(processIdentifier: pid)?.localizedName { return name }
        // PROC_PIDPATHINFO_MAXSIZE is 4 * MAXPATHLEN; the C constant is not exported to Swift.
        var buffer = [UInt8](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let path = String(cString: buffer)
        guard let appRange = path.range(of: ".app/") else { return nil }
        return path[..<appRange.lowerBound].split(separator: "/").last.map(String.init)
    }
}

/// One process's live route. Deliberately small and fail-safe: if any CoreAudio call fails the whole
/// session is destroyed in `init`, and destroying the tap un-mutes the app.
private final class MixSession {
    let pid: Int32
    let key: String
    private(set) var tap: AudioObjectID = kAudioObjectUnknown
    private(set) var aggregate: AudioObjectID = kAudioObjectUnknown
    private(set) var ioProc: AudioDeviceIOProcID?
    private var gainPointer: UnsafeMutablePointer<Float>?

    init(process: AppAudioProcess, gain value: Float) throws {
        pid = process.pid
        key = process.storageKey
        let pointer = UnsafeMutablePointer<Float>.allocate(capacity: 1)
        pointer.pointee = value
        gainPointer = pointer

        let description = CATapDescription(stereoMixdownOfProcesses: [process.id])
        description.name = "KatiKati Mix"
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped

        var tapID = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr, tapID != kAudioObjectUnknown else {
            destroy()
            throw PerAppAudioFailure.tap
        }
        tap = tapID

        // Render only when the tap and the current output agree on a plain Float32 layout. A mismatch
        // (multichannel interface, non-interleaved vs interleaved) fails closed: the tap is destroyed
        // before the aggregate exists, so the app's audio is never touched.
        guard let tapFormat = Self.format(of: tapID, selector: kAudioTapPropertyFormat),
              let target = Self.outputTarget() else { destroy(); throw PerAppAudioFailure.layout }
        guard Self.isRenderable(tapFormat, target.format) else { destroy(); throw PerAppAudioFailure.layout }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "KatiKati Mix",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [description.uuid.uuidString],
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: target.uid]],
            kAudioAggregateDeviceMainSubDeviceKey: target.uid,
            kAudioAggregateDeviceIsStackedKey: false,
        ]
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID) == noErr,
              aggregateID != kAudioObjectUnknown else { destroy(); throw PerAppAudioFailure.aggregate }
        aggregate = aggregateID

        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, input, _, output, _ in
            let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            let destination = UnsafeMutableAudioBufferListPointer(output)
            let level = pointer.pointee
            for index in 0..<min(source.count, destination.count) {
                guard let src = source[index].mData, let dst = destination[index].mData else { continue }
                let bytes = min(Int(source[index].mDataByteSize), Int(destination[index].mDataByteSize))
                memcpy(dst, src, bytes)
                guard level < 0.999 else { continue }
                let samples = dst.assumingMemoryBound(to: Float.self)
                for sample in 0..<(bytes / MemoryLayout<Float>.size) { samples[sample] *= level }
            }
        }
        guard status == noErr, let procID else { destroy(); throw PerAppAudioFailure.start }
        ioProc = procID
        guard AudioDeviceStart(aggregateID, procID) == noErr else { destroy(); throw PerAppAudioFailure.start }
    }

    /// If the engine dies without `stop()` (a skipped `onDisappear`, a replaced hosting view), the
    /// session must still destroy its tap: the tap holds the app's audio muted, so leaking it would
    /// keep that app silent for the rest of the process's life.
    deinit { destroy() }

    func setGain(_ value: Float) { gainPointer?.pointee = value }

    func teardown() { destroy() }

    private func destroy() {
        if aggregate != kAudioObjectUnknown {
            if let ioProc {
                AudioDeviceStop(aggregate, ioProc)
                AudioDeviceDestroyIOProcID(aggregate, ioProc)
            }
            AudioHardwareDestroyAggregateDevice(aggregate)
            aggregate = kAudioObjectUnknown
        }
        ioProc = nil
        if tap != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tap)
            tap = kAudioObjectUnknown
        }
        if let pointer = gainPointer {
            pointer.deallocate()
            gainPointer = nil
        }
    }

    private static func format(of object: AudioObjectID, selector: AudioObjectPropertySelector) -> AudioStreamBasicDescription? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &format) == noErr else { return nil }
        return format
    }

    /// The current default output, read once: the aggregate needs its UID and the format guard needs
    /// its stream format, so both come from the same device instead of two separate lookups.
    private struct OutputTarget {
        let uid: String
        let format: AudioStreamBasicDescription
    }

    private static func outputTarget() -> OutputTarget? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }

        var uidAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
                                                    mScope: kAudioObjectPropertyScopeGlobal,
                                                    mElement: kAudioObjectPropertyElementMain)
        var uid: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &uidSize, &uid) == noErr, let uid else { return nil }

        var stream = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamFormat,
                                                mScope: kAudioObjectPropertyScopeOutput,
                                                mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(device, &stream, 0, nil, &formatSize, &format) == noErr else { return nil }

        return OutputTarget(uid: uid.takeRetainedValue() as String, format: format)
    }

    /// Float32 on both sides, same channel count, same interleaving — the only arrangement the
    /// per-buffer copy below can render without guessing.
    private static func isRenderable(_ tap: AudioStreamBasicDescription, _ output: AudioStreamBasicDescription) -> Bool {
        let float: AudioFormatFlags = kAudioFormatFlagIsFloat
        let nonInterleaved: AudioFormatFlags = kAudioFormatFlagIsNonInterleaved
        guard tap.mFormatID == kAudioFormatLinearPCM, output.mFormatID == kAudioFormatLinearPCM,
              tap.mBitsPerChannel == 32, output.mBitsPerChannel == 32,
              tap.mFormatFlags & float != 0, output.mFormatFlags & float != 0,
              tap.mChannelsPerFrame == output.mChannelsPerFrame, tap.mChannelsPerFrame > 0 else { return false }
        return (tap.mFormatFlags & nonInterleaved) == (output.mFormatFlags & nonInterleaved)
    }

}
