import Foundation

/// Battery health from the `AppleSmartBattery` registry entry (Phase 7B-V3). Pure parsing; the Platform reader
/// supplies the dictionary. Public IOKit only.
struct BatteryHealth: Equatable, Sendable {
    var cycleCount: Int
    var healthPercent: Int?
    var temperatureCelsius: Double?

    init?(registry info: [String: Any]) {
        guard let cycles = info["CycleCount"] as? Int else { return nil }
        cycleCount = cycles
        // Apple Silicon reports MaxCapacity as a percentage; Intel as mAh next to DesignCapacity.
        let design = info["DesignCapacity"] as? Int
        let rawMax = (info["AppleRawMaxCapacity"] as? Int) ?? (info["MaxCapacity"] as? Int)
        if let design, design > 0, let rawMax, rawMax > 100 {
            healthPercent = min(100, Int((Double(rawMax) / Double(design) * 100).rounded()))
        } else if let m = info["MaxCapacity"] as? Int, m <= 100 {
            healthPercent = m
        } else {
            healthPercent = nil
        }
        // Reported in hundredths of a degree.
        temperatureCelsius = (info["Temperature"] as? Int).map { Double($0) / 100 }
    }
}

struct TopProcess: Equatable, Sendable {
    var name: String
    var cpu: Double
}

enum TopProcessParser {
    /// Parses `ps -Ao pcpu=,comm=` output: sums processes that share a name, highest CPU first, trims to `limit`.
    static func parse(_ text: String, limit: Int) -> [TopProcess] {
        var totals: [String: Double] = [:]
        var order: [String] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " "), let cpu = Double(trimmed[..<space]) else { continue }
            let path = trimmed[trimmed.index(after: space)...].trimmingCharacters(in: .whitespaces)
            let name = path.split(separator: "/").last.map(String.init) ?? path
            guard !name.isEmpty, cpu >= 0 else { continue }
            if totals[name] == nil { order.append(name) }
            totals[name, default: 0] += cpu
        }
        return order.map { TopProcess(name: $0, cpu: totals[$0] ?? 0) }
            .sorted { $0.cpu > $1.cpu }
            .prefix(max(0, limit)).map { $0 }
    }
}
