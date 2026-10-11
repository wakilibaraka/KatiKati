import XCTest
@testable import KatiKati

@MainActor
final class SyncPassSchedulerTests: XCTestCase {
    private var timers: [(work: () -> Void, cancelled: Bool)] = []
    private var finish: (() -> Void)?
    private var passes = 0

    private func make() -> SyncPassScheduler {
        SyncPassScheduler(delay: 1.5, schedule: { [unowned self] _, work in
            let i = self.timers.count
            self.timers.append((work, false))
            return { self.timers[i].cancelled = true }
        }, perform: { [unowned self] done in
            self.passes += 1
            self.finish = done
        })
    }

    private func fireLatest() {
        guard let i = timers.lastIndex(where: { !$0.cancelled }) else { return }
        timers[i].cancelled = true
        timers[i].work()
    }

    func testBurstOfRequestsRunsOnePassAfterQuiet() {
        let s = make()
        s.request(); s.request(); s.request()
        XCTAssertEqual(passes, 0)
        fireLatest()
        XCTAssertEqual(passes, 1)
        XCTAssertTrue(s.isRunning)
        finish?()
        XCTAssertFalse(s.isRunning)
        XCTAssertEqual(passes, 1)
    }

    func testRequestDuringPassCollapsesIntoOneFollowUp() {
        let s = make()
        s.request(); fireLatest()
        s.request(); s.request()
        finish?()
        XCTAssertEqual(passes, 1, "follow-up is debounced, not immediate")
        fireLatest()
        XCTAssertEqual(passes, 2)
        finish?()
        XCTAssertFalse(s.isRunning)
    }

    func testCancelDropsPendingPass() {
        let s = make()
        s.request()
        s.cancel()
        fireLatest()
        XCTAssertEqual(passes, 0)
    }
}
