import Foundation

// Finds AI-agent CLI processes in `ps -axo pid=,ppid=,time=,command=` output. Pure so the matching rules are
// testable; the Platform service runs `ps` and feeds the text in.

struct ProcessRow: Equatable, Sendable {
    var pid: Int
    var ppid: Int
    var cpuSeconds: Double
    var args: String
}

struct AgentProcess: Equatable, Sendable {
    var pid: Int
    var name: String
    /// A one-shot run (`claude -p`, `codex exec`, `gemini -p`): counts as working until it exits.
    var background: Bool
    /// CPU seconds of the process plus everything it spawned (tool calls, shells).
    var cpuSeconds: Double
}

enum AgentProcessScan {
    static let knownNames = ["claude", "codex", "gemini", "opencode", "copilot"]
    private static let launchers: Set<String> = ["node", "bun", "deno", "python", "python3", "npx"]
    private static let oneShotFlags: Set<String> = ["-p", "--print", "exec"]

    /// Parses `ps` rows; cputime is `M:SS.ss` or `H:MM:SS.ss`. Malformed lines are skipped.
    static func parse(_ output: String) -> [ProcessRow] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int(parts[0]), let ppid = Int(parts[1]),
                  let cpu = cpuSeconds(String(parts[2])) else { return nil }
            return ProcessRow(pid: pid, ppid: ppid, cpuSeconds: cpu, args: String(parts[3]))
        }
    }

    static func cpuSeconds(_ text: String) -> Double? {
        let comps = text.split(separator: ":").map { Double($0) }
        guard !comps.isEmpty, comps.count <= 3, !comps.contains(where: { $0 == nil }) else { return nil }
        return comps.reduce(0) { $0 * 60 + $1! }
    }

    /// Top-level agent processes only; an agent's own helper copies are folded into its CPU.
    /// shortcut: any command line containing "mcp" or "language-server" is treated as a helper, not an agent.
    static func agents(_ rows: [ProcessRow], extraNames: [String] = []) -> [AgentProcess] {
        let names = Set((knownNames + extraNames).map { $0.lowercased() })
        let byPid = Dictionary(rows.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        var children: [Int: [Int]] = [:]
        for r in rows { children[r.ppid, default: []].append(r.pid) }

        var matched: [Int: (name: String, background: Bool)] = [:]
        for r in rows {
            let lower = r.args.lowercased()
            if lower.contains("mcp") || lower.contains("language-server") { continue }
            let tokens = r.args.split(separator: " ").map(String.init)
            guard let first = tokens.first else { continue }
            var nameIndex = 0
            var name = basename(first)
            if launchers.contains(name), tokens.count > 1 { nameIndex = 1; name = basename(tokens[1]) }
            // Case-sensitive on purpose: the desktop apps are `Claude`, the CLIs are `claude`.
            guard names.contains(name) else { continue }
            let rest = tokens.dropFirst(nameIndex + 1)
            matched[r.pid] = (name, rest.contains(where: oneShotFlags.contains))
        }

        func hasAgentAncestor(_ pid: Int) -> Bool {
            var cur = byPid[pid]?.ppid ?? 0
            for _ in 0..<20 { // bounded walk, no cycles
                if matched[cur] != nil { return true }
                guard let parent = byPid[cur]?.ppid, parent != cur else { return false }
                cur = parent
            }
            return false
        }
        func treeCPU(_ pid: Int) -> Double {
            (byPid[pid]?.cpuSeconds ?? 0) + (children[pid] ?? []).reduce(0) { $0 + treeCPU($1) }
        }
        return matched.filter { !hasAgentAncestor($0.key) }
            .map { AgentProcess(pid: $0.key, name: $0.value.name, background: $0.value.background, cpuSeconds: treeCPU($0.key)) }
            .sorted { $0.pid < $1.pid }
    }

    /// Working = a one-shot run, or CPU grew since the previous tick (the agent or a tool it started is computing).
    static func isWorking(_ p: AgentProcess, previousCPU: [Int: Double], threshold: Double = 0.3) -> Bool {
        if p.background { return true }
        guard let before = previousCPU[p.pid] else { return false }
        return p.cpuSeconds - before > threshold
    }

    private static func basename(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}
