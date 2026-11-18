import Foundation

// Phase 52c — reads the hook log: one `<epoch> <event>` line per turn boundary. Tolerant by design:
// the file is appended to by a shell command, so a half-written or junk line must never hide the
// newest good one. Dual-compiled.

enum ClaudeHookStatus {
    /// `true` while the newest event says working, `false` once it says stopped. `nil` means "no
    /// override": no usable line, an unknown event, or an event older than `window` (the transcript
    /// mtime is then the only signal, as before this slice).
    static func workingOverride(log: String, now: Date, window: TimeInterval = 300) -> Bool? {
        guard let newest = newestEvent(log: log) else { return nil }
        guard now.timeIntervalSince(newest.date) <= window else { return nil }
        switch newest.event {
        case ClaudeHookEvent.working.rawValue: return true
        case ClaudeHookEvent.idle.rawValue: return false
        default: return nil
        }
    }

    static func newestEvent(log: String) -> (event: String, date: Date)? {
        for line in log.split(whereSeparator: \.isNewline).reversed() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2, let epoch = Double(parts[0]) else { continue }
            return (String(parts[1]), Date(timeIntervalSince1970: epoch))
        }
        return nil
    }
}

// MARK: - SLICE NL-2: Multi-Agent Live Session, Sub-Agent Swarm & Quota Models

struct SubAgentTask: Identifiable, Equatable, Codable, Sendable {
    var id: String
    var title: String
    var isCompleted: Bool = false
    var failed: Bool = false
}

enum AgentSessionState: Equatable, Sendable {
    case idle
    case thinking
    case callingTool(name: String, target: String?)
    case awaitingPermission(promptId: String, tool: String, command: String, isReadOnly: Bool)
    case completed(summary: String, duration: TimeInterval, changedLines: Int)
    case error(message: String)
    case stuck(idleSeconds: Int)
}

enum AgentLifecycleEvent: Equatable, Sendable {
    case turnStarted(now: Date)
    case callingTool(name: String, target: String?, addedLines: Int, deletedLines: Int, now: Date)
    case toolFinished(failed: Bool, now: Date)
    case subagentStarted(id: String, title: String, now: Date)
    case subagentStopped(id: String, failed: Bool, now: Date)
    case awaitingPermission(promptId: String, tool: String, command: String, isReadOnly: Bool, now: Date)
    case turnCompleted(summary: String, now: Date)
    case failed(message: String, now: Date)
}

struct AgentLiveSession: Identifiable, Equatable, Sendable {
    var id: String { sessionId }
    var provider: AIProviderKind
    var sessionId: String
    var workspaceName: String
    var startedAt: Date
    var state: AgentSessionState = .idle
    var subagents: [SubAgentTask] = []
    var addedLines: Int = 0
    var deletedLines: Int = 0
    var lastUpdated: Date

    mutating func apply(_ event: AgentLifecycleEvent) {
        switch event {
        case .turnStarted(let now):
            startedAt = now; lastUpdated = now; state = .thinking
        case .callingTool(let name, let target, let add, let del, let now):
            lastUpdated = now; addedLines += max(0, add); deletedLines += max(0, del)
            state = .callingTool(name: name, target: target)
        case .toolFinished(let failed, let now):
            lastUpdated = now
            state = failed ? .error(message: "Tool execution failed") : .thinking
        case .subagentStarted(let sid, let title, let now):
            lastUpdated = now
            if let i = subagents.firstIndex(where: { $0.id == sid }) {
                subagents[i].title = title; subagents[i].isCompleted = false; subagents[i].failed = false
            } else {
                subagents.append(SubAgentTask(id: sid, title: title))
            }
        case .subagentStopped(let sid, let failed, let now):
            lastUpdated = now
            if let i = subagents.firstIndex(where: { $0.id == sid }) {
                subagents[i].isCompleted = true; subagents[i].failed = failed
            }
        case .awaitingPermission(let pid, let tool, let cmd, let readOnly, let now):
            lastUpdated = now
            state = .awaitingPermission(promptId: pid, tool: tool, command: cmd, isReadOnly: readOnly)
        case .turnCompleted(let summary, let now):
            lastUpdated = now
            state = .completed(summary: summary, duration: max(0, now.timeIntervalSince(startedAt)), changedLines: addedLines + deletedLines)
        case .failed(let msg, let now):
            lastUpdated = now; state = .error(message: msg)
        }
    }

    mutating func checkWatchdog(now: Date, stuckThreshold: TimeInterval = 180) {
        switch state {
        case .thinking, .callingTool:
            let elapsed = now.timeIntervalSince(lastUpdated)
            if elapsed >= stuckThreshold { state = .stuck(idleSeconds: Int(elapsed)) }
        default: break
        }
    }
}

struct AgentQuotaSnapshot: Equatable, Sendable {
    var provider: AIProviderKind
    var fiveHourUsedPercent: Double?
    var dailyCostUSD: Double
    var tokensPerSecond: Double?
    var localVRAMMB: Int?
}
