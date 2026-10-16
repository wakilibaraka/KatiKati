import Foundation
import XCTest
@testable import KatiKati

final class DownloadManagerTests: XCTestCase {

    func testMagnetURIParserValid() {
        let uri = "magnet:?xt=urn:btih:c12fe1c06bba254a9dc9f519b335380dc1f74c38&dn=Ubuntu+24.04+LTS&tr=https%3A%2F%2Ftorrent.ubuntu.com%2Fannounce&xl=5400000000"
        let parsed = MagnetURIParser.parse(uri)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.displayName, "Ubuntu 24.04 LTS")
        XCTAssertEqual(parsed?.infoHash, "C12FE1C06BBA254A9DC9F519B335380DC1F74C38")
        XCTAssertEqual(parsed?.exactLength, 5400000000)
        XCTAssertEqual(parsed?.trackers.count, 1)
        XCTAssertEqual(parsed?.trackers.first, "https://torrent.ubuntu.com/announce")
    }

    func testMagnetURIParserInvalid() {
        let invalid = "https://example.com/file.iso"
        XCTAssertNil(MagnetURIParser.parse(invalid))

        let noHash = "magnet:?dn=Something"
        XCTAssertNil(MagnetURIParser.parse(noHash))
    }

    func testDownloadItemCalculations() {
        var item = DownloadItem(
            name: "test.zip",
            type: .directUrl,
            state: .active,
            bytesDownloaded: 500_000_000,
            totalBytes: 1_000_000_000,
            downloadSpeedBps: 10_000_000,
            etaSeconds: 50
        )

        XCTAssertEqual(item.fraction, 0.5, accuracy: 0.001)
        XCTAssertEqual(item.formattedETA, "50s")
        XCTAssertTrue(item.formattedSpeed.contains("/s"))
        XCTAssertTrue(item.formattedSizeProgress.contains("/"))

        item.etaSeconds = 125
        XCTAssertEqual(item.formattedETA, "2m 5s")

        item.etaSeconds = 3665
        XCTAssertEqual(item.formattedETA, "1h 1m")
    }

    /// Phase 44: the hub starts empty and refuses BitTorrent input only when no engine is installed on the
    /// machine; an http(s) link still goes through pause / resume / cancel. (The magnet's real path is
    /// covered below with a fake engine, so no test ever spawns `aria2c`.)
    @MainActor
    func testDownloadManagerStartsEmptyAndRefusesTorrentsWithoutAnEngine() {
        let service = DownloadManagerService(torrent: FakeTorrentEngine(available: false))
        XCTAssertTrue(service.items.isEmpty)

        let magnet = "magnet:?xt=urn:btih:FEDCBA9876543210FEDCBA9876543210FEDCBA98&dn=TestTorrent"
        XCTAssertFalse(service.addDownload(input: magnet))
        XCTAssertFalse(service.addDownload(input: "https://example.com/ubuntu-24.04.iso.torrent"))
        XCTAssertFalse(service.addDownload(input: "not a link"))
        XCTAssertTrue(service.items.isEmpty)

        // `.invalid` is reserved (RFC 2606), so the transfer itself never reaches a real host.
        XCTAssertTrue(service.addDownload(input: "https://download.invalid/test.zip"))
        XCTAssertEqual(service.items.count, 1)
        let item = service.items[0]
        XCTAssertEqual(item.type, .directUrl)
        XCTAssertEqual(item.name, "test.zip")
        XCTAssertEqual(item.downloadSpeedBps, 0)   // no invented rate before the delegate reports one
        XCTAssertNil(item.etaSeconds)

        service.pause(id: item.id)
        XCTAssertEqual(service.items.first(where: { $0.id == item.id })?.state, .paused)

        service.resume(id: item.id)
        XCTAssertEqual(service.items.first(where: { $0.id == item.id })?.state, .active)

        service.cancel(id: item.id)
        XCTAssertNil(service.items.first(where: { $0.id == item.id }))
        XCTAssertTrue(service.items.isEmpty)
    }

    // MARK: - Aria2RPC mapping (payloads captured from a live aria2c 1.37.0, 2026-10-16)

    /// The magnet's own GID describes only the metadata block it fetches: 21 307 bytes in the capture. The
    /// row must stay CONNECTING with no size at all rather than showing that as the download.
    func testMagnetStagePayloadMapsToConnectingWithoutInventingASize() throws {
        let status = try XCTUnwrap(Aria2RPC.status(from: Self.metadataPayload))

        XCTAssertEqual(status.gid, "ece738d8a6098dd9")
        XCTAssertNil(status.payloadGID)
        XCTAssertEqual(status.state, .initializing)
        XCTAssertEqual(status.totalBytes, 0)
        XCTAssertEqual(status.completedBytes, 0)
        XCTAssertNil(status.name)                  // the [METADATA] path is the engine's, not a name
        XCTAssertTrue(status.filePaths.isEmpty)
        XCTAssertEqual(status.seeders, 3)          // real swarm counts are available even this early
        XCTAssertEqual(status.connections, 44)
        XCTAssertEqual(status.infoHash, "dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c")
    }

    /// Once the metadata lands, the same GID points at the payload: still CONNECTING (the numbers below
    /// would be the metadata block's), until that payload GID is polled instead.
    func testMetadataCompleteWithFollowedByStaysConnecting() throws {
        var payload = Self.metadataPayload
        payload["followedBy"] = ["40d4fc03ecf33ee3"]
        payload["status"] = "complete"
        payload["completedLength"] = "21307"

        let status = try XCTUnwrap(Aria2RPC.status(from: payload))
        XCTAssertEqual(status.payloadGID, "40d4fc03ecf33ee3")
        XCTAssertEqual(status.state, .initializing)
        XCTAssertEqual(status.totalBytes, 0)
    }

    /// The payload GID: the torrent's real name, size, swarm counts and file paths.
    func testPayloadMapsTheRealTransfer() throws {
        let status = try XCTUnwrap(Aria2RPC.status(from: Self.payload))

        XCTAssertEqual(status.gid, "40d4fc03ecf33ee3")
        XCTAssertEqual(status.state, .active)
        XCTAssertEqual(status.name, "Big Buck Bunny")
        XCTAssertEqual(status.totalBytes, 276_445_467)
        XCTAssertEqual(status.completedBytes, 3_455_259)
        XCTAssertEqual(status.downloadBps, 1_884_659)
        XCTAssertEqual(status.seeders, 10)
        XCTAssertEqual(status.connections, 44)
        XCTAssertEqual(status.filePaths.count, 3)
        XCTAssertEqual(status.filePaths.last, "/tmp/kkt-wire/dl/Big Buck Bunny/poster.jpg")
    }

    func testTerminalAndFailedStatuses() throws {
        var complete = Self.payload
        complete["status"] = "complete"
        complete["downloadSpeed"] = "0"
        XCTAssertEqual(Aria2RPC.status(from: complete)?.state, .completed)

        var paused = Self.payload
        paused["status"] = "paused"
        XCTAssertEqual(Aria2RPC.status(from: paused)?.state, .paused)

        var failed = Self.payload
        failed["status"] = "error"
        failed["errorCode"] = "1"
        failed["errorMessage"] = "No such file or directory"
        XCTAssertEqual(Aria2RPC.status(from: failed)?.state, .failed("No such file or directory"))

        XCTAssertNil(Aria2RPC.status(from: ["status": "active"]))   // no GID: not a status
    }

    func testErrorEnvelopeBecomesAFailure() {
        let body = Data(#"{"id":"p","jsonrpc":"2.0","error":{"code":1,"message":"GID 0123456789abcdef is not found"}}"#.utf8)
        guard case .failure(let message) = Aria2RPC.outcome(from: body) else {
            return XCTFail("an error envelope must not read as a result")
        }
        XCTAssertEqual(message, "GID 0123456789abcdef is not found")

        let ok = Data(#"{"id":"p","jsonrpc":"2.0","result":"OK"}"#.utf8)
        guard case .result(let value) = Aria2RPC.outcome(from: ok) else {
            return XCTFail("a result envelope must read as a result")
        }
        XCTAssertEqual(value as? String, "OK")

        guard case .failure = Aria2RPC.outcome(from: Data("not json".utf8)) else {
            return XCTFail("garbage is a failure, not a crash")
        }
    }

    /// The exact param shapes the live engine accepted in the capture: `[token, [uri], {dir}]`.
    func testRequestShapes() throws {
        let body = try XCTUnwrap(Aria2RPC.body(id: 7, method: "aria2.tellStatus",
                                              params: Aria2RPC.statusParams(secret: "s", gid: "g")))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(object["id"] as? String, "7")
        XCTAssertEqual(object["method"] as? String, "aria2.tellStatus")
        let params = try XCTUnwrap(object["params"] as? [Any])
        XCTAssertEqual(params.first as? String, "token:s")
        XCTAssertEqual(params[1] as? String, "g")
        XCTAssertEqual(params[2] as? [String], Aria2RPC.statusKeys)

        let add = Aria2RPC.addParams(secret: "s", uri: "magnet:?xt=urn:btih:AA", directory: "/tmp/dl")
        XCTAssertEqual(add[0] as? String, "token:s")
        XCTAssertEqual(add[1] as? [String], ["magnet:?xt=urn:btih:AA"])
        XCTAssertEqual(add[2] as? [String: String], ["dir": "/tmp/dl"])
        XCTAssertEqual(Aria2RPC.gidParams(secret: "s", gid: "g") as? [String], ["token:s", "g"])
    }

    // MARK: - Hub ↔ engine (fake engine: no process, no transfer)

    /// The row's whole life: magnet in, CONNECTING with no size, then the engine's real numbers, then done.
    /// Also witnesses that cancelling drops both GIDs and that the engine stops when the last row goes.
    @MainActor
    func testTorrentRowFollowsTheEngineFromMagnetToCompletion() async {
        let engine = FakeTorrentEngine(available: true)
        engine.metadataStatus = Self.metadataStatus(seeders: 3, connections: 44)
        let service = DownloadManagerService(torrent: engine)

        let magnet = "magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c&dn=Big+Buck+Bunny"
        XCTAssertTrue(service.addDownload(input: magnet))
        await waitUntil({ engine.addedURIs == [magnet] }, "the engine was never handed the magnet")

        let id = try? XCTUnwrap(service.items.first { $0.type == .torrent }?.id)
        guard let id else { return }   // the failed unwrap already recorded the failure
        await waitUntil({ service.items.first { $0.id == id }?.state == .initializing })
        XCTAssertEqual(service.items.first { $0.id == id }?.totalBytes, 0)
        XCTAssertEqual(service.items.first { $0.id == id }?.name, "Big Buck Bunny")   // the magnet's dn

        // The engine has followed the magnet into the payload: the row now reports the real transfer.
        engine.payloadStatus = Self.payloadStatus()
        service.refreshTorrents()
        await waitUntil({ service.items.first { $0.id == id }?.totalBytes == 276_445_467 },
                        "the row never picked up the payload")
        guard let item = service.items.first(where: { $0.id == id }) else { return XCTFail("row vanished") }
        XCTAssertEqual(item.name, "Big Buck Bunny")
        XCTAssertEqual(item.seeders, 10)
        XCTAssertEqual(item.peers, 44)
        XCTAssertEqual(item.downloadSpeedBps, 1_884_659)
        XCTAssertEqual(item.uploadSpeedBps, 0)
        XCTAssertEqual(item.state, .active)
        XCTAssertEqual(item.etaSeconds, (276_445_467 - 3_455_259) / 1_884_659)
        XCTAssertEqual(item.destinationURL?.path, "/tmp/kkt-wire/dl/Big Buck Bunny")
        XCTAssertEqual(item.infoHash, "DD8255ECDC7CA55FB0BBF81323D87062DB1F6D1C")

        service.pause(id: id)
        await waitUntil({ engine.pausedGIDs == ["payloadgid"] }, "pause never reached the engine")
        service.resume(id: id)
        await waitUntil({ engine.unpausedGIDs == ["payloadgid"] }, "resume never reached the engine")

        engine.payloadStatus = Self.payloadStatus(state: .completed, completedBytes: 276_445_467, downloadBps: 0)
        service.refreshTorrents()
        await waitUntil({ service.items.first { $0.id == id }?.state == .completed }, "the completed row never settled")
        XCTAssertNotNil(service.items.first { $0.id == id }?.completedAt)

        service.cancel(id: id)
        await waitUntil({ engine.removedGIDs.sorted() == ["metagid", "payloadgid"] }, "the engine GIDs were never dropped")
        XCTAssertTrue(service.items.filter { $0.type == .torrent }.isEmpty)
        // The engine is stopped once the last torrent row is gone (after its removals landed).
        await waitUntil({ engine.shutdowns == 1 }, "the engine was left running")
    }

    /// Opt-in end-to-end witness for the real thing (`KK_LIVE_TORRENT=1`): detection, spawn, RPC and the
    /// magnet→payload hand-off against `aria2c` on this machine. Skipped by default — it starts a real
    /// transfer, which an ordinary test run must never do.
    @MainActor
    func testLiveEngineFollowsAMagnetIntoItsPayload() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KK_LIVE_TORRENT"] == "1",
                          "set KK_LIVE_TORRENT=1 to drive the real aria2c")
        let engine = TorrentEngine.shared
        try XCTSkipUnless(engine.isAvailable, "aria2c is not installed")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kkt-live-torrent")
        try? FileManager.default.removeItem(at: directory)
        defer {
            engine.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }

        let magnet = "magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c&dn=Big+Buck+Bunny&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337"
        let gid = try await engine.add(uri: magnet, directory: directory)

        var payload: Aria2RPC.Status?
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline, payload == nil {
            if let child = (try? await engine.status(gid: gid))?.payloadGID,
               let followed = try? await engine.status(gid: child), followed.totalBytes > 0 {
                payload = followed
                break
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        let followed = try XCTUnwrap(payload, "the engine never followed the magnet into a payload")
        XCTAssertEqual(followed.infoHash?.uppercased(), "DD8255ECDC7CA55FB0BBF81323D87062DB1F6D1C")
        XCTAssertFalse(followed.name?.isEmpty ?? true)
        XCTAssertGreaterThan(followed.totalBytes, 1_000_000)
        XCTAssertFalse(followed.filePaths.isEmpty)

        await engine.remove(gid: gid)
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    /// Opt-in end-to-end witness for the delivered artifact (`KK_LIVE_TORRENT=1`): the magnet goes in
    /// through `addDownload` — the same call the notch hub's input bar makes — and comes out as a row with
    /// the engine's real numbers. Cleans up after itself in the user's Downloads folder.
    @MainActor
    func testLiveHubDownloadsAMagnetThroughTheRealEngine() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KK_LIVE_TORRENT"] == "1",
                          "set KK_LIVE_TORRENT=1 to drive the real aria2c")
        try XCTSkipUnless(TorrentEngine.shared.isAvailable, "aria2c is not installed")

        let service = DownloadManagerService()   // the shared engine, exactly what the hub uses
        let magnet = "magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c&dn=Big+Buck+Bunny&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337"
        XCTAssertTrue(service.addDownload(input: magnet))
        defer { service.release() }

        await waitUntil({ service.items.first { $0.type == .torrent }?.totalBytes ?? 0 > 0 },
                        "the hub never showed the torrent's real size", timeout: 60)
        guard let row = service.items.first(where: { $0.type == .torrent }) else { return XCTFail("no torrent row") }
        XCTAssertEqual(row.infoHash, "DD8255ECDC7CA55FB0BBF81323D87062DB1F6D1C")
        XCTAssertEqual(row.name, "Big Buck Bunny")
        XCTAssertGreaterThan(row.totalBytes, 1_000_000)
        XCTAssertTrue([.active, .completed].contains(row.state))

        service.cancel(id: row.id)
        await waitUntil({ service.items.filter { $0.type == .torrent }.isEmpty }, "the row was not dropped")
        // The engine must not outlive the hub (the live run found it doing exactly that before
        // `--stop-with-process` was added).
        await waitUntil({ Self.engineChildCount() == 0 }, "the engine outlived the hub", timeout: 10)

        if let target = row.destinationURL { try? FileManager.default.removeItem(at: target) }
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: row.destinationURL?.path ?? "").appendingPathExtension("aria2"))
    }

    /// How many `aria2c` children this process still has — the orphan check.
    private static func engineChildCount() -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-P", String(getpid()), "-f", "aria2c"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return 0 }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.split(separator: "\n").filter { !$0.isEmpty }.count
    }

    // MARK: - Helpers

    /// Payloads captured from a live `aria2c` 1.37.0 (2026-10-16) fetching a real magnet.
    private static let metadataPayload: [String: Any] = [
        "bittorrent": ["announceList": [["udp://tracker.opentrackr.org:1337"], ["udp://explodie.org:6969"]]],
        "completedLength": "0", "connections": "44", "downloadSpeed": "0",
        "files": [["completedLength": "0", "index": "1", "length": "21307",
                   "path": "[METADATA]Big+Buck+Bunny", "selected": "true", "uris": []]],
        "gid": "ece738d8a6098dd9", "infoHash": "dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c",
        "numSeeders": "3", "seeder": "false", "status": "active",
        "totalLength": "21307", "uploadSpeed": "0"
    ]

    private static let payload: [String: Any] = [
        "bittorrent": ["announceList": [["udp://tracker.opentrackr.org:1337"]],
                       "info": ["name": "Big Buck Bunny"], "mode": "multi"],
        "completedLength": "3455259", "connections": "44", "downloadSpeed": "1884659",
        "files": [
            ["completedLength": "0", "index": "1", "length": "140",
             "path": "/tmp/kkt-wire/dl/Big Buck Bunny/Big Buck Bunny.en.srt", "selected": "true", "uris": []],
            ["completedLength": "2097152", "index": "2", "length": "276134947",
             "path": "/tmp/kkt-wire/dl/Big Buck Bunny/Big Buck Bunny.mp4", "selected": "true", "uris": []],
            ["completedLength": "145691", "index": "3", "length": "310380",
             "path": "/tmp/kkt-wire/dl/Big Buck Bunny/poster.jpg", "selected": "true", "uris": []]
        ],
        "gid": "40d4fc03ecf33ee3", "infoHash": "dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c",
        "numSeeders": "10", "seeder": "false", "status": "active",
        "totalLength": "276445467", "uploadSpeed": "0"
    ]

    /// The magnet's own GID once the engine has followed it — `payloadGID` set, no payload numbers yet.
    private static func metadataStatus(seeders: Int, connections: Int) -> Aria2RPC.Status {
        Aria2RPC.Status(gid: "metagid", payloadGID: "payloadgid", infoHash: nil, name: nil,
                        state: .initializing, totalBytes: 0, completedBytes: 0, downloadBps: 0,
                        uploadBps: 0, connections: connections, seeders: seeders, filePaths: [])
    }

    private static func payloadStatus(state: DownloadItemState = .active, completedBytes: Int64 = 3_455_259,
                                     downloadBps: Int64 = 1_884_659) -> Aria2RPC.Status {
        Aria2RPC.Status(gid: "payloadgid", payloadGID: nil,
                        infoHash: "dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c",
                        name: "Big Buck Bunny", state: state, totalBytes: 276_445_467,
                        completedBytes: completedBytes, downloadBps: downloadBps, uploadBps: 0,
                        connections: 44, seeders: 10,
                        filePaths: ["/tmp/kkt-wire/dl/Big Buck Bunny/Big Buck Bunny.en.srt",
                                    "/tmp/kkt-wire/dl/Big Buck Bunny/Big Buck Bunny.mp4",
                                    "/tmp/kkt-wire/dl/Big Buck Bunny/poster.jpg"])
    }

    /// Spins the main actor until `condition` holds, then asserts it — the hub applies engine responses in
    /// its own `Task`s, so a test cannot read the result synchronously. The `await` is why `XCTAssertTrue`
    /// cannot wrap the call (an autoclosure cannot be async), so the assert lives in here.
    private func waitUntil(_ condition: () -> Bool, _ message: String = "", timeout: TimeInterval = 3,
                           file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !condition() {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(condition(), message, file: file, line: line)
    }
}

/// A BitTorrent engine with no process behind it: hands out canned statuses so the hub's magnet →
/// payload → completion path is testable without spawning `aria2c` or transferring anything.
@MainActor
private final class FakeTorrentEngine: TorrentEngineClient {
    var isAvailable: Bool
    var metadataStatus: Aria2RPC.Status?
    var payloadStatus: Aria2RPC.Status?
    private(set) var addedURIs: [String] = []
    private(set) var removedGIDs: [String] = []
    private(set) var pausedGIDs: [String] = []
    private(set) var unpausedGIDs: [String] = []
    private(set) var shutdowns = 0

    init(available: Bool) { isAvailable = available }

    func add(uri: String, directory: URL) async throws -> String {
        addedURIs.append(uri)
        return "metagid"
    }

    func status(gid: String) async throws -> Aria2RPC.Status {
        guard let status = gid == "metagid" ? metadataStatus : payloadStatus else {
            throw TorrentEngineError.engine("GID \(gid) is not found")
        }
        return status
    }

    func pause(gid: String) async throws { pausedGIDs.append(gid) }
    func unpause(gid: String) async throws { unpausedGIDs.append(gid) }
    func remove(gid: String) async { removedGIDs.append(gid) }
    func shutdown() { shutdowns += 1 }
}
