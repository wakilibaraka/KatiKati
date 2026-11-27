import AppKit
import Darwin
import Foundation
import OSLog

/// The outcome of parsing one request line (W-10).
enum WorkspaceControlParse {
    case command(WorkspaceControlCommand)
    case error(String)
}

/// One parsed control-socket command (W-10).
enum WorkspaceControlCommand: Equatable, Sendable {
    case status
    case switchTo(WorkspaceID)
    case moveTo(WorkspaceID)
    case layout(TilingLayoutPreset)
    case pause
    case resume
    case retile
}

/// What the socket talks to (W-10).
///
/// The server deliberately never reaches into `TilingEngine` itself: it parses a line, hands the
/// command over, and writes the reply. That seam is what lets a test drive the real socket with a
/// stub and prove the protocol without a running window manager.
@MainActor
protocol WorkspaceControlTarget: AnyObject {
    func perform(_ command: WorkspaceControlCommand) -> String
}

/// W-10: a user-only control socket for workspaces and tiling, so scripts can drive what the
/// shortcuts drive.
///
/// Shape follows the rest of this app's private state: one UNIX socket under Application Support,
/// mode `0600`, plus an exclusive lock file so a second agent cannot serve the same path. Requests
/// are newline-delimited and capped at 4 KiB; replies are one line. Nothing here accepts a path or a
/// window id from the client — only a workspace token or a preset name, both validated against the
/// app's own types.
final class WorkspaceControlServer: @unchecked Sendable {
    static let shared = WorkspaceControlServer()

    /// A request longer than this is rejected instead of being half-parsed.
    static let maxRequestBytes = 4096

    private let queue = DispatchQueue(label: "com.katikati.workspace.control", qos: .utility)
    private let log = Logger(subsystem: "com.katikati.app", category: "workspace-control")
    private let explicitSocketURL: URL?
    private let explicitTarget: WorkspaceControlTarget?

    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var lockFD: Int32 = -1

    /// - Parameters:
    ///   - socketURL: overrides the Application Support path (tests use a temp directory).
    ///   - target: overrides `TilingEngine.shared` (tests use a spy).
    init(socketURL: URL? = nil, target: WorkspaceControlTarget? = nil) {
        self.explicitSocketURL = socketURL
        self.explicitTarget = target
    }

    /// True while this instance owns a listening socket.
    var isListening: Bool { listenFD >= 0 }

    var socketURL: URL? {
        explicitSocketURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("KatiKati", isDirectory: true)
            .appendingPathComponent("control.sock")
    }

    /// Idempotent: a second call while the socket is already listening does nothing.
    func start() {
        guard listenFD < 0, let url = socketURL else { return }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // One listener per path. `flock` locks the open file description, so a second instance in
        // the same process is rejected too — which is exactly what the end-to-end test asserts.
        let lockPath = directory.appendingPathComponent("control.lock").path
        lockFD = open(lockPath, O_CREAT | O_RDWR, 0o600)
        if lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
            // Another agent owns the socket; stay out of its way rather than unlinking its path.
            close(lockFD)
            lockFD = -1
            return
        }

        unlink(url.path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(url.path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            return
        }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
        }

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { addressPointer in
                bind(fd, addressPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            // `sun_path` is 104 bytes on macOS: an over-long path is the usual cause, and silently
            // leaving the CLI with no socket is worse than a log line.
            log.error("control socket bind failed for \(url.path, privacy: .public)")
            close(fd)
            return
        }
        chmod(url.path, 0o600)

        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptPending(on: fd)
        }
        source.resume()
        acceptSource = source
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        if let url = socketURL { unlink(url.path) }
        if lockFD >= 0 {
            flock(lockFD, LOCK_UN)
            close(lockFD)
            lockFD = -1
        }
    }

    private func acceptPending(on fd: Int32) {
        let client = accept(fd, nil, nil)
        guard client >= 0 else { return }

        var buffer = [UInt8](repeating: 0, count: Self.maxRequestBytes)
        let count = read(client, &buffer, buffer.count)
        guard count > 0 else {
            close(client)
            return
        }

        // A full buffer with no newline means the request ran past the cap. Reject it whole rather
        // than acting on a truncated command.
        let hasTerminator = buffer[0..<count].contains(UInt8(ascii: "\n"))
        let tooLarge = count >= Self.maxRequestBytes && !hasTerminator
        let request = String(decoding: buffer[0..<count], as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        Task { @MainActor in
            let reply: String
            if tooLarge {
                reply = "error request too large"
            } else {
                let target: WorkspaceControlTarget = self.explicitTarget ?? TilingEngine.shared
                switch WorkspaceControlServer.parse(request) {
                case .command(let command): reply = target.perform(command)
                case .error(let message): reply = message
                }
            }
            let bytes = Array((reply + "\n").utf8)
            _ = bytes.withUnsafeBufferPointer { pointer in
                write(client, pointer.baseAddress, pointer.count)
            }
            close(client)
        }
    }

    /// Pure parser: one line in, one command or one error line out. No socket, no engine.
    static func parse(_ request: String) -> WorkspaceControlParse {
        let parts = request.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let command = parts.first?.lowercased() else { return .error("error empty request") }

        switch command {
        case "status":
            return .command(.status)

        case "switch", "move":
            guard parts.count > 1, let workspace = WorkspaceID(token: parts[1]) else {
                return .error("error expected a workspace 1-10 or A-Z")
            }
            return .command(command == "switch" ? .switchTo(workspace) : .moveTo(workspace))

        case "layout":
            guard parts.count > 1, let preset = TilingLayoutPreset(rawValue: parts[1]) else {
                return .error("error expected a preset: " + TilingLayoutPreset.allCases.map(\.rawValue).joined(separator: ","))
            }
            return .command(.layout(preset))

        case "pause":
            return .command(.pause)

        case "resume":
            return .command(.resume)

        case "retile":
            return .command(.retile)

        default:
            return .error("error unknown command (status, switch, move, layout, pause, resume, retile)")
        }
    }
}

/// The production target: the app's own tiling engine.
extension TilingEngine: WorkspaceControlTarget {
    func perform(_ command: WorkspaceControlCommand) -> String {
        switch command {
        case .status:
            let displayKey = NSScreen.screens.first.map { screenKey(for: $0) } ?? "main"
            let workspace = activeWorkspace(on: displayKey)
            let enabled = workspacesEnabled ? "on" : "off"
            let tiling = isEnabled ? "on" : "off"
            let count = workspaceTree(for: workspace, on: displayKey).count
            return "ok workspaces=\(enabled) tiling=\(tiling) display=\(displayKey) workspace=\(workspace.token) windows=\(count)"

        case .switchTo(let workspace):
            guard workspacesEnabled else { return "error workspaces are off" }
            switchWorkspace(workspace)
            return "ok switch \(workspace.token)"

        case .moveTo(let workspace):
            guard workspacesEnabled else { return "error workspaces are off" }
            moveFocusedToWorkspace(workspace)
            return "ok move \(workspace.token)"

        case .layout(let preset):
            setPreset(preset)
            return "ok layout \(preset.rawValue)"

        case .pause:
            setEnabled(false)
            return "ok paused"

        case .resume:
            setEnabled(true)
            return "ok resumed"

        case .retile:
            retileAll()
            return "ok retiled"
        }
    }
}
