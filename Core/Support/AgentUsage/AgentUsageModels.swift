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
}

/// Readout snapshot consumed by Notch Bento cards and closed wings.
struct AgentUsageSnapshot: Equatable, Sendable {
    var todayTokens: AgentTokens = AgentTokens()
    var todayCost: Double = 0.0
    var todaySavings: Double = 0.0
    var activeTurn: AgentLiveTurn? = nil
    var limits: [AgentProvider: AgentLimits] = [:]
    var recentTurns: [AgentLiveTurn] = []
    var weeklyHeatmap: [Double] = Array(repeating: 0.0, count: 7)

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
