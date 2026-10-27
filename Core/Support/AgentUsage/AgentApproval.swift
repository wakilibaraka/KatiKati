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
        return AgentApprovalRequest(
            id: id, toolName: tool,
            summary: truncate(oneLine, to: summaryLimit),
            detail: full.count > summaryLimit || full.contains("\n") ? truncate(full.trimmingCharacters(in: .whitespacesAndNewlines), to: detailLimit) : nil,
            cwd: object["cwd"] as? String,
            created: created)
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
