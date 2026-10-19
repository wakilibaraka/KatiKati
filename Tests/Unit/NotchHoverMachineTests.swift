import XCTest
@testable import KatiKati

// The notch opens on a dwell, closes after a grace period, and never flickers on jitter.

final class NotchHoverMachineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func testFastPassDoesNotOpen() {
        var m = NotchHoverMachine()
        XCTAssertFalse(m.update(inTrigger: true, inKeepOpen: false, pinned: false, now: at(0)))
        XCTAssertFalse(m.update(inTrigger: true, inKeepOpen: false, pinned: false, now: at(0.05)))
        XCTAssertFalse(m.update(inTrigger: false, inKeepOpen: false, pinned: false, now: at(0.08)))
        XCTAssertNil(m.nextDeadline, "leaving cancels the pending open")
        XCTAssertFalse(m.update(inTrigger: true, inKeepOpen: false, pinned: false, now: at(0.5)), "the dwell timer restarts")
    }

    func testDwellOpens() {
        var m = NotchHoverMachine()
        _ = m.update(inTrigger: true, inKeepOpen: false, pinned: false, now: at(0))
        XCTAssertEqual(m.nextDeadline, at(0.12))
        XCTAssertTrue(m.update(inTrigger: true, inKeepOpen: false, pinned: false, now: at(0.12)))
    }

    func testCloseWaitsForGracePeriodAndReentryCancelsIt() {
        var m = NotchHoverMachine()
        m.forceOpen()
        XCTAssertTrue(m.update(inTrigger: false, inKeepOpen: false, pinned: false, now: at(0)))
        XCTAssertTrue(m.update(inTrigger: false, inKeepOpen: false, pinned: false, now: at(0.2)))
        XCTAssertTrue(m.update(inTrigger: false, inKeepOpen: true, pinned: false, now: at(0.22)), "re-entering holds it open")
        XCTAssertNil(m.nextDeadline)
        _ = m.update(inTrigger: false, inKeepOpen: false, pinned: false, now: at(1))
        XCTAssertFalse(m.update(inTrigger: false, inKeepOpen: false, pinned: false, now: at(1.25)))
    }

    func testPinnedHoldsOpenWhileCursorIsOutside() {
        var m = NotchHoverMachine()
        m.forceOpen()
        for i in 0..<10 {
            XCTAssertTrue(m.update(inTrigger: false, inKeepOpen: false, pinned: true, now: at(Double(i))))
        }
        XCTAssertTrue(m.update(inTrigger: false, inKeepOpen: false, pinned: false, now: at(10)), "grace period starts only after the pin ends")
        XCTAssertFalse(m.update(inTrigger: false, inKeepOpen: false, pinned: false, now: at(10.3)))
    }

    func testNoFlickerOnJitterAroundTheEdge() {
        var m = NotchHoverMachine()
        _ = m.update(inTrigger: true, inKeepOpen: false, pinned: false, now: at(0))
        _ = m.update(inTrigger: true, inKeepOpen: false, pinned: false, now: at(0.2))
        XCTAssertTrue(m.isOpen)
        var states: [Bool] = []
        for i in 0..<20 { // cursor wobbling in/out of the open zone every 40 ms
            let inside = i % 2 == 0
            states.append(m.update(inTrigger: false, inKeepOpen: inside, pinned: false, now: at(0.3 + Double(i) * 0.04)))
        }
        XCTAssertTrue(states.allSatisfy { $0 })
    }

    func testForceCloseAndZones() {
        var m = NotchHoverMachine()
        m.forceOpen(); m.forceClose()
        XCTAssertFalse(m.isOpen)
        let closed = CGRect(x: 800, y: 1080, width: 180, height: 32)
        XCTAssertTrue(NotchHoverZones.trigger(closedFrame: closed).contains(CGPoint(x: 890, y: 1112)), "cursor pinned to the very top edge counts")
        XCTAssertFalse(NotchHoverZones.trigger(closedFrame: closed).contains(CGPoint(x: 700, y: 1100)))
        let open = CGRect(x: 600, y: 922, width: 640, height: 190)
        XCTAssertTrue(NotchHoverZones.keepOpen(openFrame: open).contains(CGPoint(x: 595, y: 930)))
        XCTAssertFalse(NotchHoverZones.keepOpen(openFrame: open).contains(CGPoint(x: 560, y: 930)))
    }

    func testBehaviorDefaultsAndClamping() {
        let d = UserDefaults(suiteName: "NotchBehaviorTests")!
        d.removePersistentDomain(forName: "NotchBehaviorTests")
        XCTAssertEqual(NotchOpenMode.current(d), .hover)
        XCTAssertEqual(NotchBehavior.hoverDelay(d), 0.12)
        d.set(99.0, forKey: NotchBehavior.hoverDelayKey)
        d.set(0.0, forKey: NotchBehavior.closeDelayKey)
        d.set("bogus", forKey: NotchOpenMode.defaultsKey)
        XCTAssertEqual(NotchBehavior.hoverDelay(d), 1.0)
        XCTAssertEqual(NotchBehavior.closeDelay(d), 0.10)
        XCTAssertEqual(NotchOpenMode.current(d), .hover)
    }
}
