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

    // Phase 12 A4 — the Settings page's find field and the fifteen snap zones it lists.

    func testShortcutFindRule() {
        XCTAssertTrue(SettingsLayoutPane.shortcutMatches("Snap Left Half", query: ""), "an empty field lists everything")
        XCTAssertTrue(SettingsLayoutPane.shortcutMatches("Snap Left Half", query: "   "))
        XCTAssertTrue(SettingsLayoutPane.shortcutMatches("Snap Left Half", query: "left"))
        XCTAssertTrue(SettingsLayoutPane.shortcutMatches("Snap Left Half", query: "LEFT"))
        XCTAssertTrue(SettingsLayoutPane.shortcutMatches("Snap Left Half", query: " half "), "the query is trimmed")
        XCTAssertFalse(SettingsLayoutPane.shortcutMatches("Snap Left Half", query: "right"))
    }

    /// The defect class the pages kept hitting: two rows wearing one name. A find field makes it
    /// worse, since a search would return the wrong one of the pair.
    func testEveryShortcutHasItsOwnName() {
        let names = ShortcutAction.allCases.map(SettingsLayoutPane.shortcutActionName)
        XCTAssertTrue(names.allSatisfy { !$0.isEmpty }, "every action has a name")
        XCTAssertEqual(Set(names).count, names.count, "two actions must not show one name")
    }

    /// A zone that loses its row in Settings is a feature nobody can reach, so the page's four
    /// groups have to be every snap zone exactly once.
    func testSnapGroupsCoverEverySnapZoneOnce() {
        let listed = SettingsLayoutPane.snapHotkeyGroups.flatMap { $0 }
        let zones = ShortcutAction.allCases.filter { $0.snapPosition != nil } + [.snapNextDisplay]
        XCTAssertEqual(Set(listed), Set(zones))
        XCTAssertEqual(listed.count, zones.count, "no zone twice")
        XCTAssertEqual(zones.count, 16)
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

// MARK: - Phase 9d / 9e

final class ShortcutKeyTriggerTests: XCTestCase {
    func testKeyTriggerRoundTrips() {
        let t = ShortcutTrigger.key(ShortcutKey(keyCode: 2, modifiers: ShortcutKey.control | ShortcutKey.option))
        XCTAssertEqual(t.serialized, "key:3:2")
        XCTAssertEqual(ShortcutTrigger.parse("key:3:2"), t)
    }

    func testHyperTriggerRoundTrips() {
        XCTAssertEqual(ShortcutTrigger.hyper(13).serialized, "hyper:13")
        XCTAssertEqual(ShortcutTrigger.parse("hyper:13"), .hyper(13))
    }

    func testBareKeyAndUnknownKeyAreRejected() {
        XCTAssertNil(ShortcutTrigger.parse("key:0:2"))      // no modifier would steal typing
        XCTAssertNil(ShortcutTrigger.parse("key:3:999"))    // unnamed key
        XCTAssertNil(ShortcutTrigger.parse("hyper:999"))
        XCTAssertNil(ShortcutTrigger.parse("key:99:2"))
    }

    func testGlyphs() {
        XCTAssertEqual(ShortcutKey(keyCode: 2, modifiers: ShortcutKey.control | ShortcutKey.command).glyphs, "⌃⌘D")
    }

    func testNewActionsAreOffByDefaultWithUniqueHotKeyIDs() {
        let ids = ShortcutAction.allCases.map(\.hotKeyID)
        XCTAssertEqual(Set(ids).count, ids.count)
        for a in [ShortcutAction.drawer, .notchTools, .weather, .clock, .notchPageNext, .notchPagePrevious] { XCTAssertEqual(a.defaultTrigger, .off) }
    }

    func testConflictsAcrossTriggerKinds() {
        let k = ShortcutTrigger.key(ShortcutKey(keyCode: 2, modifiers: ShortcutKey.option))
        XCTAssertEqual(ShortcutConflicts.duplicated([.drawer: k, .weather: k, .clock: .hyper(8)]), [.drawer, .weather])
        XCTAssertEqual(ShortcutConflicts.duplicated([.drawer: .hyper(2), .weather: .hyper(2)]), [.drawer, .weather])
    }
}
