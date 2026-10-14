import Foundation

// Phase 33d — AgentPricing: Built-in official API price rates per million tokens and
// friendly model name display formatter. Dual-compiled.

struct AgentRate: Equatable, Sendable {
    let input: Double       // $ per 1M input tokens
    let output: Double      // $ per 1M output tokens
    let cacheRead: Double   // $ per 1M cache read tokens
    let cacheWrite: Double  // $ per 1M cache write tokens
}

enum AgentPricing {
    // Official API list rates per 1,000,000 tokens
    static let rates: [String: AgentRate] = [
        "claude-3-7-sonnet": AgentRate(input: 3.00, output: 15.00, cacheRead: 0.30, cacheWrite: 3.75),
        "claude-3-5-sonnet": AgentRate(input: 3.00, output: 15.00, cacheRead: 0.30, cacheWrite: 3.75),
        "claude-3-5-haiku": AgentRate(input: 0.80, output: 4.00, cacheRead: 0.08, cacheWrite: 1.00),
        "claude-3-opus": AgentRate(input: 15.00, output: 75.00, cacheRead: 1.50, cacheWrite: 18.75),
        "gpt-4o": AgentRate(input: 2.50, output: 10.00, cacheRead: 1.25, cacheWrite: 2.50),
        "gpt-4o-mini": AgentRate(input: 0.15, output: 0.60, cacheRead: 0.075, cacheWrite: 0.15),
        "o1": AgentRate(input: 15.00, output: 60.00, cacheRead: 7.50, cacheWrite: 15.00),
        "o3-mini": AgentRate(input: 1.10, output: 4.40, cacheRead: 0.55, cacheWrite: 1.10)
    ]

    static let defaultClaudeRate = AgentRate(input: 3.00, output: 15.00, cacheRead: 0.30, cacheWrite: 3.75)
    static let defaultCodexRate = AgentRate(input: 2.50, output: 10.00, cacheRead: 1.25, cacheWrite: 2.50)

    static func rate(for model: String) -> AgentRate {
        let norm = normalized(model)
        for (key, val) in rates {
            if norm.contains(key) {
                return val
            }
        }
        return norm.contains("claude") ? defaultClaudeRate : defaultCodexRate
    }

    static func cost(tokens: AgentTokens, model: String) -> (cost: Double, savings: Double) {
        let r = rate(for: model)
        let cost = (Double(tokens.input) * r.input
                  + Double(tokens.cacheWrite) * r.cacheWrite
                  + Double(tokens.cacheRead) * r.cacheRead
                  + Double(tokens.output) * r.output) / 1_000_000.0

        let savings = Double(tokens.cacheRead) * max(0.0, r.input - r.cacheRead) / 1_000_000.0
        return (cost, savings)
    }

    static func normalized(_ model: String) -> String {
        model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func displayName(_ model: String) -> String {
        let norm = normalized(model)
        if norm.contains("3-7-sonnet") || norm.contains("3.7-sonnet") {
            return "Claude 3.7 Sonnet"
        } else if norm.contains("3-5-sonnet") || norm.contains("3.5-sonnet") {
            return "Claude 3.5 Sonnet"
        } else if norm.contains("3-5-haiku") || norm.contains("3.5-haiku") {
            return "Claude 3.5 Haiku"
        } else if norm.contains("opus") {
            return "Claude 3 Opus"
        } else if norm.contains("gpt-4o-mini") {
            return "GPT-4o mini"
        } else if norm.contains("gpt-4o") {
            return "GPT-4o"
        } else if norm.contains("o3-mini") {
            return "o3-mini"
        } else if norm.contains("o1") {
            return "o1"
        }
        return model.isEmpty ? "Agent" : model
    }
}
