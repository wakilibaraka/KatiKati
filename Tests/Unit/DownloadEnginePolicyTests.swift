import XCTest
@testable import KatiKati

final class DownloadEnginePolicyTests: XCTestCase {
    func testConnectionsClampToTheSupportedRange() {
        XCTAssertEqual(DownloadEnginePolicy(connections: 0).connections, 1)
        XCTAssertEqual(DownloadEnginePolicy(connections: 33).connections, 32)
        XCTAssertEqual(DownloadEnginePolicy(connections: 32).connections, 32)
        XCTAssertEqual(DownloadEnginePolicy(connections: 12).connections, 12)
        XCTAssertEqual(DownloadEnginePolicy.standard.connections, 8)
    }

    func testStallKnobsClampToUsefulValues() {
        let policy = DownloadEnginePolicy(connections: 4, stallWindow: 0, stallRateFraction: 2, reconnectAttempts: 99)
        XCTAssertEqual(policy.stallWindow, 2)
        XCTAssertEqual(policy.stallRateFraction, 0.9)
        XCTAssertEqual(policy.reconnectAttempts, 8)
    }

    func testSegmentCountIsBoundedByBothThePolicyAndTheByteBudget() {
        let policy = DownloadEnginePolicy(connections: 16)
        XCTAssertEqual(policy.segmentCount(forContentLength: 8 * 1_048_576), 8)
        XCTAssertEqual(policy.segmentCount(forContentLength: 2 * 1_048_576), 2)
        XCTAssertEqual(policy.segmentCount(forContentLength: 100), 1)
        XCTAssertEqual(policy.segmentCount(forContentLength: nil), 1)
        XCTAssertLessThanOrEqual(policy.segmentCount(forContentLength: 8_000 * 1_048_576), 16)
    }

    func testPlannerHonoursARequestedCountAndCapsAtThirtyTwo() {
        let plan = DownloadSegmentPlanner.plan(contentLength: 64 * 1_048_576, acceptRanges: true, segmentCount: 32)
        XCTAssertEqual(plan.segments.count, 32)
        XCTAssertEqual(plan.segments.first?.start, 0)
        XCTAssertEqual(plan.segments.last?.end, 64 * 1_048_576 - 1)
        let capped = DownloadSegmentPlanner.plan(contentLength: 128 * 1_048_576, acceptRanges: true, segmentCount: 64)
        XCTAssertEqual(capped.segments.count, 32)
    }

    func testStallDetectorNoticesAQuietStreamAndStopsAfterItsBudget() {
        var detector = DownloadStallDetector(policy: DownloadEnginePolicy(connections: 4, reconnectAttempts: 2))
        let start = Date(timeIntervalSince1970: 1_000)
        // Fast burst, then nothing: peak is high, the recent rate collapses.
        detector.record(bytes: 0, at: start)
        detector.record(bytes: 4_000_000, at: start.addingTimeInterval(1))
        XCTAssertFalse(detector.isStalled(now: start.addingTimeInterval(1)))
        XCTAssertTrue(detector.isStalled(now: start.addingTimeInterval(9)),
                      "no bytes for eight seconds after a fast burst is a stall")
        XCTAssertTrue(detector.noteReconnect())
        XCTAssertTrue(detector.noteReconnect())
        XCTAssertFalse(detector.noteReconnect(), "the budget is two reconnects, then the failure is visible")
    }

    func testStallDetectorIgnoresASteadyStream() {
        var detector = DownloadStallDetector(policy: .standard)
        let start = Date(timeIntervalSince1970: 2_000)
        for step in 0...10 {
            detector.record(bytes: Int64(step) * 1_000_000, at: start.addingTimeInterval(Double(step)))
        }
        XCTAssertFalse(detector.isStalled(now: start.addingTimeInterval(10)))
    }

    func testResumeRecordRoundTripsAndIsRemoved() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadResumeTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        let record = DownloadResumeRecord(source: "https://example.com/a.bin",
                                          destination: "/tmp/a.bin", totalBytes: 8_000,
                                          isMultiSegment: true, completed: [0: 4_000, 1: 1_000])
        record.write(id: id, in: directory)
        XCTAssertEqual(DownloadResumeRecord.read(id: id, in: directory), record)
        DownloadResumeRecord.remove(id: id, in: directory)
        XCTAssertNil(DownloadResumeRecord.read(id: id, in: directory))
    }

    func testSmartFoldersRouteMediaAndLeaveEverythingElseInDownloads() {
        XCTAssertEqual(DownloadDestinationPolicy.folderName(for: "clip.MKV"), "Movies")
        XCTAssertEqual(DownloadDestinationPolicy.folderName(for: "song.flac"), "Music")
        XCTAssertEqual(DownloadDestinationPolicy.folderName(for: "shot.heic"), "Pictures")
        XCTAssertNil(DownloadDestinationPolicy.folderName(for: "installer.dmg"))
        XCTAssertNil(DownloadDestinationPolicy.folderName(for: "README"))
    }
}
