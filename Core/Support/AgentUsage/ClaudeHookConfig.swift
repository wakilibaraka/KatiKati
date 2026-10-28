import Foundation

// Phase 52c — the opt-in Claude Code hook. Two entries in `~/.claude/settings.json` append
// `<epoch> <event>` to a local log; the notch then ends a turn when Claude says it stopped instead
// of waiting out the transcript mtime window. Dual-compiled: pure JSON in, JSON out.

/// The two events we install. `UserPromptSubmit` fires when a turn starts, `Stop` when it ends.
enum ClaudeHookEvent: String, CaseIterable, Sendable {
    case working = "UserPromptSubmit"
    case idle = "Stop"
}

enum ClaudeHookConfigError: Error {
    /// The file exists but is not a JSON object. Refused rather than replaced: it may be the user's
    /// only copy of their Claude Code settings.
    case notAJSONObject
}

enum ClaudeHookConfig {
    /// Present in every command we write. Removal matches this, so other people's hooks survive.
    static let marker = "KatiKati/claude-status.log"
    static let settingsRelativePath = ".claude/settings.json"
    static let logRelativePath = "Library/Application Support/KatiKati/claude-status.log"

    static func logURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(logRelativePath)
    }

    /// The hook runs through the user's shell; `$HOME` is quoted because the app support path has a space.
    static func command(for event: ClaudeHookEvent) -> String {
        "printf '%s %s\\n' \"$(date +%s)\" \(event.rawValue) >> \"$HOME/\(logRelativePath)\""
    }

    /// Adds our entries, replacing any earlier copy of ours. Every other key and hook is carried over
    /// untouched; running it twice produces the same bytes.
    static func install(into data: Data) throws -> Data {
        var root = try rootObject(from: data)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in ClaudeHookEvent.allCases {
            var groups = strippingOurHooks(from: hooks[event.rawValue] as? [Any] ?? []).groups
            groups.append(["hooks": [["type": "command", "command": command(for: event)]]])
            hooks[event.rawValue] = groups
        }
        root["hooks"] = hooks
        return try serialize(root)
    }

    /// Removes only our entries. Returns `data` untouched when there are none.
    static func remove(from data: Data) throws -> Data {
        var root = try rootObject(from: data)
        guard var hooks = root["hooks"] as? [String: Any] else { return data }
        var removedAny = false
        for event in ClaudeHookEvent.allCases {
            guard let existing = hooks[event.rawValue] as? [Any] else { continue }
            let result = strippingOurHooks(from: existing)
            guard result.removedAny else { continue }
            removedAny = true
            let kept = result.groups
            if kept.isEmpty {
                hooks.removeValue(forKey: event.rawValue)
            } else {
                hooks[event.rawValue] = kept
            }
        }
        guard removedAny else { return data }
        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }
        return try serialize(root)
    }

    // MARK: - JSON

    private static func rootObject(from data: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            throw ClaudeHookConfigError.notAJSONObject
        }
        guard let root = object as? [String: Any] else { throw ClaudeHookConfigError.notAJSONObject }
        return root
    }

    private static func serialize(_ root: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// Drops our entries from every matcher group. A group that held other commands keeps them; a group
    /// that was only ours disappears. `removedAny` is what removal needs: a group can stay while its
    /// contents change, so counting groups would miss it.
    private static func strippingOurHooks(from groups: [Any], marker: String = ClaudeHookConfig.marker) -> (groups: [Any], removedAny: Bool) {
        var removedAny = false
        let kept = groups.compactMap { group -> Any? in
            guard var dictionary = group as? [String: Any], let hooks = dictionary["hooks"] as? [Any] else {
                return group
            }
            let remaining = hooks.filter { !isOurs(entry: $0, marker: marker) }
            guard remaining.count != hooks.count else { return group }
            removedAny = true
            guard !remaining.isEmpty else { return nil }
            dictionary["hooks"] = remaining
            return dictionary
        }
        return (kept, removedAny)
    }

    private static func isOurs(entry: Any, marker: String = ClaudeHookConfig.marker) -> Bool {
        guard let entry = entry as? [String: Any], let command = entry["command"] as? String else { return false }
        return command.contains(marker)
    }

    // MARK: - Approvals (port plan #5)

    /// The one extra event: Claude asks before running a tool the user's rules do not already allow.
    static let approvalEvent = "PermissionRequest"
    /// Present in the approval command, and nowhere in the status commands, so each removes only its own.
    static let approvalMarker = "katikati-approve"
    static let approvalScriptRelativePath = "Library/Application Support/KatiKati/bin/katikati-approve"
    /// How long Claude waits for the script. The script gives up a little earlier and hands the question
    /// back to the terminal prompt, so a missed card never leaves Claude stuck.
    static let approvalHookTimeoutSeconds = 70

    static func approvalCommand() -> String { "\"$HOME/\(approvalScriptRelativePath)\"" }

    static func installApproval(into data: Data) throws -> Data {
        var root = try rootObject(from: data)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var groups = strippingOurHooks(from: hooks[approvalEvent] as? [Any] ?? [], marker: approvalMarker).groups
        groups.append(["hooks": [["type": "command", "command": approvalCommand(), "timeout": approvalHookTimeoutSeconds]]])
        hooks[approvalEvent] = groups
        root["hooks"] = hooks
        return try serialize(root)
    }

    static func removeApproval(from data: Data) throws -> Data {
        var root = try rootObject(from: data)
        guard var hooks = root["hooks"] as? [String: Any], let existing = hooks[approvalEvent] as? [Any] else { return data }
        let result = strippingOurHooks(from: existing, marker: approvalMarker)
        guard result.removedAny else { return data }
        if result.groups.isEmpty { hooks.removeValue(forKey: approvalEvent) } else { hooks[approvalEvent] = result.groups }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        return try serialize(root)
    }
}
