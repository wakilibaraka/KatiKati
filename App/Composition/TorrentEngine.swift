import Darwin
import Foundation

/// Phase 44 — the BitTorrent engine behind the download hub. KatiKati has no in-process torrent stack,
/// so it drives `aria2c` (the package-manager standard on macOS) as a loopback-only JSON-RPC child
/// process it owns: `--rpc-listen-all=false`, a fresh random `--rpc-secret` per start, and the user's
/// Downloads folder as its `--dir`, so a torrent lands where the other two download types do.
///
/// Lifecycle: nothing spawns until the first magnet lands, the process is stopped when the last torrent
/// leaves the hub (`DownloadManagerService`) and on quit (`AppDelegate`) — so a machine that never opens
/// a magnet never runs it, and no orphan engine is left behind. `--seed-time=0` stops the upload when the
/// payload completes.
///
/// No `aria2c` on the machine means `isAvailable == false` and magnet input is refused, never answered
/// with invented swarm numbers (that is the Phase 43 rule this replaces the refusal with a real engine).
///
/// Phase 44b: the binary resolves on every read (custom Settings path wins, else the installed
/// candidates), so a pasted path works without relaunch; seeding/upload policy comes from the same
/// settings and is pushed at spawn plus live via `applyPolicy()`.
@MainActor
final class TorrentEngine: TorrentEngineClient {
    static let shared = TorrentEngine()

    private var process: Process?
    private var port: Int?
    private var secret: String?
    private var nextRequestID = 1

    private var binary: URL? {
        let custom = UserDefaults.standard.string(forKey: TorrentSettings.enginePathKey)
        return TorrentSettings.resolveBinary(custom: custom) {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    /// The resolved path for the Settings status line (nil = none found).
    var resolvedBinaryPath: String? { binary?.path }

    var isAvailable: Bool { binary != nil }

    // MARK: - Transfers

    func add(uri: String, directory: URL) async throws -> String {
        try await startIfNeeded()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let value = try await call("aria2.addUri", Aria2RPC.addParams(secret: secret ?? "", uri: uri, directory: directory.path))
        guard let gid = value as? String else { throw TorrentEngineError.engine("the engine accepted the link but returned no GID") }
        return gid
    }

    func status(gid: String) async throws -> Aria2RPC.Status {
        let value = try await call("aria2.tellStatus", Aria2RPC.statusParams(secret: secret ?? "", gid: gid))
        guard let payload = value as? [String: Any], let status = Aria2RPC.status(from: payload) else {
            throw TorrentEngineError.engine("unexpected status payload")
        }
        return status
    }

    func pause(gid: String) async throws {
        _ = try await call("aria2.pause", Aria2RPC.gidParams(secret: secret ?? "", gid: gid))
    }

    func unpause(gid: String) async throws {
        _ = try await call("aria2.unpause", Aria2RPC.gidParams(secret: secret ?? "", gid: gid))
    }

    func remove(gid: String) async {
        // The right call depends on where the GID is; a refusal for the wrong state is expected, not an error.
        for method in ["aria2.forceRemove", "aria2.remove", "aria2.removeDownloadResult"] {
            _ = try? await call(method, Aria2RPC.gidParams(secret: secret ?? "", gid: gid))
        }
    }

    // MARK: - Process lifecycle

    /// Pushes the current seeding/upload policy to a running engine. No-op while stopped; a binary-path
    /// change applies on next start only — never kill a running transfer to switch binaries.
    func applyPolicy() async {
        guard process?.isRunning == true, let secret else { return }
        let policy = TorrentSettings.current()
        let hour = Calendar.current.component(.hour, from: Date())
        let limit = TorrentSettings.effectiveUploadLimit(maxKBps: policy.maxUploadKBps, quietStart: policy.quietStartHour, quietEnd: policy.quietEndHour, quietKBps: policy.quietUploadKBps, hour: hour)
        let options = TorrentSettings.globalOptions(seedRatio: policy.seedRatio, seedMinutes: policy.seedTimeMinutes, uploadKBps: limit)
        _ = try? await call("aria2.changeGlobalOption", ["token:" + secret, options])
    }

    private func startIfNeeded() async throws {
        if process?.isRunning == true, port != nil { return }
        guard let binary else { throw TorrentEngineError.notInstalled }
        guard let port = Self.freeLoopbackPort() else { throw TorrentEngineError.unreachable("no free loopback port") }

        let policy = TorrentSettings.current()
        let hour = Calendar.current.component(.hour, from: Date())
        let limit = TorrentSettings.effectiveUploadLimit(maxKBps: policy.maxUploadKBps, quietStart: policy.quietStartHour, quietEnd: policy.quietEndHour, quietKBps: policy.quietUploadKBps, hour: hour)
        let options = TorrentSettings.globalOptions(seedRatio: policy.seedRatio, seedMinutes: policy.seedTimeMinutes, uploadKBps: limit)
        let secret = UUID().uuidString
        let process = Process()
        process.executableURL = binary
        process.arguments = ["--no-conf", "--quiet", "--console-log-level=warn",
                            "--enable-rpc=true", "--rpc-listen-all=false",
                            "--rpc-listen-port=\(port)", "--rpc-secret=\(secret)",
                            "--dir=\(downloadsDirectory.path)",
                            "--seed-ratio=\(options["seed-ratio"] ?? "0")",
                            "--seed-time=\(options["seed-time"] ?? "0")",
                            "--max-upload-limit=\(options["max-upload-limit"] ?? "0")",
                            "--file-allocation=none", "--summary-interval=0",
                            // Backstop for a hard kill (SIGKILL/crash), where `applicationWillTerminate`
                            // never runs: aria2 exits within a few seconds of us (measured 2026-10-16).
                            "--stop-with-process=\(getpid())"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw TorrentEngineError.unreachable(error.localizedDescription)
        }
        self.process = process
        self.port = port
        self.secret = secret

        // The port is not answering the instant the process starts; poll `getVersion` with a bounded wait.
        for _ in 0..<40 {
            if (try? await call("aria2.getVersion", ["token:" + secret])) != nil {
                await applyPolicy()
                return
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        shutdown()
        throw TorrentEngineError.unreachable("aria2 did not answer on 127.0.0.1:\(port)")
    }

    func shutdown() {
        process?.terminate()
        process = nil
        port = nil
        secret = nil
    }

    private var downloadsDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    }

    // MARK: - RPC

    private func call(_ method: String, _ params: [Any]) async throws -> Any {
        guard let port else { throw TorrentEngineError.unreachable("the engine is not running") }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/jsonrpc")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Aria2RPC.body(id: nextRequestID, method: method, params: params)
        nextRequestID += 1

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw TorrentEngineError.unreachable(error.localizedDescription)
        }
        switch Aria2RPC.outcome(from: data) {
        case .result(let value): return value
        case .failure(let message): throw TorrentEngineError.engine(message)
        }
    }

    /// A loopback port for the engine to bind. Chosen by binding port 0 and reading back the kernel's
    /// pick, then released for aria2 — a tiny race another process could win, which the readiness probe
    /// above then reports instead of pretending the engine is up.
    private static func freeLoopbackPort() -> Int? {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)

        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, length) }
        }
        guard bound == 0 else { return nil }
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        guard named == 0 else { return nil }
        return Int(UInt16(bigEndian: address.sin_port))
    }
}
