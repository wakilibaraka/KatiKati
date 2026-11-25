import Foundation

/// Pure value types + parsing for the edge-bar status cluster (Phase 7A-4). No IOKit /
/// CoreWLAN / CoreAudio here — Platform monitors feed raw facts in, the UI reads these.

struct BatteryStatus: Equatable, Sendable {
    /// 0...100; nil when no internal battery (desktop Mac).
    var level: Int?
    var isCharging: Bool
    var isPluggedIn: Bool
    /// 59c: time to empty or full, charging watts, thermal state, Low Power Mode. Empty on a Mac with
    /// no battery, and every field stays optional so the UI can hide what this machine cannot report.
    var facts = PowerFacts.empty

    static let noBattery = BatteryStatus(level: nil, isCharging: false, isPluggedIn: true)

    var hasBattery: Bool { level != nil }

    /// Parses one `IOPSGetPowerSourceDescription` dictionary. Returns nil for non-battery sources
    /// (UPS, etc.) or malformed capacity values.
    init?(powerSource info: [String: Any]) {
        if let type = info["Type"] as? String, type != "InternalBattery" { return nil }
        guard let current = info["Current Capacity"] as? Int,
              let max = info["Max Capacity"] as? Int, max > 0 else { return nil }
        self.level = Swift.min(100, Swift.max(0, Int((Double(current) / Double(max) * 100).rounded())))
        self.isCharging = (info["Is Charging"] as? Bool) ?? false
        self.isPluggedIn = (info["Power Source State"] as? String) == "AC Power"
    }

    init(level: Int?, isCharging: Bool, isPluggedIn: Bool) {
        self.level = level.map { Swift.min(100, Swift.max(0, $0)) }
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
    }

    /// SF Symbol for the battery glyph (fill steps), plain bolt variant while charging.
    var symbolName: String {
        guard let level else { return "powerplug" }
        if isCharging { return "battery.100.bolt" }
        switch level {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}

struct WiFiStatus: Equatable, Sendable {
    var isPoweredOn: Bool
    /// nil when not associated, or when the OS withholds the name (no Location permission);
    /// we never request that permission and never read passwords.
    var ssid: String?
    /// dBm, typically -30 (strong) … -100 (weak); nil when not associated.
    var rssi: Int?

    static let off = WiFiStatus(isPoweredOn: false, ssid: nil, rssi: nil)

    var isConnected: Bool { isPoweredOn && rssi != nil }

    /// 0...3 signal steps from RSSI.
    var signalSteps: Int {
        guard isConnected, let rssi else { return 0 }
        switch rssi {
        case (-55)...: return 3
        case (-67)...: return 2
        case (-80)...: return 1
        default: return 0
        }
    }

    /// SF Symbol `wifi` variable value (0...1); nil renders the slashed glyph.
    var symbolName: String { isConnected ? "wifi" : (isPoweredOn ? "wifi.exclamationmark" : "wifi.slash") }
    var symbolVariableValue: Double { Double(signalSteps) / 3 }
}

struct VolumeStatus: Equatable, Sendable {
    /// 0...1 output scalar.
    var level: Float
    var isMuted: Bool

    init(level: Float, isMuted: Bool) {
        self.level = level.isFinite ? Swift.min(1, Swift.max(0, level)) : 0
        self.isMuted = isMuted
    }

    var symbolName: String {
        if isMuted || level == 0 { return "speaker.slash.fill" }
        switch level {
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    /// Whole-percent label, 0 while muted.
    var percent: Int { isMuted ? 0 : Int((level * 100).rounded()) }
}

/// Network / audio link state displayed in the Status Trio menu-bar ring center.
enum NetworkLinkKind: Equatable, Hashable, Sendable {
    case wifi(steps: Int)
    case ethernet
    case hotspot
    case bluetoothAudio
    case offline
}

struct SystemStatus: Equatable, Sendable {
    var battery: BatteryStatus = .noBattery
    var wifi: WiFiStatus = .off
    var volume: VolumeStatus = VolumeStatus(level: 0.5, isMuted: false)
    var wiredEthernetConnected = false
    var isHotspotActive = false
    var bluetoothAudioDeviceName: String?

    var isBatteryLow: Bool {
        guard let level = battery.level else { return false }
        return !battery.isCharging && level < 20
    }

    func activeLink(showBluetoothAudio: Bool = true) -> NetworkLinkKind {
        if showBluetoothAudio, let name = bluetoothAudioDeviceName, !name.isEmpty { return .bluetoothAudio }
        if isHotspotActive { return .hotspot }
        if wiredEthernetConnected { return .ethernet }
        if wifi.isConnected { return .wifi(steps: wifi.signalSteps) }
        return .offline
    }
}

// MARK: - MB-10: per-app audio mix

/// One app's mix setting. Gains persist by bundle id (falling back to the name for helper processes
/// with no bundle), so a relaunch restores the level without remembering a pid, which is reused by
/// whichever process the system starts next.
struct PerAppAudioMix: Equatable, Sendable {
    var bundleID: String?
    var name: String
    var gain: Double
    var isMuted: Bool
}

/// Why a per-app route could not be created. The card shows this instead of a slider that looks active
/// while nothing is routed.
enum PerAppAudioFailure: Error, Equatable, Sendable {
    /// The private process tap was refused (missing System Audio Recording grant, or the HAL said no).
    case tap
    /// The private aggregate device could not be built on the current output.
    case aggregate
    /// The aggregate was built but its IOProc would not start.
    case start
    /// The tap and the output device do not share a Float32 layout this engine can copy.
    case layout

    var isLayoutMismatch: Bool { self == .layout }
}

/// Pure rules for the opt-in mixer. The engine owns CoreAudio; everything that can be decided from
/// numbers lives here so it is unit-tested rather than only listened to.
enum PerAppAudioRules {
    static func clamped(_ gain: Double) -> Double {
        guard gain.isFinite else { return 1 }
        return min(1, max(0, gain))
    }

    /// Unity (or a mute) is the engine's cue to stop rerouting: a 100 % tap is pure added latency.
    static func effectiveGain(_ mix: PerAppAudioMix) -> Float {
        mix.isMuted ? 0 : Float(clamped(mix.gain))
    }

    static func needsRouting(_ mix: PerAppAudioMix) -> Bool {
        mix.isMuted || clamped(mix.gain) < 0.999
    }

    static func percent(_ gain: Double) -> Int {
        Int((clamped(gain) * 100).rounded())
    }
}
