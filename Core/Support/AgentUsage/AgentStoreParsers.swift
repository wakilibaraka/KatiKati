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

// MARK: - SLICE NL-1: Universal Loadout Core Engine (Multi-Agent)

enum AIProviderKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case claudeCode, codexCLI, cursor, geminiCLI, windsurf, aider, openRouter, ollama
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codexCLI: return "Codex CLI"
        case .cursor: return "Cursor"
        case .geminiCLI: return "Gemini CLI"
        case .windsurf: return "Windsurf"
        case .aider: return "Aider"
        case .openRouter: return "OpenRouter"
        case .ollama: return "Ollama"
        }
    }
    var symbol: String {
        switch self {
        case .claudeCode: return "sparkle"
        case .codexCLI: return "chevron.left.forwardslash.chevron.right"
        case .cursor: return "cursorarrow.rays"
        case .geminiCLI: return "wand.and.stars"
        case .windsurf: return "wind"
        case .aider: return "terminal"
        case .openRouter: return "network"
        case .ollama: return "cpu"
        }
    }
    var configRelativePath: String {
        switch self {
        case .claudeCode: return ".claude/settings.json"
        case .codexCLI: return ".codex/config.toml"
        case .cursor: return ".cursor/mcp.json"
        case .geminiCLI: return ".gemini/settings.json"
        case .windsurf: return ".codeium/windsurf/mcp_config.json"
        case .aider: return ".aider.conf.yml"
        case .openRouter: return ".config/openrouter/config.json"
        case .ollama: return ".ollama/config.json"
        }
    }
}

enum LoadoutItemKind: String, Codable, CaseIterable, Sendable { case mcpServer, skill, ruleFile, plugin }

enum LoadoutScope: Equatable, Codable, Sendable { case global, workspace(String) }

struct LoadoutItem: Identifiable, Equatable, Codable, Sendable {
    var id: String
    var name: String
    var kind: LoadoutItemKind
    var provider: AIProviderKind
    var scope: LoadoutScope
    var isEnabled: Bool
    var estimatedTokens: Int
}

enum LoadoutProfile: String, CaseIterable, Codable, Identifiable, Sendable {
    case allOn, leanCoding, research, offlineLocal
    var id: String { rawValue }
    var title: String {
        switch self {
        case .allOn: return "All On"
        case .leanCoding: return "Lean Coding"
        case .research: return "Research"
        case .offlineLocal: return "Offline / Local"
        }
    }
    func applies(to item: LoadoutItem) -> Bool {
        switch self {
        case .allOn: return true
        case .leanCoding: return item.kind == .ruleFile || item.kind == .skill
        case .research: return item.kind == .mcpServer || item.kind == .skill
        case .offlineLocal: return item.provider == .ollama || item.kind == .ruleFile
        }
    }
}

enum LoadoutConfigCodec {
    enum CodecError: Error { case invalidJSONObject }
    static let defaultMCPOverheadTokens = 320

    static func parseJSONServers(data: Data, provider: AIProviderKind, scope: LoadoutScope) -> [LoadoutItem] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var items: [LoadoutItem] = []
        let active = root["mcpServers"] as? [String: Any] ?? [:]
        let disabled = root["_disabled_mcpServers"] as? [String: Any] ?? [:]
        for name in active.keys.sorted() {
            items.append(LoadoutItem(id: "\(provider.rawValue)-mcp-\(name)", name: name, kind: .mcpServer,
                                     provider: provider, scope: scope, isEnabled: true, estimatedTokens: defaultMCPOverheadTokens))
        }
        for name in disabled.keys.sorted() {
            items.append(LoadoutItem(id: "\(provider.rawValue)-mcp-\(name)", name: name, kind: .mcpServer,
                                     provider: provider, scope: scope, isEnabled: false, estimatedTokens: defaultMCPOverheadTokens))
        }
        return items
    }

    static func toggleJSONServer(data: Data, name: String, enabled: Bool) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodecError.invalidJSONObject
        }
        var active = root["mcpServers"] as? [String: Any] ?? [:]
        var disabled = root["_disabled_mcpServers"] as? [String: Any] ?? [:]
        if enabled, let entry = disabled.removeValue(forKey: name) {
            active[name] = entry
        } else if !enabled, let entry = active.removeValue(forKey: name) {
            disabled[name] = entry
        }
        root["mcpServers"] = active
        if disabled.isEmpty { root.removeValue(forKey: "_disabled_mcpServers") } else { root["_disabled_mcpServers"] = disabled }
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    static func parseTOMLServers(text: String, scope: LoadoutScope) -> [LoadoutItem] {
        var items: [LoadoutItem] = []
        var current: String?
        var enabled = true
        func flush() {
            guard let name = current else { return }
            items.append(LoadoutItem(id: "codexCLI-mcp-\(name)", name: name, kind: .mcpServer,
                                     provider: .codexCLI, scope: scope, isEnabled: enabled, estimatedTokens: defaultMCPOverheadTokens))
        }
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") && line.hasSuffix("]") {
                flush(); current = nil; enabled = true
                let inner = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if inner.hasPrefix("mcp_servers.") {
                    current = String(inner.dropFirst("mcp_servers.".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                }
            } else if current != nil, line.hasPrefix("enabled"), let eq = line.firstIndex(of: "=") {
                let val = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                enabled = (val != "false")
            }
        }
        flush()
        return items
    }

    static func toggleTOMLServer(text: String, name: String, enabled: Bool) -> String {
        var lines = text.components(separatedBy: "\n")
        var inTarget = false
        var headerIndex: Int?
        var replaced = false
        for i in lines.indices {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                if inTarget { break }
                let inner = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                let cleaned = inner.hasPrefix("mcp_servers.") ? String(inner.dropFirst("mcp_servers.".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\"' ")) : ""
                if cleaned == name { inTarget = true; headerIndex = i }
            } else if inTarget && trimmed.hasPrefix("enabled") && trimmed.contains("=") {
                lines[i] = "enabled = \(enabled ? "true" : "false")"
                replaced = true
                break
            }
        }
        if !replaced, let h = headerIndex {
            lines.insert("enabled = \(enabled ? "true" : "false")", at: h + 1)
        }
        return lines.joined(separator: "\n")
    }

    static func estimateSkillTokens(markdown: String) -> Int {
        var desc = ""
        if markdown.hasPrefix("---") {
            for line in markdown.components(separatedBy: .newlines).dropFirst() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed == "---" { break }
                if trimmed.lowercased().hasPrefix("description:") {
                    desc = trimmed.dropFirst("description:".count).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                }
            }
        }
        let source = desc.isEmpty ? markdown : desc
        return max(1, min(source.count, 1536) / 4)
    }

    static func contextOverhead(items: [LoadoutItem], contextWindow: Int = 200_000) -> (totalTokens: Int, percent: Double, isBloated: Bool) {
        let total = items.filter(\.isEnabled).reduce(0) { $0 + max(0, $1.estimatedTokens) }
        let pct = contextWindow > 0 ? min(100.0, Double(total) / Double(contextWindow) * 100.0) : 0
        return (total, pct, total > 20_000)
    }
}
