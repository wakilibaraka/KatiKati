import Foundation

// Port plan #5 (2026-10-27) — approve or deny a Claude Code tool request from KatiKati instead of the
// terminal. Claude's `PermissionRequest` hook runs `katikati-approve`, which drops the hook's JSON in
// `approvals/pending/`, waits for `approvals/decided/<id>` and prints Claude's decision. If KatiKati is not
// running (no fresh `approvals/alive`) or nobody answers in time, it prints nothing and Claude asks in
// the terminal as usual: a missed card never blocks Claude. Dual-compiled: pure parsing and text.

enum AgentApprovalDecision: String, Equatable, Sendable {
    case allow, deny
}

struct AgentApprovalRequest: Equatable, Identifiable, Sendable {
    /// The request file's name without `.json`: `<epoch>-<pid>`.
    var id: String
    var toolName: String
    /// One line, at most `AgentApproval.summaryLimit` characters: what Claude wants to do.
    var summary: String
    /// The fuller text behind the summary (a long command), capped; nil when the summary says it all.
    var detail: String?
    var cwd: String?
    var created: Date
    var provider: AIProviderKind = .claudeCode
}

enum AgentApproval {
    static let summaryLimit = 160
    static let detailLimit = 800
    /// A request older than this was abandoned by the script (it gives up first); never show it.
    static let requestLifetime: TimeInterval = 90
    /// The app touches `alive` this often; the script treats a file older than `aliveFreshness` as "app not running".
    static let heartbeatInterval: TimeInterval = 5
    static let aliveFreshness: TimeInterval = 15

    static let approvalsRelativePath = "Library/Application Support/KatiKati/approvals"

    static func directory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(approvalsRelativePath, isDirectory: true)
    }

    // MARK: - Parsing

    /// `data` is the JSON Claude passes to the hook on stdin. Nil when it is not an object with a `tool_name`.
    static func parse(id: String, data: Data, created: Date) -> AgentApprovalRequest? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tool = object["tool_name"] as? String, !tool.isEmpty else { return nil }
        let input = object["tool_input"] as? [String: Any] ?? [:]
        let full = primaryText(tool: tool, input: input)
        let oneLine = collapse(full)
        let rawProvider = (object["provider"] as? String ?? object["agent"] as? String ?? "").lowercased()
        let provider = resolveProvider(rawProvider)
        return AgentApprovalRequest(
            id: id, toolName: tool,
            summary: truncate(oneLine, to: summaryLimit),
            detail: full.count > summaryLimit || full.contains("\n") ? truncate(full.trimmingCharacters(in: .whitespacesAndNewlines), to: detailLimit) : nil,
            cwd: object["cwd"] as? String,
            created: created,
            provider: provider)
    }

    private static func resolveProvider(_ raw: String) -> AIProviderKind {
        if raw.contains("codex") { return .codexCLI }
        if raw.contains("cursor") { return .cursor }
        if raw.contains("gemini") { return .geminiCLI }
        if raw.contains("windsurf") { return .windsurf }
        if raw.contains("aider") { return .aider }
        if raw.contains("ollama") { return .ollama }
        if raw.contains("openrouter") { return .openRouter }
        return .claudeCode
    }

    /// The most telling field of the tool's input. Unknown tools fall back to their first text value.
    private static func primaryText(tool: String, input: [String: Any]) -> String {
        func string(_ key: String) -> String? { (input[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        switch tool {
        case "Bash": return string("command") ?? tool
        case "Edit", "MultiEdit", "Write", "Read", "NotebookEdit": return string("file_path") ?? string("notebook_path") ?? tool
        case "WebFetch": return string("url") ?? tool
        case "WebSearch": return string("query") ?? tool
        case "Task": return string("description") ?? string("prompt") ?? tool
        case "Glob", "Grep": return string("pattern") ?? tool
        default:
            for key in input.keys.sorted() { if let text = string(key) { return text } }
            return tool
        }
    }

    private static func collapse(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func truncate(_ text: String, to limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
    }

    // MARK: - Files

    /// `<epoch>-<pid>` → its epoch, so the app can drop stale files without reading them.
    static func created(fromID id: String) -> Date? {
        id.split(separator: "-", maxSplits: 1).first.flatMap { Double($0) }.map(Date.init(timeIntervalSince1970:))
    }

    static func isExpired(created: Date, now: Date) -> Bool { now.timeIntervalSince(created) > requestLifetime }

    /// Only plain ids become file names: the app writes `decided/<id>` and must never be steered outside it.
    static func isSafeID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.allSatisfy { $0.isNumber || $0 == "-" }
    }

    // MARK: - The hook script

    /// Installed to `~/Library/Application Support/KatiKati/bin/katikati-approve`. POSIX sh and macOS
    /// built-ins only: no JSON parsing here (the app reads the raw hook input), no Python (the stub would
    /// pop an Xcode tools install dialog on a clean Mac).
    static let hookScript = #"""
    #!/bin/sh
    # katikati-approve: asks KatiKati to approve or deny a Claude Code tool request. Written by KatiKati.
    # Prints nothing (Claude then asks in the terminal) unless KatiKati answers in time.
    dir="$HOME/Library/Application Support/KatiKati/approvals"
    alive="$dir/alive"
    now=$(date +%s)
    stamp=$(stat -f %m "$alive" 2>/dev/null) || exit 0
    [ $((now - stamp)) -le 15 ] || exit 0
    id="$now-$$"
    mkdir -p "$dir/pending" "$dir/decided" || exit 0
    trap 'rm -f "$dir/pending/$id.json" "$dir/pending/$id.tmp" "$dir/decided/$id"' EXIT
    cat > "$dir/pending/$id.tmp" || exit 0
    mv "$dir/pending/$id.tmp" "$dir/pending/$id.json" || exit 0
    tries=0
    while [ $tries -lt 120 ]; do
      if [ -f "$dir/decided/$id" ]; then
        case "$(cat "$dir/decided/$id")" in
          allow)
            printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
            exit 0 ;;
          deny)
            printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied from KatiKati."}}}'
            exit 0 ;;
        esac
        exit 0
      fi
      now=$(date +%s)
      stamp=$(stat -f %m "$alive" 2>/dev/null) || exit 0
      [ $((now - stamp)) -le 15 ] || exit 0
      tries=$((tries + 1))
      sleep 0.5
    done
    exit 0
    """#
}

enum AgentPermissionPolicy {
    static let autoApproveReadOnlyKey = "com.katikati.agent.autoApproveReadOnly"
    static let readOnlyTools: Set<String> = ["Read", "Grep", "Glob", "LS", "WebFetch", "WebSearch"]

    static func isReadOnlyTool(toolName: String, summary: String) -> Bool {
        if readOnlyTools.contains(toolName) { return true }
        guard toolName == "Bash" else { return false }
        let cmd = summary.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let unsafeTokens = [";", "&&", "||", "|", ">", "<", "`", "$(", "rm ", "mv ", "cp ", "chmod ", "chown ", "git push", "git reset", "git checkout", "git commit", "git merge", "git rebase"]
        guard !unsafeTokens.contains(where: { cmd.contains($0) }) else { return false }
        return cmd.hasPrefix("git status") || cmd.hasPrefix("git diff") || cmd.hasPrefix("git log") || cmd == "pwd" || cmd.hasPrefix("ls")
    }

    static func shouldAutoApprove(_ request: AgentApprovalRequest, enabled: Bool) -> Bool {
        enabled && isReadOnlyTool(toolName: request.toolName, summary: request.summary)
    }
}

// MARK: - Liquid Notch Agent Socket & Hook Installer (LQ-3, MIT: fellipegoncalvesleite/liquid-notch)

enum LiquidAgentProvider: String, CaseIterable, Sendable {
    case claude, codex
    var displayName: String { self == .claude ? "Claude Code" : "Codex" }
}

enum LiquidAgentSessionState: String, Equatable, Sendable {
    case working, needs, done, ready, error
}

enum LiquidAgentNeed: Equatable, Sendable {
    case permission(tool: String, detail: String)
    case question(prompt: String, options: [String])
}

struct LiquidAgentSession: Identifiable, Equatable, Sendable {
    let id: String
    let provider: LiquidAgentProvider
    var state: LiquidAgentSessionState
    var cwd: String
    var tool: String
    var detail: String
    var need: LiquidAgentNeed?
    var updatedAt: Date
}

struct LiquidAgentHookLine: Sendable {
    let provider: String
    let event: String
    let host: String
    let raw: Data

    var json: [String: Any] { ((try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]) ?? [:] }

    var waits: Bool {
        event == "PermissionRequest" || (event == "PreToolUse" && provider == "claude" && json["tool_name"] as? String == "AskUserQuestion")
    }

    static func parse(_ data: Data) -> LiquidAgentHookLine? {
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        let parts = text.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4, let body = String(parts[3]).data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: body)) is [String: Any] else { return nil }
        return LiquidAgentHookLine(provider: String(parts[0]), event: String(parts[1]), host: String(parts[2]), raw: body)
    }

    static func decisionJSON(allow: Bool) -> String {
        let decision: [String: Any] = allow ? ["behavior": "allow"]
            : ["behavior": "deny", "message": "Denied from KatiKati."]
        let out: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        let data = (try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func answerJSON(input: [String: Any], question: String, option: String) -> String {
        var updated = input
        var answers = updated["answers"] as? [String: Any] ?? [:]
        answers[question] = option
        updated["answers"] = answers
        let out: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PreToolUse", "permissionDecision": "allow", "updatedInput": updated]]
        let data = (try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

enum LiquidHookInstaller {
    static let enabledKey = "com.katikati.liquid.agentHooksEnabled"

    struct Target {
        let provider: String
        let file: URL
        let events: [String]
    }

    static func targets(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [Target] {
        [
            Target(provider: "claude", file: home.appendingPathComponent(".claude/settings.json"),
                   events: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Notification", "Stop", "StopFailure", "SessionEnd"]),
            Target(provider: "codex", file: home.appendingPathComponent(".codex/hooks.json"),
                   events: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "SessionEnd"]),
        ]
    }

    static func supportDir(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/KatiKati", isDirectory: true)
    }

    static func scriptURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        supportDir(home: home).appendingPathComponent("agent-hook.sh")
    }

    static func socketPath(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        supportDir(home: home).appendingPathComponent("agents.sock").path
    }

    static let script = #"""
    #!/bin/sh
    # KatiKati Liquid Notch: fail-open local socket hook for Claude Code and Codex.
    SOCK="$HOME/Library/Application Support/KatiKati/agents.sock"
    [ -S "$SOCK" ] || exit 0
    EVENT="$1"; PROVIDER="$2"
    INPUT=$(tr -d '\n')
    WAIT=0
    [ "$EVENT" = PermissionRequest ] && WAIT=25
    if [ "$EVENT" = PreToolUse ] && printf '%s' "$INPUT" | /usr/bin/grep -q '"tool_name"[[:space:]]*:[[:space:]]*"AskUserQuestion"'; then WAIT=600; fi
    if [ "$WAIT" != 0 ]; then
      printf '%s\t%s\t%s\t%s\n' "$PROVIDER" "$EVENT" "$__CFBundleIdentifier" "$INPUT" | /usr/bin/nc -U -w "$WAIT" "$SOCK" 2>/dev/null
    else
      ( printf '%s\t%s\t%s\t%s\n' "$PROVIDER" "$EVENT" "$__CFBundleIdentifier" "$INPUT" | /usr/bin/nc -U -w 1 "$SOCK" ) </dev/null >/dev/null 2>&1 &
    fi
    exit 0
    """#

    static func timeout(for event: String, provider: String) -> Int {
        if event == "PermissionRequest" { return 30 }
        if event == "PreToolUse" && provider == "claude" { return 610 }
        return event == "SessionEnd" ? 2 : 5
    }

    static func installed(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        targets(home: home).allSatisfy { contains($0, home: home) }
    }

    static func install(home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        let scriptFile = scriptURL(home: home)
        try FileManager.default.createDirectory(at: scriptFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try script.write(to: scriptFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptFile.path)
        do {
            for t in targets(home: home) {
                try edit(t, home: home) { hooks in
                    for event in t.events {
                        var groups = hooks[event] as? [[String: Any]] ?? []
                        let cmd = "\"\(scriptFile.path)\" \(event) \(t.provider)"
                        groups.append(["hooks": [["type": "command", "command": cmd, "timeout": timeout(for: event, provider: t.provider)]]])
                        hooks[event] = groups
                    }
                }
            }
        } catch {
            try? uninstall(home: home)
            throw error
        }
    }

    static func uninstall(home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        for t in targets(home: home) where contains(t, home: home) {
            try edit(t, home: home) { _ in }
        }
        try? FileManager.default.removeItem(at: scriptURL(home: home))
    }

    private static func contains(_ target: Target, home: URL) -> Bool {
        guard let data = try? Data(contentsOf: target.file),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { ($0 as? [[String: Any]] ?? []).contains { isOurs($0, home: home) } }
    }

    private static func isOurs(_ group: [String: Any], home: URL) -> Bool {
        let path = scriptURL(home: home).path
        return (group["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String ?? "").contains(path) }
    }

    private static func edit(_ target: Target, home: URL, mutate: (inout [String: Any]) -> Void) throws {
        let fm = FileManager.default
        var root: [String: Any] = [:]
        if fm.fileExists(atPath: target.file.path) {
            let data = try Data(contentsOf: target.file)
            root = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let backup = target.file.deletingLastPathComponent()
                .appendingPathComponent("\(target.file.lastPathComponent).katikati-backup-\(Int(Date().timeIntervalSince1970))")
            try? data.write(to: backup, options: .atomic)
        } else {
            try fm.createDirectory(at: target.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for key in Array(hooks.keys) {
            let filtered = (hooks[key] as? [[String: Any]] ?? []).filter { !isOurs($0, home: home) }
            if filtered.isEmpty { hooks.removeValue(forKey: key) } else { hooks[key] = filtered }
        }
        mutate(&hooks)
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try out.write(to: target.file, options: .atomic)
    }
}
