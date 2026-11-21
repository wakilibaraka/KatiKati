import Foundation
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

    // MARK: Slice MD-5 · ⌘ guard

    func testPointerActivityBreaksTheSequence() {
        var d = ModifierDoubleTapDetector()
        XCTAssertNil(tap(&d, 55, at: 0))
        d.pointerActivity()
        XCTAssertNil(tap(&d, 55, at: 0.2), "⌘+drag then a quick tap is not a double tap")
        XCTAssertEqual(tap(&d, 55, at: 0.35), .leftCommand,
                       "a clean pair after the break still fires")
    }

    func testCommandDoubleTapObeysTheDocumentedWindow() {
        var d = ModifierDoubleTapDetector()
        XCTAssertNil(tap(&d, 55, at: 0))
        XCTAssertNil(tap(&d, 55, at: 0.4), "release-to-release over 350 ms is not a double tap")

        var quick = ModifierDoubleTapDetector()
        XCTAssertNil(tap(&quick, 55, at: 0))
        XCTAssertEqual(tap(&quick, 55, at: 0.34), .leftCommand, "inside 350 ms it fires")
    }

    func testAHeldCommandIsNotATap() {
        var d = ModifierDoubleTapDetector()
        XCTAssertNil(tap(&d, 55, at: 0, hold: 0.4), "holding ⌘ is a hold, not a tap")
        XCTAssertNil(tap(&d, 55, at: 0.5))
    }
}

// MARK: - Phase 9d / 9e

final class WindowSwitcherShortcutTests: XCTestCase {
    func testDefaultIsOptionTab() {
        XCTAssertEqual(ShortcutAction.windowSwitcher.defaultTrigger.switcherKey,
                       ShortcutKey(keyCode: 48, modifiers: ShortcutKey.option))
        XCTAssertEqual(ShortcutAction.windowSwitcher.defaultTrigger.switcherKey?.glyphs, "⌥Tab")
    }

    func testOffMeansNoHotKey() {
        XCTAssertNil(ShortcutTrigger.off.switcherKey)
    }

    func testBindingsWithNothingToHoldFallBackToDefault() {
        let fallback = ShortcutKey(keyCode: 48, modifiers: ShortcutKey.option)
        XCTAssertEqual(ShortcutTrigger.doubleTap(.leftOption).switcherKey, fallback)
        XCTAssertEqual(ShortcutTrigger.hyper(13).switcherKey, fallback)
    }

    func testCustomKeyAndChordAreUsedAsBound() {
        let custom = ShortcutKey(keyCode: 50, modifiers: ShortcutKey.control)   // ⌃`
        XCTAssertEqual(ShortcutTrigger.key(custom).switcherKey, custom)
        XCTAssertEqual(ShortcutTrigger.chord(.optionShiftSpace).switcherKey,
                       ShortcutKey(keyCode: 49, modifiers: ShortcutKey.option | ShortcutKey.shift))
    }

    func testTabSurvivesSerialization() {
        let raw = ShortcutAction.windowSwitcher.defaultTrigger.serialized
        XCTAssertEqual(ShortcutTrigger.parse(raw), ShortcutAction.windowSwitcher.defaultTrigger)
    }
}

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

final class ShortcutOverhaulTests: XCTestCase {
    func testHoldAndFnRoundTrip() {
        for k in ShortcutTapKey.allCases {
            XCTAssertEqual(ShortcutTrigger.parse(ShortcutTrigger.hold(k).serialized), .hold(k))
        }
        XCTAssertEqual(ShortcutTrigger.parse("tap:fn"), .doubleTap(.fn))
    }

    func testChordAndKeyForSameCombinationOverlap() {
        let k = ShortcutTrigger.key(ShortcutKey(keyCode: 49, modifiers: ShortcutKey.option))
        XCTAssertEqual(ShortcutConflicts.duplicated([.drawer: .chord(.optionSpace), .weather: k]), [.drawer, .weather])
    }

    func testDefaultsPassTheValidator() {
        let defaults = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultTrigger) })
        for (a, t) in defaults where t != .off {
            XCTAssertEqual(ShortcutValidator.check(t, for: a, among: defaults), .ok, a.rawValue)
        }
    }

    func testReservedAndFnWarnButAreAllowed() {
        for t in [ShortcutTrigger.chord(.controlSpace), .chord(.commandSpace), .doubleTap(.fn), .hold(.fn)] {
            guard case .warn = ShortcutValidator.check(t, for: .weather, among: [:]) else { return XCTFail("\(t)") }
        }
    }

    func testBareLetterRejectedBareFunctionKeyAllowed() {
        XCTAssertEqual(ShortcutValidator.check(.key(ShortcutKey(keyCode: 0, modifiers: 0)), for: .weather, among: [:]),
                       .reject("Add a modifier (⌃ ⌥ ⇧ ⌘) to a plain key."))
        XCTAssertEqual(ShortcutValidator.check(.key(ShortcutKey(keyCode: 122, modifiers: 0)), for: .weather, among: [:]), .ok)
    }

    func testDrawerHasItsOwnIdAndDefault() {
        XCTAssertEqual(ShortcutAction.windowDrawer.defaultTrigger.switcherKey?.glyphs, "⌃⌥W")
        XCTAssertNotEqual(ShortcutAction.windowDrawer.hotKeyID, ShortcutAction.snapRightThird.hotKeyID)
    }
}

final class SwitcherRowStepTests: XCTestCase {
    func testRowStepMovesByColumnsAndStopsAtEdges() {
        XCTAssertEqual(WindowSwitcherModel.rowStep(selection: 1, count: 8, columns: 4, down: true), 5)
        XCTAssertEqual(WindowSwitcherModel.rowStep(selection: 5, count: 8, columns: 4, down: false), 1)
        XCTAssertEqual(WindowSwitcherModel.rowStep(selection: 6, count: 8, columns: 4, down: true), 6)
        XCTAssertEqual(WindowSwitcherModel.rowStep(selection: 2, count: 8, columns: 4, down: false), 2)
        XCTAssertEqual(WindowSwitcherModel.rowStep(selection: 3, count: 5, columns: 1, down: true), 4)
    }
}

final class PeekHoldTests: XCTestCase {
    func testQuickTapKeepsOpenLongHoldHides() {
        XCTAssertEqual(PeekHold.outcome(heldFor: 0.1), .keepOpen)
        XCTAssertEqual(PeekHold.outcome(heldFor: 0.6), .hide)
    }
    func testPeekHasNoDefaultKey() {
        XCTAssertEqual(ShortcutAction.peek.defaultTrigger, .off)
    }

    func testDictationActionAndTranscriptCleaning() {
        XCTAssertEqual(ShortcutAction.dictate.defaultTrigger, .off)
        XCTAssertEqual(DictationTranscript.cleaned("  hello   world \n\t from   dictation "), "hello world from dictation")
        XCTAssertEqual(DictationTranscript.cleaned("   "), "")
    }
}

// MARK: - Slice D: keyboard focus on the dock

final class DockFocusModelTests: XCTestCase {
    private func model(_ ids: [String] = ["a", "b", "c"]) -> DockFocusModel {
        DockFocusModel(ids: ids)
    }

    func testBeginFocusesTheFirstCardAndAnEmptyBarStaysOff() {
        var m = model()
        XCTAssertFalse(m.isActive)
        m.begin()
        XCTAssertEqual(m.focusedID, "a")
        var empty = model([])
        empty.begin()
        XCTAssertFalse(empty.isActive)
        XCTAssertNil(empty.focusedID)
    }

    func testArrowsMoveAndDoNotWrap() {
        var m = model()
        m.begin()
        XCTAssertEqual(m.handle(.left), .none, "left on the first card does not wrap to the last")
        XCTAssertEqual(m.focusedID, "a")
        XCTAssertEqual(m.handle(.right), .moved)
        XCTAssertEqual(m.handle(.right), .moved)
        XCTAssertEqual(m.focusedID, "c")
        XCTAssertEqual(m.handle(.right), .none, "right on the last card does not wrap to the first")
        XCTAssertEqual(m.focusedID, "c")
    }

    func testHomeAndEndJumpToTheEnds() {
        var m = model()
        m.begin()
        _ = m.handle(.right)
        XCTAssertEqual(m.handle(.end), .moved)
        XCTAssertEqual(m.focusedID, "c")
        XCTAssertEqual(m.handle(.end), .moved, "End on the last card is already there")
        XCTAssertEqual(m.handle(.home), .moved)
        XCTAssertEqual(m.focusedID, "a")
    }

    func testEnterActivatesTheFocusedCardAndEscapeEndsFocus() {
        var m = model()
        m.begin()
        _ = m.handle(.right)
        XCTAssertEqual(m.handle(.enter), .activated("b"))
        XCTAssertTrue(m.isActive, "activating does not move the ring by itself")
        XCTAssertEqual(m.handle(.escape), .ended)
        XCTAssertFalse(m.isActive)
        XCTAssertEqual(m.handle(.right), .none, "keys do nothing once focus is gone")
    }

    func testSyncKeepsTheSameCardAndClampsWithoutWrapping() {
        var m = model(["a", "b", "c"])
        m.begin()
        _ = m.handle(.right)
        m.sync(["x", "b", "y"])
        XCTAssertEqual(m.focusedID, "b", "the focused card keeps the keyboard when the strip changes")
        m.sync(["x", "y"])
        XCTAssertEqual(m.focusedID, "y", "a vanished card clamps to the nearest remaining one")
        m.sync([])
        XCTAssertFalse(m.isActive)
        m.sync(["only"])
        XCTAssertFalse(m.isActive, "an unfocused model is not woken by a sync")
    }

    /// The shortcut owns one hot key id and one store key, and starts off like every assignable action.
    @MainActor
    func testDockFocusHasItsOwnHotKeyIDAndStoreKey() {
        let ids = ShortcutAction.allCases.map(\.hotKeyID)
        XCTAssertEqual(Set(ids).count, ids.count, "no two actions may share a Carbon hot key id")
        XCTAssertEqual(ShortcutAction.dockFocus.hotKeyID, 53)
        XCTAssertEqual(ShortcutAction.dockFocus.defaultTrigger, .off)
        XCTAssertEqual(ShortcutAction.dockFocus.snapPosition, nil)
        XCTAssertFalse(ShortcutAction.dockFocus.isTilingAction)

        let suite = "katikati.dockFocus.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppSettingsStore(defaults: defaults)
        store.setShortcut(.dockFocus, .key(ShortcutKey(keyCode: 2, modifiers: ShortcutKey.control | ShortcutKey.option)))
        let raw = defaults.string(forKey: "com.katikati.shortcut.dockFocus")
        XCTAssertEqual(ShortcutTrigger.parse(raw), .key(ShortcutKey(keyCode: 2, modifiers: ShortcutKey.control | ShortcutKey.option)))
        XCTAssertEqual(AppSettingsStore(defaults: defaults).shortcutBindings[.dockFocus]?.serialized, raw)
    }
}

final class PinnedAppHotkeyTests: XCTestCase {
    func testValidationTrimsDropsInvalidAndDeduplicates() throws {
        let commandA = ShortcutKey(keyCode: 0, modifiers: ShortcutKey.command)
        let commandS = ShortcutKey(keyCode: 1, modifiers: ShortcutKey.command)
        let first = PinnedAppHotkey(bundleID: " com.example.app ", key: commandA)
        let invalidBareLetter = PinnedAppHotkey(bundleID: "com.example.invalid", key: ShortcutKey(keyCode: 2, modifiers: 0))
        let duplicateBundle = PinnedAppHotkey(bundleID: "com.example.app", key: commandS)
        let duplicateKey = PinnedAppHotkey(bundleID: "com.example.other", key: commandA)
        let second = PinnedAppHotkey(bundleID: "com.example.second", key: commandS)

        let validated = PinnedAppHotkeyValidation.validated([first, invalidBareLetter, duplicateBundle, duplicateKey, second])
        XCTAssertEqual(validated.map(\.bundleID), ["com.example.app", "com.example.second"])
        XCTAssertEqual(validated.first?.key, commandA)

        let decoded = try JSONDecoder().decode(PinnedAppHotkey.self,
                                               from: JSONEncoder().encode(first))
        XCTAssertEqual(decoded, first)
    }
}

/// SCU-1: categories, one ownership table, the three-state conflict, preset packs, the keycap map,
/// and the two ways into the bindings list.
final class ShortcutRedesignCoreTests: XCTestCase {
    func testEachBandTakesTheActionsItShould() {
        XCTAssertEqual(ShortcutAction.launcher.category, .core)
        XCTAssertEqual(ShortcutAction.commandBar.category, .core)
        XCTAssertEqual(ShortcutAction.snapLeftHalf.category, .windowAndSnap)
        XCTAssertEqual(ShortcutAction.windowSwitcher.category, .windowAndSnap)
        XCTAssertEqual(ShortcutAction.stripCycleWidth.category, .tiling)
        XCTAssertEqual(ShortcutAction.radialDial.category, .desktopAndNotch)
        XCTAssertEqual(ShortcutAction.captureArea.category, .tools)
        // Every action lands in exactly one band — the chips must never lose a row.
        for action in ShortcutAction.allCases { _ = action.category }
    }

    func testSystemOwnedCombinationsAreClashesAndTheValidatorAgrees() {
        let spotlight = ShortcutKey(keyCode: 49, modifiers: ShortcutKey.command)
        let reason = MacOSShortcutOwnership.reason(for: spotlight)
        XCTAssertNotNil(reason)
        XCTAssertEqual(ShortcutConflictDetector.conflict(for: .commandBar, trigger: .key(spotlight), among: [:]),
                       .systemClash(reason!))
        if case .warn(let why) = ShortcutValidator.check(.key(spotlight), for: .commandBar, among: [:]) {
            XCTAssertEqual(why, reason, "the recorder and the badge must read the same table")
        } else {
            XCTFail("⌘Space should warn, never pass silently")
        }
        // KatiKati's own defaults stay clear — ⌥Space, ⌥⇧Space and ⌃⌥M are not macOS shortcuts.
        XCTAssertNil(MacOSShortcutOwnership.reason(for: ShortcutKey(keyCode: 49, modifiers: ShortcutKey.option)))
        XCTAssertNil(MacOSShortcutOwnership.reason(for: ShortcutKey(keyCode: 46, modifiers: ShortcutKey.control | ShortcutKey.option)))
        XCTAssertEqual(ShortcutConflictDetector.conflict(for: .commandBar, trigger: .chord(.optionSpace), among: [:]), .clear)
    }

    func testDuplicatesAreNamedAndOffIsNeverAConflict() {
        let key = ShortcutKey(keyCode: 46, modifiers: ShortcutKey.control | ShortcutKey.option)
        let bindings: [ShortcutAction: ShortcutTrigger] = [.snapMaximize: .key(key), .snapCenter: .key(key)]
        XCTAssertEqual(ShortcutConflictDetector.conflict(for: .snapMaximize, trigger: .key(key), among: bindings),
                       .internalDuplicate(.snapCenter))
        XCTAssertEqual(ShortcutConflictDetector.conflict(for: .translate, trigger: .off, among: bindings), .clear)
        XCTAssertEqual(ShortcutConflictDetector.conflicted(bindings).count, 2)
    }

    func testHyperPackBindsTheSixWindowActionsAndKeepsEverythingElse() {
        let pack = ShortcutPresetPack.hyperKeyPack.bindings(replacing: [:])
        for action in [ShortcutAction.snapLeftHalf, .snapRightHalf, .snapMaximize,
                       .snapNextDisplay, .windowSwitcher, .toggleTiling] {
            guard case .hyper = pack[action] else { return XCTFail("\(action) should be a Hyper binding") }
        }
        XCTAssertEqual(pack[.launcher], ShortcutAction.launcher.defaultTrigger)
        XCTAssertEqual(pack[.commandBar], ShortcutAction.commandBar.defaultTrigger)
    }

    func testMinimalPackDropsOnlyTheSystemClashes() {
        let pack = ShortcutPresetPack.minimalConflictFree.bindings(replacing: [:])
        for (action, trigger) in pack {
            guard case .key(let key) = trigger.overlapKey else { continue }
            XCTAssertNil(MacOSShortcutOwnership.reason(for: key), "\(action) still clashes with macOS")
        }
        XCTAssertEqual(pack[.snapMaximize], ShortcutAction.snapMaximize.defaultTrigger, "⌃⌥M must survive")
    }

    func testMiniKeyboardLightsCapsAndPulsesTimingGestures() {
        let chord = MiniKeyboardState.from(.chord(.optionShiftSpace))
        XCTAssertEqual(chord.litModifiers, ["⌥", "⇧"])
        XCTAssertEqual(chord.mainKey, "Space")
        XCTAssertFalse(chord.pulses)
        XCTAssertEqual(MiniKeyboardState.from(.hyper(0)).litModifiers, ["✦"])
        let tap = MiniKeyboardState.from(.doubleTap(.leftCommand))
        XCTAssertTrue(tap.pulses)
        XCTAssertEqual(tap.mainKey, "⌘")
        XCTAssertEqual(MiniKeyboardState.from(.off), .idle)
    }

    func testFilterFindsByNameGlyphsAndExactKeys() {
        XCTAssertTrue(ShortcutFilter.matches(name: "Launcher", action: .launcher, trigger: .off, query: "laun"))
        XCTAssertTrue(ShortcutFilter.matches(name: "Command Bar", action: .commandBar, trigger: .chord(.optionSpace), query: "⌥Space"))
        XCTAssertFalse(ShortcutFilter.matches(name: "Launcher", action: .launcher, trigger: .off, query: "snap"))
        XCTAssertTrue(ShortcutFilter.matches(trigger: .chord(.optionSpace), key: ShortcutKey(keyCode: 49, modifiers: ShortcutKey.option)))
        XCTAssertFalse(ShortcutFilter.matches(trigger: .chord(.optionSpace), key: ShortcutKey(keyCode: 49, modifiers: ShortcutKey.command)))
    }
}

/// The one cheat sheet: the frontmost app's menu shortcuts, with KatiKati's own live bindings as
/// their own category, grouped, filtered and exported. Moved here from `ShortcutCheatSheetTests.swift`
/// so the suite stays in the existing files.
final class ShortcutCheatSheetTests: XCTestCase {
    func testBuildsGroupedCategoriesAndFiltersByQueryAndModifiers() {
        let entries = [
            MenuSearchEntry(path: ["File", "New Window"], commandKey: "n", modifiers: 0, isEnabled: true),
            MenuSearchEntry(path: ["File", "Export", "PDF…"], commandKey: "e", modifiers: 1, isEnabled: true),
            MenuSearchEntry(path: ["Edit", "No Shortcut"], commandKey: nil, modifiers: 0, isEnabled: true),
            MenuSearchEntry(path: ["Apple", "About"], commandKey: "i", modifiers: 0, isEnabled: true)
        ]

        let categories = ShortcutCheatSheetBuilder.build(entries: entries)
        XCTAssertEqual(categories.map(\.title), ["File"])
        XCTAssertEqual(categories.first?.items.count, 2)
        XCTAssertEqual(categories.first?.items.last?.subtitle, "Export")
        XCTAssertEqual(categories.first?.items.last?.shortcut, "⇧⌘E")

        let shiftOnly = ShortcutCheatSheetBuilder.filter(
            categories: categories,
            query: "",
            requiredModifiers: [.shift]
        )
        XCTAssertEqual(shiftOnly.first?.items.map(\.title), ["Export", "PDF…"].last.map { [$0] })

        let md = ShortcutCheatSheetBuilder.exportMarkdown(appName: "Finder", categories: categories)
        XCTAssertTrue(md.contains("# Finder Keyboard Shortcuts"))
        XCTAssertTrue(md.contains("| Export › PDF… | `⇧⌘E` |"))
    }

    /// `showCheatSheet` is what opens this one sheet, so it must stay bindable and reachable.
    func testShowCheatSheetActionDefaultsOffAndSitsInTools() {
        XCTAssertEqual(ShortcutAction.showCheatSheet.defaultTrigger, .off)
        XCTAssertEqual(ShortcutAction.showCheatSheet.category, .tools)
        XCTAssertTrue(ShortcutAction.allCases.contains(.showCheatSheet))
    }

    /// KatiKati's own shortcuts share the sheet with the frontmost app's, in a category of their own.
    func testKatiKatiBindingsBecomeTheirOwnCategory() {
        let entries = [MenuSearchEntry(path: ["File", "New Window"], commandKey: "n", modifiers: 0, isEnabled: true)]
        let items = [
            ShortcutCheatSheetItem(id: "katikati.commandBar", title: "Command Bar", subtitle: "KatiKati",
                                   shortcut: "⌥Space", modifiers: [.option], category: "KatiKati", path: []),
            ShortcutCheatSheetItem(id: "katikati.launcher", title: "Launcher", subtitle: "KatiKati",
                                   shortcut: "⌥⇧Space", modifiers: [.option, .shift], category: "KatiKati", path: [])
        ]

        let categories = ShortcutCheatSheetBuilder.build(entries: entries, katikatiItems: items)
        XCTAssertEqual(categories.map(\.title), ["File", "KatiKati"])
        XCTAssertEqual(categories.last?.items.map(\.title), ["Command Bar", "Launcher"])

        let filtered = ShortcutCheatSheetBuilder.filter(categories: categories, query: "launcher", requiredModifiers: [])
        XCTAssertEqual(filtered.map(\.title), ["KatiKati"])
        XCTAssertEqual(filtered.first?.items.map(\.title), ["Launcher"])
    }
}
