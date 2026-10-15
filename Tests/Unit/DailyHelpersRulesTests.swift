import XCTest
@testable import KatiKati

// Phase 36 — pure rules for the small daily helpers.
final class DailyHelpersRulesTests: XCTestCase {
    func testCapsLockFirstReadingIsBaselineThenTransitionsFire() {
        var t = CapsLockTracker()
        XCTAssertNil(t.update(isOn: true))
        XCTAssertNil(t.update(isOn: true))
        XCTAssertEqual(t.update(isOn: false), .capsLockOff)
        XCTAssertEqual(t.update(isOn: true), .capsLockOn)
    }

    func testBatteryNudgesOnceAtEightyThenFullAndRearmOnUnplug() {
        func b(_ level: Int, plugged: Bool = true, charging: Bool = true) -> BatteryStatus {
            BatteryStatus(level: level, isCharging: charging, isPluggedIn: plugged)
        }
        var rule = BatteryNoticeRule()
        XCTAssertNil(rule.update(b(60)))                    // seed
        XCTAssertNil(rule.update(b(79)))
        XCTAssertEqual(rule.update(b(80)), .batteryHigh)
        XCTAssertNil(rule.update(b(81)))                    // once only
        XCTAssertEqual(rule.update(b(100, charging: false)), .batteryFull)
        XCTAssertNil(rule.update(b(100, charging: false)))
        XCTAssertNil(rule.update(b(90, plugged: false, charging: false)))   // unplug re-arms
        XCTAssertEqual(rule.update(b(85)), .batteryHigh)
    }

    func testBatteryLaunchAboveThresholdStaysQuiet() {
        var rule = BatteryNoticeRule()
        XCTAssertNil(rule.update(BatteryStatus(level: 90, isCharging: true, isPluggedIn: true)))
        XCTAssertNil(rule.update(BatteryStatus(level: 92, isCharging: true, isPluggedIn: true)))
    }
}
