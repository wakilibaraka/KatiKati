import XCTest
@testable import KatiKati

final class QuickAddStateTests: XCTestCase {
    func testSaveOnlyEnabledInCaptureWithText() {
        var s = QuickAddState()
        XCTAssertFalse(s.canSave, "menu stage")
        s.choose(.note)
        XCTAssertFalse(s.canSave, "no text")
        s.text = "   \n"
        XCTAssertFalse(s.canSave, "whitespace only")
        s.text = " buy milk "
        XCTAssertTrue(s.canSave)
        XCTAssertEqual(s.trimmed, "buy milk")
    }

    func testSaveLifecycleAndBackReset() {
        var s = QuickAddState()
        s.choose(.reminder); s.text = "call"; s.due = .tomorrow
        XCTAssertTrue(s.beginSave())
        XCTAssertEqual(s.save, .saving)
        XCTAssertFalse(s.beginSave(), "no double save")
        s.finishSave(success: false)
        XCTAssertEqual(s.save, .idle, "failure lets the user retry")
        XCTAssertTrue(s.beginSave()); s.finishSave(success: true)
        XCTAssertEqual(s.save, .saved)
        s.back()
        XCTAssertEqual(s, QuickAddState())
    }

    func testDueDates() {
        let cal = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var s = QuickAddState()
        XCTAssertNil(s.dueDate(now: now, calendar: cal))
        s.due = .tomorrow
        XCTAssertEqual(s.dueDate(now: now, calendar: cal), cal.date(byAdding: .day, value: 1, to: now))
    }
}
