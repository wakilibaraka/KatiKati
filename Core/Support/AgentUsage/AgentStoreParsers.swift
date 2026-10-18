import Foundation

// Phase 48c — parsers for every local AI store that records tokens or cost.
// Pure: store rows in, day totals out. SQLite and file enumeration live in
// AgentUsageService (background queue, read-only, usage tables only); this file
// never touches disk, copies nothing, and never opens the credentials those
// directories also hold (opencode auth.json, gemini oauth tokens).

/// One usage-accounted row from a tool's own store, already filtered to today.
struct AgentStoreRow: Equatable, Sendable {
    var tokens: AgentTokens
    var storeCost: Double
    var model: String
    var project: String
    var lastActivity: Date
}

enum AgentOpenCodeParser {
    /// session/session_v2 time columns are unix MILLISECONDS
    /// (witnessed 2026-10-17: 1791963406090 on a recent session row).
    static func isToday(millis: Int64, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let date = Date(timeIntervalSince1970: Double(millis) / 1000.0)
        return calendar.isDate(date, inSameDayAs: now)
    }

    /// The store keeps model as a JSON blob ({"id":"…","providerID":"…"}) or a plain id.
    /// The id is the tool's own label — shown as read, never mapped to a price name.
    static func modelName(from raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if let data = raw.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let id = json["id"] as? String, !id.isEmpty {
            return id
        }
        return raw
    }
}

enum AgentCopilotParser {
    /// The stores Copilot keeps here (sessions/turns: ids, cwd, message text) carry no
    /// token or cost columns, so there is nothing to count. Only a schema that actually
    /// records accounting contributes — a store with no accounting yields nothing.
    static func hasAccounting(columns: [String]) -> Bool {
        let names = Set(columns.map { $0.lowercased() })
        return names.contains("input_tokens") || names.contains("tokens_input")
            || names.contains("total_tokens") || names.contains("cost")
    }
}

enum AgentCodexParser {
    /// Tolerant rollout-line scan over ~/.codex/sessions (and archived_sessions):
    /// Codex persists token_count events whose exact envelope evolves, so any nested
    /// object carrying input/output token keys counts. Cost is never in the log —
    /// the service prices it, marked estimated.
    static func parseJSONLLine(_ line: String) -> (tokens: AgentTokens, model: String?)? {
        guard line.contains("token") else { return nil }
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        guard let usage = firstTokenDict(in: json) else { return nil }
        let tokens = AgentTokens(
            input: int(usage, keys: ["input_tokens", "inputTokens"]),
            cacheWrite: int(usage, keys: ["cache_creation_input_tokens", "cacheCreationTokens"]),
            cacheRead: int(usage, keys: ["cache_read_input_tokens", "cached_tokens", "cacheReadTokens"]),
            output: int(usage, keys: ["output_tokens", "outputTokens"]),
            reasoning: int(usage, keys: ["reasoning_tokens", "reasoningTokens"])
        )
        guard tokens.total > 0 else { return nil }
        return (tokens, firstModel(in: json))
    }

    private static func firstTokenDict(in node: Any) -> [String: Any]? {
        if let dict = node as? [String: Any] {
            let keys = Set(dict.keys.map { $0.lowercased() })
            if keys.contains("input_tokens") || keys.contains("inputtokens")
                || keys.contains("output_tokens") || keys.contains("outputtokens") {
                return dict
            }
            for value in dict.values {
                if let found = firstTokenDict(in: value) { return found }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let found = firstTokenDict(in: value) { return found }
            }
        }
        return nil
    }

    private static func firstModel(in node: Any) -> String? {
        if let dict = node as? [String: Any] {
            if let model = dict["model"] as? String, !model.isEmpty { return model }
            for value in dict.values {
                if let found = firstModel(in: value) { return found }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let found = firstModel(in: value) { return found }
            }
        }
        return nil
    }

    private static func int(_ dict: [String: Any], keys: [String]) -> Int {
        for key in keys {
            if let n = dict[key] as? NSNumber { return n.intValue }
        }
        return 0
    }
}
