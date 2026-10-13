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
