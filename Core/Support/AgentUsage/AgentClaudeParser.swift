import Foundation

// Phase 33d — AgentClaudeParser: Pure parser for Claude Desktop plan limits
// (plan-usage-history.json) and Claude Code local JSONL turn transcripts. Dual-compiled.

enum AgentClaudeParser {
    // MARK: - Plan Usage History Parser

    struct AppSample: Equatable, Sendable {
        let date: Date
        let organization: String?
        let sessionUsedPercent: Double?
        let weeklyUsedPercent: Double?
    }

    static func parsePlanUsageHistory(data: Data, now: Date = Date()) -> AgentLimits? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let samples = json["samples"] as? [[String: Any]] else {
            return nil
        }

        var parsedSamples: [AppSample] = []
        for s in samples {
            guard let t = (s["t"] as? NSNumber)?.doubleValue else { continue }
            let date = Date(timeIntervalSince1970: t / 1000.0)
            let org = s["org"] as? String
            let u = s["u"] as? [String: Any] ?? [:]
            let fh = (u["fh"] as? NSNumber)?.doubleValue
            let sd = (u["sd"] as? NSNumber)?.doubleValue
            parsedSamples.append(AppSample(
                date: date,
                organization: org,
                sessionUsedPercent: fh,
                weeklyUsedPercent: sd
            ))
        }

        guard let latest = parsedSamples.last else { return nil }

        var windows: [AgentLimitWindow] = []

        if let fh = latest.sessionUsedPercent {
            // 5-hour rolling session window (300 minutes)
            let sessionResetsAt = latest.date.addingTimeInterval(300 * 60)
            windows.append(AgentLimitWindow(
                id: "claude.session.5h",
                kind: .session,
                minutes: 300,
                scope: nil,
                usedPercent: fh,
                resetsAt: sessionResetsAt > now ? sessionResetsAt : nil,
                estimatedResetsAt: sessionResetsAt
            ))
        }

        if let sd = latest.weeklyUsedPercent {
            // 7-day weekly window (10080 minutes)
            let weeklyResetsAt = latest.date.addingTimeInterval(7 * 86_400)
            windows.append(AgentLimitWindow(
                id: "claude.weekly.7d",
                kind: .weekly,
                minutes: 10_080,
                scope: nil,
                usedPercent: sd,
                resetsAt: weeklyResetsAt > now ? weeklyResetsAt : nil,
                estimatedResetsAt: weeklyResetsAt
            ))
        }

        guard !windows.isEmpty else { return nil }

        return AgentLimits(
            provider: .claude,
            windows: windows,
            observedAt: latest.date
        )
    }

    // MARK: - JSONL Line Token Extractor

    static func parseJSONLLine(_ line: String) -> (tokens: AgentTokens, model: String?, timestamp: Date?)? {
        guard line.contains("\"usage\"") || line.contains("\"input_tokens\"") else { return nil }
        guard let data = line.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }

        var model = json["model"] as? String
        var timestamp: Date? = nil
        if let ts = json["timestamp"] as? String {
            timestamp = ISO8601DateFormatter().date(from: ts)
        }

        // Check if usage is embedded directly or inside message
        var usageDict: [String: Any]? = json["usage"] as? [String: Any]
        if usageDict == nil, let msg = json["message"] as? [String: Any] {
            usageDict = msg["usage"] as? [String: Any]
            if model == nil { model = msg["model"] as? String }
        }

        guard let usage = usageDict else { return nil }

        let input = (usage["input_tokens"] as? NSNumber)?.intValue ?? 0
        let output = (usage["output_tokens"] as? NSNumber)?.intValue ?? 0
        let cacheRead = (usage["cache_read_input_tokens"] as? NSNumber)?.intValue ?? 0
        let cacheWrite = (usage["cache_creation_input_tokens"] as? NSNumber)?.intValue ?? 0

        let tokens = AgentTokens(
            input: input,
            cacheWrite: cacheWrite,
            cacheRead: cacheRead,
            output: output,
            reasoning: 0
        )

        return (tokens, model, timestamp)
    }
}
