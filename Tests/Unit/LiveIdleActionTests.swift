import XCTest
@testable import KatiKati

final class LiveIdleActionTests: XCTestCase {
    func testIdleActionsAreFocusTimerKeepAwakeInOrder() {
        XCTAssertEqual(LiveIdleAction.allCases, [.focus, .timer, .keepAwake])
        XCTAssertEqual(LiveIdleAction.allCases.map(\.symbolName), ["brain.head.profile", "timer", "cup.and.saucer"])
    }

    func testOnlyTheClockFallbackShowsIdleActions() {
        for kind in LiveActivityKind.allCases {
            XCTAssertEqual(LiveIdleAction.showsIdleActions(for: kind), kind == .clock, "\(kind)")
        }
    }
}

extension LiveIdleActionTests {
    func testRingProgressClampsAndIsNilWithoutProgress() {
        let focus = LiveActivity(kind: .focus, content: .focus(FocusContent(phase: .focus, remaining: 10, progress: 1.4, completedInCycle: 0)))
        XCTAssertEqual(focus.ringProgress, 1)
        let timer = LiveActivity(kind: .timer, content: .timer(TimerContent(remaining: 5, total: 10, progress: 0.5)))
        XCTAssertEqual(timer.ringProgress, 0.5)
        let stream = LiveActivity(kind: .music, content: .music(MusicContent(title: "t", artist: nil, progress: nil, hasPrevious: false, hasNext: false)))
        XCTAssertNil(stream.ringProgress)
        XCTAssertNil(LiveActivity(kind: .clock, content: .clock).ringProgress)
    }
}
