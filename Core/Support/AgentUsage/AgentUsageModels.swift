import Foundation

// Phase 33d — AgentUsageModels: Pure data models for local AI agent tracking
// (Claude Code, Codex, OpenCode, GitHub Copilot). Zero telemetry, local log inspection only. Dual-compiled.

/// Supported coding agent providers.
enum AgentProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case claude = "claude"
    case codex = "codex"
    case opencode = "opencode"
    case copilot = "copilot"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .opencode: return "OpenCode"
        case .copilot: return "GitHub Copilot"
        }
    }

    var symbol: String {
        switch self {
        case .claude: return "sparkle"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .opencode: return "terminal"
        case .copilot: return "infinity"
        }
    }
}

/// Token metrics for a prompt turn or aggregated session.
struct AgentTokens: Equatable, Sendable, Codable {
    var input: Int = 0
    var cacheWrite: Int = 0
    var cacheRead: Int = 0
    var output: Int = 0
    var reasoning: Int = 0

    var total: Int { input + cacheWrite + cacheRead + output }
    var prompt: Int { input + cacheWrite + cacheRead }

    var cacheHitRate: Double {
        prompt > 0 ? Double(cacheRead) / Double(prompt) : 0.0
    }

    static func += (lhs: inout AgentTokens, rhs: AgentTokens) {
        lhs.input += rhs.input
        lhs.cacheWrite += rhs.cacheWrite
        lhs.cacheRead += rhs.cacheRead
        lhs.output += rhs.output
        lhs.reasoning += rhs.reasoning
    }

    func merged(with other: AgentTokens) -> AgentTokens {
        AgentTokens(
            input: max(input, other.input),
            cacheWrite: max(cacheWrite, other.cacheWrite),
            cacheRead: max(cacheRead, other.cacheRead),
            output: max(output, other.output),
            reasoning: max(reasoning, other.reasoning)
        )
    }
}

/// One model response record.
struct AgentUsageRecord: Equatable, Sendable, Identifiable {
    var id: String { "\(provider.rawValue)-\(session)-\(date.timeIntervalSince1970)" }
    let provider: AgentProvider
    let date: Date
    let model: String
    let project: String
    let session: String
    let requests: Int
    var tokens: AgentTokens
    var cost: Double
    var savings: Double

    init(
        provider: AgentProvider,
        date: Date,
        model: String,
        project: String,
        session: String,
        requests: Int = 1,
        tokens: AgentTokens,
        cost: Double = 0.0,
        savings: Double = 0.0
    ) {
        self.provider = provider
        self.date = date
        self.model = model
        self.project = project
        self.session = session
        self.requests = requests
        self.tokens = tokens
        self.cost = cost
        self.savings = savings
    }
}

/// Plan usage allowance window (5h session reset or 7d weekly).
struct AgentLimitWindow: Equatable, Identifiable, Sendable {
    enum Kind: String, Sendable {
        case session
        case weekly
        case other
    }

    let id: String
    let kind: Kind
    let minutes: Int?
    let scope: String?
    let usedPercent: Double
    let resetsAt: Date?
    var estimatedResetsAt: Date? = nil

    var usedFraction: Double { min(1.0, max(0.0, usedPercent / 100.0)) }
    var remainingFraction: Double { 1.0 - usedFraction }
}

/// Limits reported by provider logs or local apps.
struct AgentLimits: Equatable, Sendable {
    let provider: AgentProvider
    var windows: [AgentLimitWindow]
    let observedAt: Date
}

/// Real-time live turn being generated or executed.
struct AgentLiveTurn: Equatable, Identifiable, Sendable {
    let id: String
    let provider: AgentProvider
    let model: String
    let project: String
    let started: Date
    var lastActivity: Date
    var tokens: AgentTokens
    var cost: Double
    var isActive: Bool
    var activeTool: AgentToolCall? = nil
}

/// Active tool invocation by an agent (e.g., Read, Edit, Bash).
struct AgentToolCall: Equatable, Sendable, Codable {
    var toolName: String
    var targetPath: String?
    var addedLines: Int = 0
    var deletedLines: Int = 0

    init(toolName: String, targetPath: String? = nil, addedLines: Int = 0, deletedLines: Int = 0) {
        self.toolName = toolName
        self.targetPath = targetPath
        self.addedLines = addedLines
        self.deletedLines = deletedLines
    }

    var summary: String {
        var parts: [String] = [toolName]
        if let path = targetPath, !path.isEmpty {
            let name = (path as NSString).lastPathComponent
            parts.append(name)
        }
        if addedLines > 0 || deletedLines > 0 {
            parts.append("+\(addedLines)/-\(deletedLines)")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - AI Stats Receipt (Slice D-AgentLive)

struct AIReceiptItem: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let value: String
    let subtitle: String?
}

struct AIStatsReceipt: Equatable, Sendable {
    let totalActiveSeconds: TimeInterval
    let totalCostUSD: Double
    let totalTokens: Int
    let estimatedWords: Int
    let linesAdded: Int
    let linesDeleted: Int
    let streakDays: Int
    let items: [AIReceiptItem]

    var formattedDuration: String {
        let hours = Int(totalActiveSeconds) / 3600
        let minutes = (Int(totalActiveSeconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    var formattedCost: String {
        String(format: "$%.2f", totalCostUSD)
    }

    var formattedNetLines: String {
        "+\(linesAdded) / -\(linesDeleted)"
    }
}

enum AIStatsReceiptCalculator {
    static func calculate(
        tokens: AgentTokens,
        costUSD: Double,
        activeDuration: TimeInterval,
        linesAdded: Int,
        linesDeleted: Int,
        streakDays: Int
    ) -> AIStatsReceipt {
        let words = Int(Double(tokens.output) * 0.75)

        var items: [AIReceiptItem] = []
        let hours = activeDuration / 3600.0
        items.append(AIReceiptItem(id: "time", title: "Active Time", value: String(format: "%.1f hrs", hours), subtitle: "Coding & planning"))
        items.append(AIReceiptItem(id: "cost", title: "API Cost Equivalent", value: String(format: "$%.2f", costUSD), subtitle: "At public tier rates"))
        items.append(AIReceiptItem(id: "words", title: "Words Generated", value: "\(words)", subtitle: "Code & markdown tokens"))
        items.append(AIReceiptItem(id: "diff", title: "Line Changes", value: "+\(linesAdded)/-\(linesDeleted)", subtitle: "Net code diffs"))
        items.append(AIReceiptItem(id: "streak", title: "AI Streak", value: "\(streakDays) days", subtitle: "Consecutive coding days"))

        return AIStatsReceipt(
            totalActiveSeconds: activeDuration,
            totalCostUSD: costUSD,
            totalTokens: tokens.total,
            estimatedWords: words,
            linesAdded: linesAdded,
            linesDeleted: linesDeleted,
            streakDays: streakDays,
            items: items
        )
    }
}

/// One provider's measured today-total. An absent key means nothing was measured —
/// the page draws nothing for it, never a zero standing in for a reading.
struct AgentProviderDay: Equatable, Sendable {
    var tokens: AgentTokens = AgentTokens()
    var cost: Double = 0.0
    /// True when the number is the store's own cost column, false when priced here.
    var costIsStoreReported: Bool = false
}

/// Readout snapshot consumed by Notch Bento cards and closed wings.
struct AgentUsageSnapshot: Equatable, Sendable {
    var todayTokens: AgentTokens = AgentTokens()
    var todayCost: Double = 0.0
    var todaySavings: Double = 0.0
    var activeDuration: TimeInterval = 0
    var linesAdded: Int = 0
    var linesDeleted: Int = 0
    var streakDays: Int = 0
    var activeTurn: AgentLiveTurn? = nil
    var limits: [AgentProvider: AgentLimits] = [:]
    var recentTurns: [AgentLiveTurn] = []
    var weeklyHeatmap: [Double] = Array(repeating: 0.0, count: 7)
    /// Providers whose own store was opened and has accounting (tokens or cost),
    /// whether or not it held rows today. The page names exactly these.
    var sourcesRead: [AgentProvider] = []
    /// Today's per-provider totals, only for providers with rows.
    var providerToday: [AgentProvider: AgentProviderDay] = [:]

    /// "Claude · OpenCode" in provider order; empty when nothing was read.
    var sourceNames: String {
        sourcesRead.map { $0.displayName }.joined(separator: " · ")
    }

    /// "Claude estimated · OpenCode reported" for counted providers only.
    var costBasisLine: String {
        AgentProvider.allCases.compactMap { provider in
            guard let day = providerToday[provider] else { return nil }
            return "\(provider.displayName) \(day.costIsStoreReported ? "reported" : "estimated")"
        }.joined(separator: " · ")
    }

    /// Most recent measured model across turns — the idle title. Nil when nothing measured.
    var lastMeasuredModel: String? {
        recentTurns.sorted(by: { $0.lastActivity > $1.lastActivity }).first?.model
    }

    /// Formatted cost string, e.g. "$1.42"
    var formattedTodayCost: String {
        String(format: "$%.2f", todayCost)
    }

    /// Formatted token count, e.g. "142.5k"
    var formattedTodayTokens: String {
        let count = todayTokens.total
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fk", Double(count) / 1_000.0)
        } else {
            return "\(count)"
        }
    }

}

enum AgentUsageMetrics {
    static func activeDuration(intervals: [(start: Date, end: Date)], maximumGap: TimeInterval = 300) -> TimeInterval {
        let normalized = intervals.compactMap { interval -> (Date, Date)? in
            guard interval.end > interval.start else { return nil }
            return (interval.start, min(interval.end, interval.start.addingTimeInterval(maximumGap)))
        }.sorted { $0.0 < $1.0 }

        var total: TimeInterval = 0
        var current: (Date, Date)?
        for interval in normalized {
            guard let existing = current else {
                current = interval
                continue
            }
            if interval.0 <= existing.1 {
                current = (existing.0, max(existing.1, interval.1))
            } else {
                total += existing.1.timeIntervalSince(existing.0)
                current = interval
            }
        }
        if let current { total += current.1.timeIntervalSince(current.0) }
        return total
    }

    static func heatmap(dailyCosts: [String: Double], endingAt end: Date, calendar: Calendar) -> [Double] {
        (0..<7).reversed().map { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: end) else { return 0 }
            return dailyCosts[ScreenTimeLedger.dayKey(date, calendar: calendar)] ?? 0
        }
    }

    static func streakDays(dailyCosts: [String: Double], endingAt end: Date, calendar: Calendar) -> Int {
        var streak = 0
        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: end) else { break }
            guard (dailyCosts[ScreenTimeLedger.dayKey(date, calendar: calendar)] ?? 0) > 0 else { break }
            streak += 1
        }
        return streak
    }

    static func streakDays(activeDays: Set<String>, endingAt end: Date, calendar: Calendar) -> Int {
        var streak = 0
        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: end) else { break }
            guard activeDays.contains(ScreenTimeLedger.dayKey(date, calendar: calendar)) else { break }
            streak += 1
        }
        return streak
    }
}

/// Phase 52d: Daily spend budget presets for the Notch AI page ("Loadout-style" budget caps).
enum AgentBudgetPreset: String, CaseIterable, Sendable {
    static let key = "com.katikati.agent.budgetPreset"

    case off = "off"
    case light5 = "light5"
    case standard15 = "standard15"
    case heavy50 = "heavy50"

    var dailyCapUSD: Double? {
        switch self {
        case .off: return nil
        case .light5: return 5.0
        case .standard15: return 15.0
        case .heavy50: return 50.0
        }
    }

    var badgeTitle: String {
        switch self {
        case .off: return "Cap: Off"
        case .light5: return "Cap: $5/d"
        case .standard15: return "Cap: $15/d"
        case .heavy50: return "Cap: $50/d"
        }
    }

    var next: AgentBudgetPreset {
        let all = Self.allCases
        guard let idx = all.firstIndex(of: self) else { return .off }
        return all[(idx + 1) % all.count]
    }

    func usedFraction(todayCost: Double) -> Double? {
        guard let cap = dailyCapUSD, cap > 0 else { return nil }
        return min(1.0, max(0.0, todayCost / cap))
    }
}

// MARK: - Lumabar Dual-Bar AI Limit Tile (Slice 4.4)

struct AILimitBarTileSummary: Equatable, Sendable {
    let providerName: String // "Claude", "ChatGPT", "Gemini", "Cursor", "OpenCode"
    let sessionPercent: Int // e.g. 74%
    let sessionResetCountdown: String // e.g. "1h 39m"
    let weeklyPercent: Int // e.g. 45%
    let weeklyResetDay: String // e.g. "Fri"
    let tokenFormatted: String // e.g. "Opus 4.5 • 38.2M"

    static func formatTokens(_ totalTokens: Int, model: String = "Opus 4.5") -> String {
        let millions = Double(totalTokens) / 1_000_000.0
        if millions >= 0.1 {
            return String(format: "%@ • %.1fM", model, millions)
        } else {
            let thousands = Double(totalTokens) / 1_000.0
            return String(format: "%@ • %.0fK", model, thousands)
        }
    }

    static func formatCountdown(seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "0m" }
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(max(1, minutes))m"
        }
    }
}

// MARK: - MB-9: the menu bar's agent summary

/// Pure strings for the Creative Hub's opt-in `Agents` card. The card is narrow (344 pt), so the
/// summary is one line: today's spend, then how much of the loadout is on. No locale grouping — this
/// is a status pill, not an accounting table.
enum AgentLoadoutSummary {
    static func compactCost(_ cost: Double) -> String {
        guard cost.isFinite, cost > 0 else { return "$0.00" }
        if cost < 0.01 { return "<$0.01" }
        return String(format: "$%.2f", cost)
    }

    static func enabledCount(_ items: [LoadoutItem]) -> Int { items.filter(\.isEnabled).count }

    static func badge(cost: Double, enabled: Int, total: Int) -> String {
        "\(compactCost(cost)) · \(max(0, enabled))/\(max(0, total))"
    }

    /// The profile picker's next value, wrapping. Pure so the control cannot land on an
    /// index that does not exist when a profile is removed in a later release.
    static func nextProfile(after profile: LoadoutProfile) -> LoadoutProfile {
        let all = LoadoutProfile.allCases
        guard let index = all.firstIndex(of: profile), !all.isEmpty else { return .allOn }
        return all[(index + 1) % all.count]
    }
}
