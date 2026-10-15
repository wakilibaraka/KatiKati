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

    func testCleaningLockDurationIsClamped() {
        XCTAssertEqual(CleaningLock.clamped(1), 10)
        XCTAssertEqual(CleaningLock.clamped(60), 60)
        XCTAssertEqual(CleaningLock.clamped(9999), 300)
    }

    /// Phase 12 safety fix: a lock whose window passed while the app was not running (crash,
    /// force-quit) must release the keyboard instead of holding it.
    func testCleaningLockResumesOnlyInsideItsWindowAndOtherwiseFailsOpen() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(CleaningLock.launchDecision(deadline: nil, now: now), .release)
        XCTAssertEqual(CleaningLock.launchDecision(deadline: now.addingTimeInterval(-0.5), now: now), .release)
        XCTAssertEqual(CleaningLock.launchDecision(deadline: now, now: now), .release)
        XCTAssertEqual(CleaningLock.launchDecision(deadline: now.addingTimeInterval(42.4), now: now), .resume(seconds: 43))
        XCTAssertEqual(CleaningLock.launchDecision(deadline: now.addingTimeInterval(300), now: now), .resume(seconds: 300))
    }

    func testEjectPolicyOffersOnlyExternalLocalEjectables() {
        XCTAssertTrue(EjectPolicy.isOffered(isEjectable: true, isInternal: false, isLocal: true, isRoot: false))
        XCTAssertFalse(EjectPolicy.isOffered(isEjectable: true, isInternal: true, isLocal: true, isRoot: false))
        XCTAssertFalse(EjectPolicy.isOffered(isEjectable: true, isInternal: false, isLocal: false, isRoot: false))
        XCTAssertFalse(EjectPolicy.isOffered(isEjectable: true, isInternal: false, isLocal: true, isRoot: true))
        XCTAssertFalse(EjectPolicy.isOffered(isEjectable: false, isInternal: false, isLocal: true, isRoot: false))
    }

    func testPrivacyDotsEmptyOnlyWhenNothingInUse() {
        XCTAssertTrue(PrivacyDots().isEmpty)
        XCTAssertFalse(PrivacyDots(camera: true).isEmpty)
        XCTAssertFalse(PrivacyDots(microphone: true).isEmpty)
    }

    func testSnippetsParseAsSnippetKindWithNewlineEscape() {
        let list = CustomCommand.parseSnippets(";sig = Best,\\nSam\n;addr = 1 Main St")
        XCTAssertEqual(list.map(\.name), [";sig", ";addr"])
        XCTAssertEqual(list[0].target, "Best,\nSam")
        XCTAssertTrue(list.allSatisfy { $0.kind == .snippet })
        XCTAssertEqual(CustomCommand.matching(";s", in: list).count, 1)
    }
}
