import Foundation

// Phase 44 — the BitTorrent engine's wire vocabulary, split in two: this pure half (request params,
// status mapping, the protocol the hub drives) and the process/HTTP half in
// `App/Composition/TorrentEngine.swift`.
//
// Every shape here was read off a live `aria2c` 1.37.0 (2026-10-16) started with the exact argv
// `TorrentEngine` uses, against a real magnet:
//   * every number arrives as a *string* ("276445467", "connections": "44");
//   * a magnet's own GID describes only the metadata block it is fetching (21 307 bytes, file path
//     "[METADATA]Big+Buck+Bunny") and points at the real download through `followedBy`; the
//     `bittorrent.info.name`/payload numbers only exist on that followed GID;
//   * a failure comes back as `{"error":{"code":1,"message":"GID … is not found"}}` with no `result`.
//
// Pure and dual-compiled (app + unit tests) so the mapping is tested against those captured payloads.

enum Aria2RPC {
    /// The properties the 1 Hz poll asks for, so each tick's response stays small.
    static let statusKeys = ["gid", "status", "totalLength", "completedLength", "downloadSpeed",
                             "uploadSpeed", "connections", "numSeeders", "seeder", "infoHash",
                             "followedBy", "files", "bittorrent", "errorCode", "errorMessage"]

    static func body(id: Int, method: String, params: [Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": String(id),
                                                    "method": method, "params": params])
    }

    static func addParams(secret: String, uri: String, directory: String) -> [Any] {
        ["token:" + secret, [uri], ["dir": directory]]
    }

    static func statusParams(secret: String, gid: String) -> [Any] {
        ["token:" + secret, gid, statusKeys]
    }

    static func gidParams(secret: String, gid: String) -> [Any] {
        ["token:" + secret, gid]
    }

    /// A `tellStatus` result mapped onto the hub's model. `nil` when it carries no GID at all.
    struct Status: Equatable {
        var gid: String
        /// The payload download the engine started once the metadata (magnet) or the `.torrent` file
        /// landed — `followedBy`. `nil` while that is still in flight.
        var payloadGID: String?
        var infoHash: String?
        /// `bittorrent.info.name`, else the first file's name. The magnet's `dn` is only a placeholder
        /// until the real torrent name is known.
        var name: String?
        var state: DownloadItemState
        var totalBytes: Int64
        var completedBytes: Int64
        var downloadBps: Int64
        var uploadBps: Int64
        var connections: Int
        var seeders: Int
        var filePaths: [String]
    }

    static func status(from payload: [String: Any]) -> Status? {
        guard let gid = payload["gid"] as? String else { return nil }

        let bittorrent = payload["bittorrent"] as? [String: Any]
        let info = bittorrent?["info"] as? [String: Any]
        let raw = payload["status"] as? String ?? ""
        let payloadGID = (payload["followedBy"] as? [String])?.first

        // Metadata stage: the numbers on the wire describe the metadata block (or the `.torrent` file)
        // the engine is still fetching, never the download the user asked for. Reporting them would put
        // "21.3 KB" on a 276 MB row, so the row waits as CONNECTING instead.
        let metadataStage = info == nil

        var paths: [String] = []
        for file in (payload["files"] as? [[String: Any]]) ?? [] {
            if let path = file["path"] as? String, !path.hasPrefix("[METADATA]") { paths.append(path) }
        }
        let torrentName = (info?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        let state: DownloadItemState
        switch raw {
        case "error": state = .failed(failureText(payload))
        case "removed": state = .failed("removed")
        case "paused": state = .paused
        case "complete": state = metadataStage ? .initializing : .completed
        default: state = metadataStage ? .initializing : .active
        }

        return Status(
            gid: gid,
            payloadGID: payloadGID,
            infoHash: payload["infoHash"] as? String,
            name: torrentName ?? paths.first.map { ($0 as NSString).lastPathComponent },
            state: state,
            totalBytes: metadataStage ? 0 : int(payload["totalLength"]),
            completedBytes: metadataStage ? 0 : int(payload["completedLength"]),
            downloadBps: int(payload["downloadSpeed"]),
            uploadBps: int(payload["uploadSpeed"]),
            connections: Int(int(payload["connections"])),
            seeders: Int(int(payload["numSeeders"])),
            filePaths: paths
        )
    }

    /// The result envelope: `result`, or the error's message.
    enum Outcome {
        case result(Any)
        case failure(String)
    }

    static func outcome(from data: Data) -> Outcome {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure("the engine sent something that is not JSON")
        }
        if let error = object["error"] as? [String: Any] {
            return .failure((error["message"] as? String) ?? "the engine reported an error")
        }
        guard let result = object["result"] else { return .failure("the engine sent no result") }
        return .result(result)
    }

    private static func failureText(_ payload: [String: Any]) -> String {
        let message = (payload["errorMessage"] as? String) ?? ""
        guard message.isEmpty else { return message }
        let code = (payload["errorCode"] as? String) ?? "0"
        return "engine error \(code)"
    }

    private static func int(_ value: Any?) -> Int64 { Int64(value as? String ?? "") ?? 0 }
}

/// Phase 44b — the torrent hub's persisted policy: custom engine path, seeding limits and a
/// throttled upload window. Pure so the mapping is unit-tested; the engine + Settings read it via
/// `current()`. Defaults preserve today's behaviour (stop at completion, unlimited upload, no window).
enum TorrentSettings {
    static let enginePathKey = "com.katikati.torrent.enginePath"
    static let seedRatioKey = "com.katikati.torrent.seedRatio"
    static let seedTimeMinutesKey = "com.katikati.torrent.seedTimeMinutes"
    static let maxUploadKBpsKey = "com.katikati.torrent.maxUploadKBps"
    static let quietStartHourKey = "com.katikati.torrent.quietStartHour"
    static let quietEndHourKey = "com.katikati.torrent.quietEndHour"
    static let quietUploadKBpsKey = "com.katikati.torrent.quietUploadKBps"

    /// Where a package manager installs `aria2c`: first existing binary wins. The custom path (Settings)
    /// wins over all of these when it points at an executable file.
    static let candidatePaths = ["/opt/homebrew/bin/aria2c", "/usr/local/bin/aria2c",
                                 "/opt/local/bin/aria2c", "/usr/bin/aria2c"]

    struct Snapshot: Equatable {
        var enginePath = ""
        var seedRatio = 0.0
        var seedTimeMinutes = 0
        var maxUploadKBps = 0
        var quietStartHour = 0
        var quietEndHour = 0
        var quietUploadKBps = 0
    }

    static func current(defaults: UserDefaults = .standard) -> Snapshot {
        Snapshot(
            enginePath: defaults.string(forKey: enginePathKey) ?? "",
            seedRatio: clampedSeedRatio(defaults.object(forKey: seedRatioKey) as? Double),
            seedTimeMinutes: max(0, defaults.integer(forKey: seedTimeMinutesKey)),
            maxUploadKBps: max(0, defaults.integer(forKey: maxUploadKBpsKey)),
            quietStartHour: clampedHour(defaults.integer(forKey: quietStartHourKey)),
            quietEndHour: clampedHour(defaults.integer(forKey: quietEndHourKey)),
            quietUploadKBps: max(0, defaults.integer(forKey: quietUploadKBpsKey))
        )
    }

    /// Custom path wins when executable, else the first installed candidate. `isExecutable` is injected
    /// so tests never touch the filesystem.
    static func resolveBinary(custom: String?, isExecutable: (String) -> Bool) -> URL? {
        if let custom, !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           isExecutable(custom) { return URL(fileURLWithPath: custom) }
        return candidatePaths.first(where: isExecutable).map { URL(fileURLWithPath: $0) }
    }

    static func clampedSeedRatio(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0 }
        return min(max(value, 0), 50)
    }

    static func clampedHour(_ value: Int) -> Int { min(max(value, 0), 23) }

    /// Inside the quiet window the quiet limit wins (when set); outside, the normal limit. Equal
    /// start/end disables the window. Wraps past midnight.
    static func effectiveUploadLimit(maxKBps: Int, quietStart: Int, quietEnd: Int, quietKBps: Int, hour: Int) -> Int {
        guard quietStart != quietEnd, quietKBps > 0 else { return max(0, maxKBps) }
        let inWindow = quietStart < quietEnd
            ? (hour >= quietStart && hour < quietEnd)
            : (hour >= quietStart || hour < quietEnd)
        return inWindow ? quietKBps : max(0, maxKBps)
    }

    /// Global options pushed at spawn and via `changeGlobalOption`. `0` ratio/time = stop at completion
    /// (today's behaviour); `0` upload = unlimited.
    static func globalOptions(seedRatio: Double, seedMinutes: Int, uploadKBps: Int) -> [String: String] {
        ["seed-ratio": String(clampedSeedRatio(seedRatio)),
         "seed-time": String(max(0, seedMinutes)),
         "max-upload-limit": String(max(0, uploadKBps) * 1024)]
    }
}

/// One torrent row's resumable identity. GIDs die with the engine process, so only the URI is stored —
/// re-added through the normal path on next launch.
struct TorrentSessionEntry: Codable, Equatable {
    var uri: String
    var name: String
    var infoHash: String?
    var addedAt: Date
}

/// What the download hub needs from a BitTorrent engine. `TorrentEngine` is the aria2c-backed
/// implementation; unit tests inject a fake so no engine process (and no real transfer) is ever
/// started from a test.
@MainActor
protocol TorrentEngineClient: AnyObject {
    /// False when no `aria2c` binary is on this machine: magnets are then refused outright rather than
    /// answered with invented swarm numbers.
    var isAvailable: Bool { get }

    /// Starts the engine if needed and hands the magnet / `.torrent` URL over, returning the GID to poll.
    func add(uri: String, directory: URL) async throws -> String

    func status(gid: String) async throws -> Aria2RPC.Status
    func pause(gid: String) async throws
    func unpause(gid: String) async throws

    /// Drops a transfer best-effort: the right call depends on the state the GID is in (`forceRemove`
    /// while it runs, `remove` while paused, `removeDownloadResult` once finished), so all three are
    /// attempted and a refusal is not an error. Files already on disk are left alone.
    func remove(gid: String) async

    /// Stops the child process. Called when the last torrent leaves the hub and on app quit.
    func shutdown()

    /// Pushes the current seeding/upload policy to a running engine (no-op while stopped).
    func applyPolicy() async
}

extension TorrentEngineClient {
    func applyPolicy() async {}
}

enum TorrentEngineError: Error, Equatable {
    /// No `aria2c` binary on this machine.
    case notInstalled
    /// The child process never answered on its loopback port.
    case unreachable(String)
    /// The engine answered with `{"error": …}`.
    case engine(String)

    /// One line for the row / toast. Messages the engine sends are already user-grade.
    var message: String {
        switch self {
        case .notInstalled: return "aria2 isn't installed — magnet links are off"
        case .unreachable(let reason): return "BitTorrent engine unreachable: \(reason)"
        case .engine(let reason): return reason
        }
    }
}
