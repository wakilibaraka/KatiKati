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

struct SystemStatus: Equatable, Sendable {
    var battery: BatteryStatus = .noBattery
    var wifi: WiFiStatus = .off
    var volume: VolumeStatus = VolumeStatus(level: 0.5, isMuted: false)
}
