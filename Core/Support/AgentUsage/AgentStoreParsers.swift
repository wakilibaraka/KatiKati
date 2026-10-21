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
        guard let usage = tokenUsage(in: json) else { return nil }
        let tokens = AgentTokens(
            input: int(usage, keys: ["input_tokens", "inputTokens"]),
            cacheWrite: int(usage, keys: ["cache_creation_input_tokens", "cacheCreationTokens", "cache_write_input_tokens"]),
            cacheRead: int(usage, keys: ["cache_read_input_tokens", "cached_tokens", "cached_input_tokens", "cacheReadTokens"]),
            output: int(usage, keys: ["output_tokens", "outputTokens"]),
            reasoning: int(usage, keys: ["reasoning_tokens", "reasoningTokens", "reasoning_output_tokens"])
        )
        guard tokens.total > 0 else { return nil }
        return (tokens, firstModel(in: json))
    }

    /// A `token_count` event nests the session's cumulative `total_token_usage` beside the turn's
    /// `last_token_usage`. Callers sum lines, so the turn value is the one to count; the total is
    /// only a fallback for an envelope without a per-turn object. Picking by dictionary order (as
    /// this used to) meant the same event could read as one turn or as the whole session.
    /// shortcut: a rate-limit-only re-emit repeats the previous last_token_usage and counts that
    /// turn twice; upgrade when Codex stops advancing total_token_usage on real turns.
    private static func tokenUsage(in node: Any) -> [String: Any]? {
        if let dict = node as? [String: Any] {
            if let last = dict["last_token_usage"] as? [String: Any] { return last }
            if let total = dict["total_token_usage"] as? [String: Any] { return total }
            let keys = Set(dict.keys.map { $0.lowercased() })
            if keys.contains("input_tokens") || keys.contains("inputtokens")
                || keys.contains("output_tokens") || keys.contains("outputtokens") {
                return dict
            }
            for value in dict.values {
                if let found = tokenUsage(in: value) { return found }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let found = tokenUsage(in: value) { return found }
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
