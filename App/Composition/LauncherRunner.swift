import AppKit

/// Phase 21c: runs a `.script` (AppleScript through `osascript`) or `.shortcut` (`shortcuts run`) from the
/// launcher. Off unless `com.katikati.launcher.scripts.enabled` is on; a destructive script is confirmed
/// first (see `LauncherScriptSafety`). Nothing runs, polls, or spawns at rest.
@MainActor
enum LauncherRunner {
    static let enabledKey = "com.katikati.launcher.scripts.enabled"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Runs the script/shortcut half of a routed query. Returns false when disabled or when a destructive
    /// script is declined. The one-time Automation/Shortcuts prompt fires on first actual use.
    @discardableResult
    static func run(_ query: LauncherQuery) -> Bool {
        guard isEnabled else { return false }
        switch query {
        case .script(let payload):
            guard LauncherScriptSafety.classify(payload) != .destructive || confirm(payload) else { return false }
            return launch("/usr/bin/osascript", ["-e", payload])
        case .shortcut(let name):
            return launch("/usr/bin/shortcuts", ["run", name])
        default:
            return false
        }
    }

    private static func launch(_ executable: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        do { try process.run() } catch { NSSound.beep(); return false }
        return true
    }

    private static func confirm(_ payload: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Run Script")
        alert.informativeText = payload
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Continue"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}
