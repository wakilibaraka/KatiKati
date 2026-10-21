import Foundation

/// Phase 52c — the only code that writes to `~/.claude/settings.json`. It reads the file, asks the
/// pure `ClaudeHookConfig` for the new bytes and writes them atomically. A file that is not a JSON
/// object throws and is left byte-for-byte alone; the first real file is copied to
/// `settings.json.katikati-backup` once, so turning the hook off by hand is always possible.
@MainActor
enum ClaudeHookInstaller {
    nonisolated static let enabledKey = "com.katikati.agent.claudeHook"

    nonisolated static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(ClaudeHookConfig.settingsRelativePath)
    }

    static func setEnabled(_ on: Bool, settingsURL: URL = settingsURL) throws {
        let fileManager = FileManager.default
        // An unreadable file throws here instead of looking like a missing one, so nothing is overwritten.
        let existing = fileManager.fileExists(atPath: settingsURL.path) ? try Data(contentsOf: settingsURL) : nil
        if !on && existing == nil { return }

        let current = existing ?? Data("{}".utf8)
        let updated: Data
        if on {
            updated = try ClaudeHookConfig.install(into: current)
        } else {
            updated = try ClaudeHookConfig.remove(from: current)
        }
        guard updated != existing else { return }

        let backup = settingsURL.appendingPathExtension("katikati-backup")
        if let existing, !fileManager.fileExists(atPath: backup.path) {
            try existing.write(to: backup, options: .atomic)
        }
        try fileManager.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try updated.write(to: settingsURL, options: .atomic)

        if on {
            // The hook appends with `>>`, which fails when the folder is missing.
            try? fileManager.createDirectory(at: ClaudeHookConfig.logURL().deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
            AgentUsageService.shared.watchHookLog()
        }
        AgentUsageService.shared.refreshAsync()
    }
}
