import XCTest
@testable import KatiKati

final class ShortcutsTests: XCTestCase {
    func testTriggerRoundTrip() {
        for c in ShortcutChord.allCases { XCTAssertEqual(ShortcutTrigger.parse(ShortcutTrigger.chord(c).serialized), .chord(c)) }
        for k in ShortcutTapKey.allCases { XCTAssertEqual(ShortcutTrigger.parse(ShortcutTrigger.doubleTap(k).serialized), .doubleTap(k)) }
        XCTAssertEqual(ShortcutTrigger.parse("off"), .off)
        XCTAssertNil(ShortcutTrigger.parse("chord:bogus"))
        XCTAssertNil(ShortcutTrigger.parse(nil))
    }

    func testGlyphs() {
        XCTAssertEqual(ShortcutChord.optionSpace.glyphs, "⌥Space")
        XCTAssertEqual(ShortcutChord.controlShiftSpace.glyphs, "⌃⇧Space")
        XCTAssertEqual(ShortcutChord.controlOptionSpace.glyphs, "⌃⌥Space")
    }

    func testDefaultsAreDistinct() {
        let b = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultTrigger) })
        XCTAssertTrue(ShortcutConflicts.duplicated(b).isEmpty)
    }

    func testConflicts() {
        let b: [ShortcutAction: ShortcutTrigger] = [.launcher: .chord(.controlSpace), .pinboard: .chord(.controlSpace), .keepAwake: .off, .quickSettings: .off]
        XCTAssertEqual(ShortcutConflicts.duplicated(b), [.launcher, .pinboard])
    }

    private func tap(_ d: inout ModifierDoubleTapDetector, _ code: UInt16, at t: TimeInterval, hold: TimeInterval = 0.05) -> ShortcutTapKey? {
        _ = d.modifierChanged(keyCode: code, isDown: true, time: t)
        return d.modifierChanged(keyCode: code, isDown: false, time: t + hold)
    }

    func testDoubleTapFires() {
        var d = ModifierDoubleTapDetector()
        XCTAssertNil(tap(&d, 61, at: 0))
        XCTAssertEqual(tap(&d, 61, at: 0.2), .rightOption)
        XCTAssertNil(tap(&d, 61, at: 0.3), "fired taps are consumed")
    }

    func testSlowSecondTapDoesNotFire() {
        var d = ModifierDoubleTapDetector()
        XCTAssertNil(tap(&d, 55, at: 0))
        XCTAssertNil(tap(&d, 55, at: 0.6))
    }

    func testLongHoldIsNotATap() {
        var d = ModifierDoubleTapDetector()
        XCTAssertNil(tap(&d, 59, at: 0, hold: 0.5))
        XCTAssertNil(tap(&d, 59, at: 0.7))
    }

    func testOtherKeyBreaksSequence() {
        var d = ModifierDoubleTapDetector()
        XCTAssertNil(tap(&d, 58, at: 0))
        d.reset()
        XCTAssertNil(tap(&d, 58, at: 0.2))
    }

    func testLeftAndRightAreDistinct() {
        var d = ModifierDoubleTapDetector()
        XCTAssertNil(tap(&d, 58, at: 0))
        XCTAssertNil(tap(&d, 61, at: 0.2))
    }
}
