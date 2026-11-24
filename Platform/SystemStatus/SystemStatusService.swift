import AppKit
import AudioToolbox
import Combine
import CoreWLAN
import IOKit.ps
import Network

/// Live battery / Wi-Fi / volume facts for the edge-bar status cluster (Phase 7A-4).
///
/// Lazy and event-driven (STANDING_RULES §1.7e): nothing is created or observed until the first
/// `acquire()`, and the last `release()` tears every observer down. No polling timers.
/// Privacy: never asks for Location, never reads Wi-Fi passwords or keychain entries — the SSID
/// is shown only if the OS already hands it out.
@MainActor
final class SystemStatusService: ObservableObject {
    @Published private(set) var status = SystemStatus()

    private var consumers = 0
    private var powerSource: CFRunLoopSource?
    private var wifiObserverID: UUID?
    private var pathMonitor: NWPathMonitor?
    private var audioDevice = AudioObjectID(kAudioObjectUnknown)
    private var audioListenerQueue = DispatchQueue.main
    private var audioBlocks: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var systemBlock: AudioObjectPropertyListenerBlock?

    var isRunning: Bool { consumers > 0 }

    func acquire() {
        consumers += 1
        guard consumers == 1 else { return }
        startBattery()
        startWiFi()
        startNetworkPath()
        startAudio()
    }

    func release() {
        guard consumers > 0 else { return }
        consumers -= 1
        guard consumers == 0 else { return }
        stopBattery()
        stopWiFi()
        stopNetworkPath()
        stopAudio()
    }

    // MARK: Battery (IOKit power-source notification, run-loop source)

    private func startBattery() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let unmanaged = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let service = Unmanaged<SystemStatusService>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { service.refreshBattery() } }
        }, context) else { return }
        let source = unmanaged.takeRetainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        powerSource = source
        refreshBattery()
    }

    private func stopBattery() {
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode) }
        powerSource = nil
    }

    private func refreshBattery() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            update { $0.battery = .noBattery }
            return
        }
        var battery = list.lazy
            .compactMap { IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any] }
            .compactMap { BatteryStatus(powerSource: $0) }
            .first ?? .noBattery
        if battery.hasBattery { battery.facts = PowerFactsReader.read(isCharging: battery.isCharging) }
        update { $0.battery = battery }
    }

    // MARK: Wi-Fi (CoreWLAN events via shared ref-counted monitor)

    private func startWiFi() {
        guard wifiObserverID == nil else { return }
        wifiObserverID = SharedWiFiMonitor.shared.addObserver { [weak self] nextWiFi in
            self?.update { $0.wifi = nextWiFi }
        }
    }

    private func stopWiFi() {
        guard let id = wifiObserverID else { return }
        wifiObserverID = nil
        SharedWiFiMonitor.shared.removeObserver(id)
    }

    private func refreshWiFi() {
        SharedWiFiMonitor.shared.refresh()
    }

    // MARK: Network Path (event-driven Ethernet / Personal Hotspot detection)

    private func startNetworkPath() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            let ethernet = satisfied && path.usesInterfaceType(.wiredEthernet)
            let hotspot = satisfied && path.isExpensive && path.usesInterfaceType(.wifi)
            Task { @MainActor [weak self] in
                self?.update {
                    $0.wiredEthernetConnected = ethernet
                    $0.isHotspotActive = hotspot
                }
            }
        }
        monitor.start(queue: .main)
        pathMonitor = monitor
    }

    private func stopNetworkPath() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    // MARK: Volume (CoreAudio property listeners on the default output device)

    private func startAudio() {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.rebindAudioDevice() }
        }
        systemBlock = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, audioListenerQueue, block)
        rebindAudioDevice()
    }

    private func stopAudio() {
        unbindAudioDevice()
        if let systemBlock {
            var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, audioListenerQueue, systemBlock)
        }
        systemBlock = nil
    }

    private func rebindAudioDevice() {
        unbindAudioDevice()
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return }
        audioDevice = device
        for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
            for element in [kAudioObjectPropertyElementMain, 1, 2] {
                var property = Self.address(selector, scope: kAudioDevicePropertyScopeOutput, element: element)
                guard AudioObjectHasProperty(device, &property) else { continue }
                let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.refreshVolume() }
                }
                AudioObjectAddPropertyListenerBlock(device, &property, audioListenerQueue, block)
                audioBlocks.append((property, block))
            }
        }
        refreshVolume()
    }

    private func unbindAudioDevice() {
        for (var property, block) in audioBlocks {
            AudioObjectRemovePropertyListenerBlock(audioDevice, &property, audioListenerQueue, block)
        }
        audioBlocks = []
        audioDevice = AudioObjectID(kAudioObjectUnknown)
    }

    private func refreshVolume() {
        guard audioDevice != kAudioObjectUnknown else { return }
        let level = Self.readFloat(audioDevice, kAudioDevicePropertyVolumeScalar) ?? 1
        let muted = (Self.readUInt32(audioDevice, kAudioDevicePropertyMute) ?? 0) != 0
        update { $0.volume = VolumeStatus(level: level, isMuted: muted) }
    }

    /// The device's level right now. The published `status.volume` lags a write by one listener hop, and a wheel
    /// that turns faster than that would read a stale base and lose steps (measured live 2026-10-21: three
    /// 2.5 % steps moved the volume 3 points instead of 7.5).
    var currentVolumeLevel: Double {
        guard audioDevice != kAudioObjectUnknown,
              let level = Self.readFloat(audioDevice, kAudioDevicePropertyVolumeScalar) else { return Double(status.volume.level) }
        return Double(level)
    }

    /// Sets the output volume (0...1) on whichever elements the device exposes. Returns success.
    @discardableResult
    func setVolume(_ level: Float) -> Bool {
        guard audioDevice != kAudioObjectUnknown else { return false }
        var value = Swift.min(1, Swift.max(0, level))
        var wrote = false
        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            var property = Self.address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: element)
            var settable: DarwinBoolean = false
            guard AudioObjectHasProperty(audioDevice, &property),
                  AudioObjectIsPropertySettable(audioDevice, &property, &settable) == noErr, settable.boolValue else { continue }
            wrote = AudioObjectSetPropertyData(audioDevice, &property, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr || wrote
        }
        return wrote
    }

    /// Toggles output mute on the default audio device. Returns whether the mute property was written.
    @discardableResult
    func toggleMute() -> Bool {
        let wrote = Self.setDefaultOutputMuted(!status.volume.isMuted)
        if wrote { refreshVolume() }
        return wrote
    }

    nonisolated static func isDefaultOutputMuted() -> Bool? {
        let device = defaultOutputDeviceID()
        guard device != kAudioObjectUnknown else { return nil }
        return (readUInt32(device, kAudioDevicePropertyMute) ?? 0) != 0
    }

    @discardableResult
    nonisolated static func setDefaultOutputMuted(_ muted: Bool) -> Bool {
        let device = defaultOutputDeviceID()
        guard device != kAudioObjectUnknown else { return false }
        var value: UInt32 = muted ? 1 : 0
        var wrote = false
        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            var property = address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput, element: element)
            var settable: DarwinBoolean = false
            guard AudioObjectHasProperty(device, &property),
                  AudioObjectIsPropertySettable(device, &property, &settable) == noErr, settable.boolValue else { continue }
            wrote = AudioObjectSetPropertyData(device, &property, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr || wrote
        }
        return wrote
    }

    nonisolated private static func defaultOutputDeviceID() -> AudioObjectID {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else {
            return AudioObjectID(kAudioObjectUnknown)
        }
        return device
    }

    // MARK: Helpers

    private func update(_ change: (inout SystemStatus) -> Void) {
        var next = status
        change(&next)
        if next != status { status = next }
    }

    nonisolated private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    nonisolated private static func readFloat(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Float? {
        for element in [kAudioObjectPropertyElementMain, 1] {
            var property = address(selector, scope: kAudioDevicePropertyScopeOutput, element: element)
            guard AudioObjectHasProperty(device, &property) else { continue }
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr { return value }
        }
        return nil
    }

    nonisolated private static func readUInt32(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        for element in [kAudioObjectPropertyElementMain, 1] {
            var property = address(selector, scope: kAudioDevicePropertyScopeOutput, element: element)
            guard AudioObjectHasProperty(device, &property) else { continue }
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr { return value }
        }
        return nil
    }
}

/// Single ref-counted owner of `CWWiFiClient.shared().delegate` so multiple status clusters never
/// overwrite or clear each other's CoreWLAN delegate callbacks.
@MainActor
private final class SharedWiFiMonitor {
    static let shared = SharedWiFiMonitor()

    private var observers: [UUID: (WiFiStatus) -> Void] = [:]
    private var latest: WiFiStatus?
    private var wifiClient: CWWiFiClient?
    private var wifiDelegate: WiFiEventBridge?
    private var refreshTask: Task<Void, Never>?

    func addObserver(_ handler: @escaping (WiFiStatus) -> Void) -> UUID {
        let id = UUID()
        observers[id] = handler
        if observers.count == 1 {
            let client = CWWiFiClient.shared()
            let bridge = WiFiEventBridge {
                DispatchQueue.main.async { MainActor.assumeIsolated { SharedWiFiMonitor.shared.refresh() } }
            }
            client.delegate = bridge
            for event in [CWEventType.powerDidChange, .ssidDidChange, .linkDidChange, .linkQualityDidChange] {
                try? client.startMonitoringEvent(with: event)
            }
            wifiClient = client
            wifiDelegate = bridge
            refresh()
        } else if let latest {
            handler(latest)
        } else {
            refresh()
        }
        return id
    }

    func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
        guard observers.isEmpty else { return }
        refreshTask?.cancel()
        refreshTask = nil
        try? wifiClient?.stopMonitoringAllEvents()
        wifiClient?.delegate = nil
        wifiClient = nil
        wifiDelegate = nil
    }

    func refresh() {
        guard !observers.isEmpty else { return }
        let delayInitial = refreshTask != nil
        refreshTask?.cancel()
        refreshTask = Task.detached(priority: .utility) {
            if delayInitial {
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
            }
            let nextWiFi: WiFiStatus
            if let interface = CWWiFiClient.shared().interface() {
                let rssi = interface.rssiValue()
                nextWiFi = WiFiStatus(
                    isPoweredOn: interface.powerOn(),
                    ssid: interface.ssid(),
                    rssi: rssi == 0 ? nil : rssi
                )
            } else {
                nextWiFi = .off
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                SharedWiFiMonitor.shared.apply(nextWiFi)
            }
        }
    }

    private func apply(_ nextWiFi: WiFiStatus) {
        refreshTask = nil
        latest = nextWiFi
        for handler in observers.values {
            handler(nextWiFi)
        }
    }
}

/// CoreWLAN delivers delegate callbacks on arbitrary threads; this bridge just pings a closure.
private final class WiFiEventBridge: NSObject, CWEventDelegate {
    private let onChange: () -> Void
    init(onChange: @escaping () -> Void) { self.onChange = onChange }
    func powerStateDidChangeForWiFiInterface(withName interfaceName: String) { onChange() }
    func ssidDidChangeForWiFiInterface(withName interfaceName: String) { onChange() }
    func linkDidChangeForWiFiInterface(withName interfaceName: String) { onChange() }
    func linkQualityDidChangeForWiFiInterface(withName interfaceName: String, rssi: Int, transmitRate: Double) { onChange() }
}
