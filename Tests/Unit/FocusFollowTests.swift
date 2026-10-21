import XCTest
@testable import KatiKati

/// 54e — the raise table: never mid-drag, never while our own panel is key, never our own window, never
/// the app already in front, and at most one raise per 120 ms.
final class FocusFollowPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func allows(target: pid_t? = 42, frontmost: pid_t? = 7, buttonDown: Bool = false,
                        ownPanel: Bool = false, lastRaise: Date? = nil) -> Bool {
        var policy = FocusFollowPolicy()
        policy.lastRaiseAt = lastRaise
        return policy.allowsRaise(targetPID: target, frontmostPID: frontmost, ownPID: 99,
                                  mouseButtonDown: buttonDown, ownPanelIsKey: ownPanel, now: now)
    }

    func testItRaisesAnotherAppsWindow() {
        XCTAssertTrue(allows())
    }

    func testItNeverActsMidDragOrWhileOurPanelHasTheKeyboard() {
        XCTAssertFalse(allows(buttonDown: true))
        XCTAssertFalse(allows(ownPanel: true))
    }

    func testItIgnoresOurOwnWindowsNothingAndTheAppAlreadyInFront() {
        XCTAssertFalse(allows(target: 99))
        XCTAssertFalse(allows(target: nil))
        XCTAssertFalse(allows(target: 7))
    }

    func testAtMostOneRaisePer120Milliseconds() {
        XCTAssertFalse(allows(lastRaise: now.addingTimeInterval(-0.05)))
        XCTAssertFalse(allows(lastRaise: now.addingTimeInterval(-0.119)))
        XCTAssertTrue(allows(lastRaise: now.addingTimeInterval(-0.12)))
        XCTAssertTrue(allows(lastRaise: now.addingTimeInterval(-2)))
    }
}
