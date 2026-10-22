import Foundation

/// Phase 59c — the battery numbers past its percentage: time to empty or full, the watts going in, the
/// thermal pressure macOS reports, and whether Low Power Mode is on. Every field is optional: a Mac
/// without a battery, a key this machine does not publish, and macOS's "still calculating" sentinel all
/// read as nil — never as a zero that looks like a real reading.
struct PowerFacts: Equatable, Sendable {
    /// Seconds to empty on battery, to full while charging; nil until macOS has an estimate.
    var secondsRemaining: Int?
    /// Watts flowing into the battery. Nil on battery or with nothing flowing.
    var watts: Double?
    var thermal: PowerThermal = .nominal
    var isLowPowerMode = false
    /// Whether `secondsRemaining` counts to empty (on battery) or to full (charging).
    var isCharging = false

    static let empty = PowerFacts()

    /// `Time to Empty` / `Time to Full Charge` are minutes. 65535 is macOS's "calculating" and -1 or 0
    /// mean "no estimate" — all three are nil, not "0 minutes".
    static func secondsRemaining(powerSource info: [String: Any], isCharging: Bool) -> Int? {
        guard let minutes = info[isCharging ? "Time to Full Charge" : "Time to Empty"] as? Int,
              minutes > 0, minutes != 65535 else { return nil }
        return minutes * 60
    }

    /// mA × mV = µW, so the product is divided by a million. A discharging amperage arrives as the
    /// unsigned 64-bit wrap; reading it through `Int64(bitPattern:)` is what makes it negative again,
    /// and nothing flowing into the battery is nil rather than a negative wattage.
    static func watts(amperage: Int64?, millivolts: Int64?) -> Double? {
        guard let amperage, let millivolts, millivolts > 0 else { return nil }
        let value = Double(amperage) * Double(millivolts) / 1_000_000
        return value > 0 ? value : nil
    }

    /// "1h 24m" / "48m"; nil when there is no estimate.
    static func durationText(_ seconds: Int?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(1, minutes))m"
    }

    /// One line for a tile or a tooltip: "1h 24m left · 18.2 W · Fair".
    var summary: String? {
        var parts: [String] = []
        if let remaining = Self.durationText(secondsRemaining) {
            parts.append(isCharging ? "\(remaining) \(String(localized: "to full"))"
                                    : "\(remaining) \(String(localized: "left"))")
        }
        if let watts { parts.append(String(format: "%.1f W", watts)) }
        if thermal != .nominal { parts.append(thermal.name) }
        if isLowPowerMode { parts.append(String(localized: "Low Power Mode")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// `ProcessInfo.ThermalState`, named. A machine that is merely warm reads `nominal`, so the UI only
/// mentions heat when the OS says there is some.
enum PowerThermal: String, CaseIterable, Sendable {
    case nominal, fair, serious, critical

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        default: self = .nominal
        }
    }

    var name: String {
        switch self {
        case .nominal: return String(localized: "Nominal")
        case .fair: return String(localized: "Fair")
        case .serious: return String(localized: "Serious")
        case .critical: return String(localized: "Critical")
        }
    }
}
