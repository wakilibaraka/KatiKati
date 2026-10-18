import AppKit
import Darwin
import Foundation

/// Phase 28e: lists running processes for the `!` process-killer route. Reads `ps` once at summon; the
/// per-keystroke filtering is pure (`CommandBarResults`).
/// Phase 48d: also owns the one confirm-then-end flow — the Command Bar and the Top Apps tile share it
/// rather than each writing their own alert.
enum ProcessLister {
    static func list() -> [ProcessEntry] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,comm="]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.split(whereSeparator: \.isNewline).compactMap(parse)
    }

    private static func parse(_ line: Substring) -> ProcessEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let space = trimmed.firstIndex(of: " ") else { return nil }
        guard let pid = Int32(trimmed[..<space]) else { return nil }
        let path = trimmed[trimmed.index(after: space)...].trimmingCharacters(in: .whitespaces)
        let name = (path as NSString).lastPathComponent
        guard !name.isEmpty else { return nil }
        return ProcessEntry(pid: pid, name: name, path: path)
    }
}

/// The one confirm-then-end flow: `NSAlert` with the name and `PID <n>`, Kill (SIGTERM) /
/// Force Quit (SIGKILL) / Cancel. A refused signal (another user's process: `EPERM`) is reported
/// with the system's own reason string rather than pretending the process is gone — the caller
/// re-reads the list, so a surviving pid redraws itself.
enum ProcessKillConfirm {
    static func confirm(name: String, pid: Int32) {
        let alert = NSAlert()
        alert.messageText = name
        alert.informativeText = "PID \(pid)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Kill"))
        alert.addButton(withTitle: String(localized: "Force Quit"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let signal: Int32
        switch alert.runModal() {
        case .alertFirstButtonReturn: signal = SIGTERM
        case .alertSecondButtonReturn: signal = SIGKILL
        default: return
        }
        guard kill(pid, signal) != 0 else { return }
        let reason = String(cString: strerror(errno))
        let failed = NSAlert()
        failed.messageText = name
        failed.informativeText = "PID \(pid): \(reason)"
        failed.alertStyle = .warning
        failed.addButton(withTitle: String(localized: "Cancel"))
        failed.runModal()
    }
}
