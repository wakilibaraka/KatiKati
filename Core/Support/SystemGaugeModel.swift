import Foundation

/// Pure metrics model for the circular RAM/CPU pressure gauge FAB and dynamic island anchor.
public struct SystemGaugeMetrics: Equatable, Sendable {
    public let ramPercentage: Int       // 0..100
    public let cpuPressure: Double      // 0.0..1.0
    public let pressureLevel: PressureLevel

    public enum PressureLevel: String, CaseIterable, Equatable, Sendable {
        case normal     // green
        case warning    // orange
        case critical   // red
    }

    public init(ramPercentage: Int, cpuPressure: Double) {
        self.ramPercentage = max(0, min(100, ramPercentage))
        self.cpuPressure = max(0.0, min(1.0, cpuPressure))
        if cpuPressure > 0.85 || ramPercentage > 90 {
            self.pressureLevel = .critical
        } else if cpuPressure > 0.60 || ramPercentage > 75 {
            self.pressureLevel = .warning
        } else {
            self.pressureLevel = .normal
        }
    }

    public static func compute(usedMemory: UInt64, totalMemory: UInt64, cpuUsage: Double) -> SystemGaugeMetrics {
        let ramPct = totalMemory > 0 ? Int(Double(usedMemory) / Double(totalMemory) * 100.0) : 0
        return SystemGaugeMetrics(ramPercentage: ramPct, cpuPressure: cpuUsage)
    }
}

/// Dock app icon masking style (Phase 32d). **Packed (owner 2026-10-16):** the Settings row is gone,
/// so the frame is fixed at launch by the `DOCK_ICON_FRAME` switch — squircle + nothing else set is
/// what every dock icon wears today. The on-disk key `com.katikati.dock.iconShape` retires with the
/// row, which is why this type no longer carries a title: nothing user-facing names these cases.
public enum DockIconShape: String, Equatable, Codable, Sendable {
    case squircle = "squircle"
    case circle = "circle"

    /// Anything unset or unrecognized is today's squircle, so the dock's look cannot change by accident.
    public static func packedValue(_ raw: String?) -> DockIconShape {
        raw.flatMap(DockIconShape.init(rawValue:)) ?? .squircle
    }

    /// Read once per process: the switch is environment-only, so it cannot change mid-run.
    public static let packed = packedValue(DebugSwitch.dockIconFrame.value())
}

/// Weather widget presentation preset.
public enum WeatherChipPreset: String, CaseIterable, Equatable, Codable, Sendable {
    case classicPill = "classic"
    case detailedForecast = "detailed"

    public var title: String {
        switch self {
        case .classicPill: return "Classic Weather Pill"
        case .detailedForecast: return "Detailed 3-Day Forecast"
        }
    }
}

/// Now Playing presentation preset.
public enum NowPlayingPreset: String, CaseIterable, Equatable, Codable, Sendable {
    case miniChip = "mini"
    case expandedCard = "expanded"

    public var title: String {
        switch self {
        case .miniChip: return "Mini Player"
        case .expandedCard: return "Expanded Artwork Card"
        }
    }
}
