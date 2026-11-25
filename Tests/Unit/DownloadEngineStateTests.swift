import XCTest
@testable import KatiKati

final class DownloadEngineStateTests: XCTestCase {
    private let mib: Int64 = 1_048_576

    private func plan(segments: Int, sizeInMiB: Int64) -> DownloadSegmentPlan {
        DownloadSegmentPlanner.plan(contentLength: sizeInMiB * mib, acceptRanges: true, segmentCount: segments)
    }

    func testConcurrencyStaysInsideThePolicy() {
        var state = DownloadEngineState(plan: plan(segments: 4, sizeInMiB: 32),
                                        policy: DownloadEnginePolicy(connections: 2))
        XCTAssertEqual(state.next(), .start(index: 0))
        XCTAssertEqual(state.next(), .start(index: 1))
        XCTAssertEqual(state.next(), .wait, "two connections are open; nothing else may start")
        XCTAssertEqual(state.inFlight, [0, 1])
    }

    func testQueueIsServedBeforeAnySegmentIsSplit() {
        var state = DownloadEngineState(plan: plan(segments: 4, sizeInMiB: 32),
                                        policy: DownloadEnginePolicy(connections: 2))
        _ = state.next()   // start 0
        _ = state.next()   // start 1
        state.finish(index: 0)
        XCTAssertEqual(state.next(freeSlot: true), .start(index: 2),
                       "an idle connection takes the next queued segment before splitting anything")
    }

    func testFinishedWorkerStealsTheTailOfTheLargestRemainingSegment() {
        // Two segments on two connections: once one lands there is nothing queued, so the engine splits the
        // other instead of leaving the connection idle.
        var state = DownloadEngineState(plan: plan(segments: 2, sizeInMiB: 16),
                                        policy: DownloadEnginePolicy(connections: 2))
        _ = state.next()   // start 0
        _ = state.next()   // start 1
        let oldEnd = state.plan.segments.first { $0.index == 1 }!.end
        state.finish(index: 0)
        let action = state.next(freeSlot: true)
        guard case .steal(let victim, let tail) = action else {
            return XCTFail("expected a steal, got \(action)")
        }
        XCTAssertEqual(victim, 1)
        let tailSegment = state.plan.segments.first { $0.index == tail }
        let victimSegment = state.plan.segments.first { $0.index == victim }
        XCTAssertEqual(tailSegment?.end, oldEnd, "the tail keeps the victim's original end")
        XCTAssertEqual(tailSegment?.length, victimSegment?.length, "the remaining range is halved")
        XCTAssertEqual(tailSegment.map { $0.start + $0.length }, oldEnd + 1, "the two ranges meet with no gap")
        XCTAssertTrue(state.inFlight.contains(tail))
        XCTAssertTrue(state.queued.contains(victim), "the shortened victim is fetched again")
    }

    func testNoStealWhenTheRemainingTailIsTooSmall() {
        var state = DownloadEngineState(plan: plan(segments: 2, sizeInMiB: 3),
                                        policy: DownloadEnginePolicy(connections: 2))
        _ = state.next()
        _ = state.next()
        state.finish(index: 0)
        XCTAssertEqual(state.next(freeSlot: true), .wait,
                       "a tail under twice the minimum segment size is not worth splitting")
    }

    func testStallTickerReconnectsTheSegmentThatIsFurthestBehindThenGivesUp() {
        var state = DownloadEngineState(plan: plan(segments: 2, sizeInMiB: 16),
                                        policy: DownloadEnginePolicy(connections: 2, reconnectAttempts: 1))
        let start = Date(timeIntervalSince1970: 5_000)
        _ = state.next()
        _ = state.next()
        state.progress(index: 0, totalWritten: 4 * mib, at: start)
        state.progress(index: 1, totalWritten: 1 * mib, at: start.addingTimeInterval(1))
        XCTAssertEqual(state.stalledAction(now: start.addingTimeInterval(2)), nil, "still moving")
        XCTAssertEqual(state.stalledAction(now: start.addingTimeInterval(12)), .start(index: 1),
                       "the segment furthest behind is reconnected first")
        XCTAssertEqual(state.stalledAction(now: start.addingTimeInterval(30)), nil,
                       "the reconnect budget is spent; the transfer must fail visibly instead")
    }

    func testThroughputWidensAndNarrowsTheConnectionRamp() {
        var state = DownloadEngineState(plan: plan(segments: 8, sizeInMiB: 64),
                                        policy: DownloadEnginePolicy(connections: 8))
        XCTAssertEqual(state.connections, 8)
        state.ramp(recent: 100, peak: 110)
        XCTAssertEqual(state.connections, 8, "already at the policy ceiling")
        state.ramp(recent: 5, peak: 110)
        XCTAssertEqual(state.connections, 7)
        state.ramp(recent: 5, peak: 110)
        XCTAssertEqual(state.connections, 6)
        state.ramp(recent: 110, peak: 110)
        XCTAssertEqual(state.connections, 8)
    }

    func testWritePositionIsFlatPerSegment() {
        var state = DownloadEngineState(plan: plan(segments: 4, sizeInMiB: 32))
        let third = state.plan.segments[2]
        XCTAssertEqual(state.writeOffset(for: 2), third.start, "an untouched segment writes at its own start")
        state.progress(index: 2, totalWritten: 4 * mib)
        XCTAssertEqual(state.writeOffset(for: 2), third.start + 4 * mib,
                       "a segment writes at start + written, not at the end of the file")
    }

    func testResumeRecordSkipsFinishedSegments() {
        let plan = plan(segments: 4, sizeInMiB: 32)
        let first = plan.segments[0]
        var state = DownloadEngineState(plan: plan, completed: [0: first.length])
        XCTAssertFalse(state.queued.contains(0), "a segment already on disk is not fetched again")
        XCTAssertEqual(state.next(), .start(index: 1))
    }

    func testCompletePlanAsksForAssembly() {
        let plan = plan(segments: 4, sizeInMiB: 32)
        let done = Dictionary(uniqueKeysWithValues: plan.segments.map { ($0.index, $0.length) })
        var state = DownloadEngineState(plan: plan, completed: done)
        XCTAssertTrue(state.isComplete)
        XCTAssertEqual(state.next(), .assemble)
    }
}
