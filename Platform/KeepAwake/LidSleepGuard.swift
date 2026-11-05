import Foundation

/// Lid-closed mode: macOS has no public switch, so this runs `pmset -a disablesleep` through a narrow
/// passwordless sudoers rule that the owner approves once with an admin prompt. A watchdog restores sleep if
/// KatiKati dies while the guard is on, and a leftover guard is reverted on the next launch.
enum LidSleepGuard {
    private static let pmset = "/usr/bin/pmset"
    nonisolated(unsafe) private static var watchdog: Process?

    /// True once the sudoers rule exists and allows the command without a password.
    static func isInstalled() -> Bool {
        run("/usr/bin/sudo", ["-n", "-l", pmset, "-a", "disablesleep", "1"]) == 0
    }

    /// One admin-password prompt; the rule is validated with `visudo -c` before it is installed.
    static func install() -> Bool {
        guard let rule = LidSleepSudoers.rule(user: NSUserName()) else { return false }
        let script = "tmp=$(/usr/bin/mktemp) && printf '%s\\n' '\(rule)' > \"$tmp\" && /usr/sbin/visudo -cf \"$tmp\" "
            + "&& /usr/bin/install -m 0440 -o root -g wheel \"$tmp\" \(LidSleepSudoers.path); rc=$?; /bin/rm -f \"$tmp\"; exit $rc"
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let apple = "do shell script \"\(escaped)\" with administrator privileges"
        return run("/usr/bin/osascript", ["-e", apple]) == 0 && isInstalled()
    }

    /// Turns the guard on or off. Returns false when sudo refused (rule missing).
    @discardableResult
    static func set(_ on: Bool) -> Bool {
        let ok = run("/usr/bin/sudo", ["-n", pmset, "-a", "disablesleep", on ? "1" : "0"]) == 0
        if ok && on { startWatchdog() } else { stopWatchdog() }
        return ok
    }

    /// A previous run may have died with the guard on; sleep must not stay disabled forever.
    static func revertLeftover() {
        guard isEngaged(), isInstalled() else { return }
        set(false)
    }

    static func isEngaged() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: pmset)
        p.arguments = ["-g"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        return out.split(separator: "\n").contains { $0.contains("SleepDisabled") && $0.hasSuffix("1") }
    }

    // A detached shell outlives a force-quit of KatiKati and restores sleep a few seconds after we are gone.
    private static func startWatchdog() {
        stopWatchdog()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while /bin/kill -0 \(getpid()) 2>/dev/null; do /bin/sleep 3; done; /usr/bin/sudo -n \(pmset) -a disablesleep 0"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        watchdog = p
    }

    private static func stopWatchdog() {
        watchdog?.terminate()
        watchdog = nil
    }

    private static func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus } catch { return -1 }
    }
}
