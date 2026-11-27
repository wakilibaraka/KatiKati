import Foundation

struct AIUsageAlert: Equatable, Sendable {
    enum Severity: Equatable, Sendable {
        case warning
        case critical
    }

    let provider: AgentProvider
    let usedPercent: Int
    let resetsAt: Date?
    let severity: Severity
}

/// N6: fires once per threshold (80% / 95%) per provider reset window so the notch alerts the user
/// without repeating on every log refresh. Pure and dual-compiled.
struct UsageThresholdPolicy: Equatable, Sendable {
    static let defaultThresholds = [80, 95]
    private(set) var fired: [String: Set<Int>] = [:]

    mutating func evaluate(
        limits: [AgentProvider: AgentLimits],
        now: Date = Date(),
        thresholds: [Int] = defaultThresholds,
        calendar: Calendar = .current
    ) -> [AIUsageAlert] {
        var alerts: [AIUsageAlert] = []
        let sortedProviders = limits.keys.sorted { $0.rawValue < $1.rawValue }
        for provider in sortedProviders {
            guard let entry = limits[provider],
                  let window = entry.windows.first(where: { $0.kind == .session }) ?? entry.windows.first else {
                continue
            }
            let pct = Int(window.usedPercent.rounded())
            guard let crossed = thresholds.filter({ pct >= $0 }).max() else { continue }
            let stamp = Self.windowStamp(window: window, now: now, calendar: calendar)
            let bucketKey = "\(provider.rawValue)|\(window.id)|\(stamp)"
            var already = fired[bucketKey] ?? []
            guard !already.contains(crossed) else { continue }
            // Mark every lower threshold in the same window as satisfied so a jump from 70% → 96%
            // emits one critical alert rather than both 80% and 95%.
            for t in thresholds where pct >= t { already.insert(t) }
            fired[bucketKey] = already
            alerts.append(AIUsageAlert(
                provider: provider,
                usedPercent: min(100, max(0, pct)),
                resetsAt: window.resetsAt ?? window.estimatedResetsAt,
                severity: crossed >= 95 ? .critical : .warning
            ))
        }
        return alerts
    }

    private static func windowStamp(window: AgentLimitWindow, now: Date, calendar: Calendar) -> String {
        if let reset = window.resetsAt ?? window.estimatedResetsAt {
            return String(Int(reset.timeIntervalSince1970 / 60))
        }
        let comps = calendar.dateComponents([.year, .month, .day], from: now)
        return "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
    }
}
