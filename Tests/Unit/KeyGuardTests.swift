import XCTest
@testable import KatiKati

final class KeyGuardPipelineTests: XCTestCase {
    private let q = KeyGuardPipeline.quitKeyCode
    private let unlock = KeyChord(keyCode: 49, modifiers: [.control, .option])

    func testNothingSwallowedWhenAllGuardsOff() {
        let state = KeyGuardState()
        XCTAssertEqual(KeyGuardPipeline.reduce(.keyDown(keyCode: 0, modifiers: []), state: state).decision, .passThrough)
        XCTAssertEqual(KeyGuardPipeline.reduce(.keyDown(keyCode: q, modifiers: [.command]), state: state).decision, .passThrough)
    }

    func testPauseSwallowsEverythingButTheUnlockChord() {
        var state = KeyGuardState(paused: true, unlockKey: unlock)
        let swallowed = KeyGuardPipeline.reduce(.keyDown(keyCode: 0, modifiers: [.command]), state: state)
        XCTAssertEqual(swallowed.decision, .swallow)
        XCTAssertTrue(swallowed.state.paused)

        let unlocked = KeyGuardPipeline.reduce(.keyDown(keyCode: 49, modifiers: [.control, .option]), state: state)
        XCTAssertEqual(unlocked.decision, .consumeAndFire(.unlock))
        XCTAssertFalse(unlocked.state.paused)
        state = unlocked.state
    }

    func testSlowQuitSwallowsAHeldQuit() {
        let state = KeyGuardState(slowQuitEnabled: true, slowQuitApplies: true)
        let down = KeyGuardPipeline.reduce(.keyDown(keyCode: q, modifiers: [.command]), state: state)
        XCTAssertEqual(down.decision, .consumeAndFire(.slowQuitPressed))
        XCTAssertTrue(down.state.slowQuitHolding)

        let up = KeyGuardPipeline.reduce(.keyUp(keyCode: q, modifiers: []), state: down.state)
        XCTAssertEqual(up.decision, .consumeAndFire(.slowQuitReleased))
        XCTAssertFalse(up.state.slowQuitHolding)
    }

    func testSlowQuitIgnoresOtherKeysAndIneligibleApps() {
        XCTAssertEqual(KeyGuardPipeline.reduce(.keyDown(keyCode: 0, modifiers: []),
                                               state: KeyGuardState(slowQuitEnabled: true, slowQuitApplies: true)).decision, .passThrough)
        XCTAssertEqual(KeyGuardPipeline.reduce(.keyDown(keyCode: q, modifiers: [.command]),
                                               state: KeyGuardState(slowQuitEnabled: true, slowQuitApplies: false)).decision, .passThrough)
    }

    func testSlowQuitIgnoresSystemAndModifiedQuitChords() {
        let state = KeyGuardState(slowQuitEnabled: true, slowQuitApplies: true)
        XCTAssertEqual(KeyGuardPipeline.reduce(.keyDown(keyCode: q, modifiers: [.command, .shift]), state: state).decision, .passThrough, "⌘⇧Q Log Out must pass through")
        XCTAssertEqual(KeyGuardPipeline.reduce(.keyDown(keyCode: q, modifiers: [.command, .control]), state: state).decision, .passThrough, "⌘⌃Q Lock Screen must pass through")
        XCTAssertEqual(KeyGuardPipeline.reduce(.keyDown(keyCode: q, modifiers: [.command, .option]), state: state).decision, .passThrough, "⌘⌥Q Quit and Keep Windows must pass through")
    }

    func testSlowQuitSwallowsAutorepeatKeyDown() {
        let state = KeyGuardState(slowQuitEnabled: true, slowQuitApplies: true, slowQuitHolding: true)
        let repeated = KeyGuardPipeline.reduce(.keyDown(keyCode: q, modifiers: [.command]), state: state, isRepeat: true)
        XCTAssertEqual(repeated.decision, .swallow)

        // Even after hold fired and slowQuitHolding cleared, autorepeat while Q is still held must not start a new hold.
        let postFireState = KeyGuardState(slowQuitEnabled: true, slowQuitApplies: true, slowQuitHolding: false)
        let postFireRepeat = KeyGuardPipeline.reduce(.keyDown(keyCode: q, modifiers: [.command]), state: postFireState, isRepeat: true)
        XCTAssertEqual(postFireRepeat.decision, .swallow)
        XCTAssertFalse(postFireRepeat.state.slowQuitHolding)
    }

    func testSlowQuitCancelsOnEscapeOrCommandRelease() {
        let holding = KeyGuardState(slowQuitEnabled: true, slowQuitApplies: true, slowQuitHolding: true)
        let escaped = KeyGuardPipeline.reduce(.keyDown(keyCode: KeyGuardPipeline.escapeKeyCode, modifiers: []), state: holding)
        XCTAssertEqual(escaped.decision, .consumeAndFire(.slowQuitReleased))
        XCTAssertFalse(escaped.state.slowQuitHolding)

        let cmdReleased = KeyGuardPipeline.reduce(.flagsChanged(modifiers: []), state: holding)
        XCTAssertEqual(cmdReleased.decision, .consumeAndFire(.slowQuitReleased))
        XCTAssertFalse(cmdReleased.state.slowQuitHolding)
    }

    func testSlowQuitSkipsWhenSecureInputActive() {
        let state = KeyGuardState(slowQuitEnabled: true, slowQuitApplies: true, secureInputActive: true)
        XCTAssertEqual(KeyGuardPipeline.reduce(.keyDown(keyCode: q, modifiers: [.command]), state: state).decision, .passThrough)
    }

    func testSlowQuitDoubleTapTiming() {
        var timing = SlowQuitDoubleTapTiming(window: 0.5)
        let t0 = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(timing.registerTap(at: t0), .armed)
        XCTAssertEqual(timing.registerTap(at: t0.addingTimeInterval(0.3)), .fire)
        XCTAssertEqual(timing.registerTap(at: t0.addingTimeInterval(0.4)), .armed, "second tap consumed the armed window")
        XCTAssertEqual(timing.registerTap(at: t0.addingTimeInterval(1.2)), .armed, "expired window re-arms instead of firing")
        timing.reset()
        XCTAssertEqual(timing.registerTap(at: t0.addingTimeInterval(1.3)), .armed)
    }
}

/// 53i: remote desktops and virtual machines keep their own ⌘Q.
final class SlowQuitPassthroughTests: XCTestCase {
    private let q = KeyGuardPipeline.quitKeyCode

    func testPassthroughAppsSkipTheHold() {
        let state = KeyGuardState(slowQuitEnabled: true, slowQuitApplies: true, slowQuitPassthrough: true)
        XCTAssertEqual(KeyGuardPipeline.reduce(.keyDown(keyCode: q, modifiers: [.command]), state: state).decision, .passThrough)
        XCTAssertEqual(KeyGuardPipeline.reduce(.keyUp(keyCode: q, modifiers: []), state: state).decision, .passThrough)
    }

    func testPolicyUsesTheListAndIgnoresUnknownApps() {
        let policy = SlowQuitPassthrough(bundleIDs: ["com.apple.ScreenSharing"])
        XCTAssertTrue(policy.applies(to: "com.apple.ScreenSharing"))
        XCTAssertFalse(policy.applies(to: "com.apple.finder"))
        XCTAssertFalse(policy.applies(to: nil))
    }

    func testParseAndTheDefaultList() {
        XCTAssertTrue(SlowQuitPassthrough.parse("").bundleIDs.isEmpty, "clearing the field means none")
        XCTAssertEqual(SlowQuitPassthrough.parse("com.a.B, com.c.D").bundleIDs, ["com.a.B", "com.c.D"])
        XCTAssertTrue(SlowQuitPassthrough.defaults.contains("com.apple.ScreenSharing"))
    }
}

/// 53b: ⌘X copies and marks, ⌘V moves, all by rewriting the chord — nothing is synthesized.
final class FinderKeyMapTests: XCTestCase {
    private var map = FinderKeyMap()

    func testCutBecomesCopyOnDownAndUp() {
        XCTAssertEqual(map.handle(.keyDown(keyCode: FinderKeyMap.cutKey, modifiers: [.command])),
                       .rewrite(keyCode: FinderKeyMap.copyKey, addingModifiers: []))
        XCTAssertTrue(map.cutPending)
        XCTAssertEqual(map.handle(.keyUp(keyCode: FinderKeyMap.cutKey, modifiers: [])),
                       .rewrite(keyCode: FinderKeyMap.copyKey, addingModifiers: []), "key-up follows even after ⌘ is released")
    }

    func testPasteMovesOnlyAfterACut() {
        XCTAssertEqual(map.handle(.keyDown(keyCode: FinderKeyMap.pasteKey, modifiers: [.command])), .passThrough)
        _ = map.handle(.keyDown(keyCode: FinderKeyMap.cutKey, modifiers: [.command]))
        XCTAssertEqual(map.handle(.keyDown(keyCode: FinderKeyMap.pasteKey, modifiers: [.command])),
                       .rewrite(keyCode: FinderKeyMap.pasteKey, addingModifiers: .option))
        XCTAssertFalse(map.cutPending, "the move is used up")
        XCTAssertEqual(map.handle(.keyUp(keyCode: FinderKeyMap.pasteKey, modifiers: [.command])),
                       .rewrite(keyCode: FinderKeyMap.pasteKey, addingModifiers: .option))
        XCTAssertEqual(map.handle(.keyDown(keyCode: FinderKeyMap.pasteKey, modifiers: [.command])), .passThrough,
                       "a second paste is a normal paste")
    }

    func testPlainKeysAndUnmodifiedXPassThrough() {
        XCTAssertEqual(map.handle(.keyDown(keyCode: FinderKeyMap.cutKey, modifiers: [])), .passThrough)
        XCTAssertEqual(map.handle(.keyDown(keyCode: 0, modifiers: [.command])), .passThrough)
        XCTAssertEqual(map.handle(.keyUp(keyCode: FinderKeyMap.cutKey, modifiers: [])), .passThrough)
    }

    func testResetDropsAPendingCut() {
        _ = map.handle(.keyDown(keyCode: FinderKeyMap.cutKey, modifiers: [.command]))
        map.reset()
        XCTAssertFalse(map.cutPending)
        XCTAssertEqual(map.handle(.keyUp(keyCode: FinderKeyMap.cutKey, modifiers: [])), .passThrough)
        XCTAssertEqual(map.handle(.keyDown(keyCode: FinderKeyMap.pasteKey, modifiers: [.command])), .passThrough)
    }
}

/// 53a: a quick tap does nothing; a hold toggles once, and only while the key is down.
final class CapsLockGuardTests: XCTestCase {
    func testShortTapNeverFires() {
        var guardState = CapsLockGuard()
        XCTAssertTrue(guardState.press())
        guardState.release()
        XCTAssertFalse(guardState.fireIfStillHeld())
    }

    func testHoldFiresExactlyOnce() {
        var guardState = CapsLockGuard()
        XCTAssertTrue(guardState.press())
        XCTAssertTrue(guardState.fireIfStillHeld())
        XCTAssertFalse(guardState.fireIfStillHeld(), "the timer may fire late; the toggle still happens once")
        guardState.release()
        XCTAssertFalse(guardState.fireIfStillHeld())
    }

    func testAutoRepeatDoesNotReschedule() {
        var guardState = CapsLockGuard()
        XCTAssertTrue(guardState.press())
        XCTAssertFalse(guardState.press())
        XCTAssertTrue(guardState.fireIfStillHeld())
    }

    func testTheNextPressCanFireAgain() {
        var guardState = CapsLockGuard()
        _ = guardState.press()
        _ = guardState.fireIfStillHeld()
        guardState.release()
        XCTAssertTrue(guardState.press())
        XCTAssertTrue(guardState.fireIfStillHeld())
    }
}

/// 53c: the typed-word buffer. A delimiter completes a trigger; everything else just builds the word.
final class SnippetExpanderTests: XCTestCase {
    private func triggers(_ raw: String) -> [String: String] {
        SnippetExpander.triggers(from: CustomCommand.parseSnippets(raw))
    }

    func testTriggerPlusSpaceExpandsWithTheDelimiter() {
        var expander = SnippetExpander()
        expander.setTriggers(triggers("brb = be right back\nsig = Sam"))
        for ch in "brb" { XCTAssertNil(expander.feed(String(ch)), "nothing fires mid-word") }
        XCTAssertEqual(expander.feed(" "),
                       SnippetExpander.Expansion(replacement: "be right back ", triggerCount: 3))
        XCTAssertNil(expander.feed(" "), "the word started over")
    }

    func testUnknownWordIsDroppedAtTheDelimiter() {
        var expander = SnippetExpander()
        expander.setTriggers(triggers("brb = be right back"))
        for ch in "nope" { _ = expander.feed(String(ch)) }
        XCTAssertNil(expander.feed("\n"))
        for ch in "brb" { _ = expander.feed(String(ch)) }
        XCTAssertEqual(expander.feed("\t")?.replacement, "be right back\t")
    }

    func testBackspaceEditsTheWord() {
        var expander = SnippetExpander()
        expander.setTriggers(triggers("brb = be right back"))
        for ch in "brx" { _ = expander.feed(String(ch)) }
        expander.backspace()
        _ = expander.feed("b")
        XCTAssertEqual(expander.feed(" ")?.triggerCount, 3)
    }

    func testOneCharacterTriggersAndSpacedNamesDoNotFire() {
        var expander = SnippetExpander()
        expander.setTriggers(triggers("a = alpha\ntwo words = never"))
        XCTAssertNil(expander.feed("a"))
        XCTAssertNil(expander.feed(" "), "a one-character trigger is not worth expanding")
        for ch in "two words" { _ = expander.feed(String(ch)) }
        XCTAssertNil(expander.feed(" "), "a name with whitespace can never match a word")
    }

    func testTheWordIsBounded() {
        var expander = SnippetExpander()
        for _ in 0..<(SnippetExpander.maxWord * 3) { _ = expander.feed("x") }
        XCTAssertEqual(expander.word.count, SnippetExpander.maxWord)
        expander.reset()
        XCTAssertTrue(expander.word.isEmpty)
    }

    func testPasswordManagersAreIgnored() {
        XCTAssertTrue(SnippetExpander.isIgnored(bundleID: "com.1password.1password"))
        XCTAssertTrue(SnippetExpander.isIgnored(bundleID: "com.apple.keychainaccess"))
        XCTAssertFalse(SnippetExpander.isIgnored(bundleID: "com.apple.finder"))
        XCTAssertFalse(SnippetExpander.isIgnored(bundleID: nil))
    }

    /// The shared holder only feeds when the service says the frontmost app is allowed, and a secure
    /// field drops the word instead of letting it complete later.
    func testSharedFeedNeedsAnActiveStateAndDropsTheWordUnderSecureInput() {
        let shared = KeyGuardShared()
        shared.setSnippets(enabled: true, triggers: ["brb": "be right back"])
        shared.update(state: KeyGuardState(snippetsActive: false))
        for ch in "brb" { XCTAssertNil(shared.feedSnippet(String(ch), secureInput: false)) }

        shared.update(state: KeyGuardState(snippetsActive: true))
        for ch in "brb" { _ = shared.feedSnippet(String(ch), secureInput: false) }
        XCTAssertNil(shared.feedSnippet(" ", secureInput: true), "secure input clears the word")
        for ch in "brb" { _ = shared.feedSnippet(String(ch), secureInput: false) }
        XCTAssertEqual(shared.feedSnippet(" ", secureInput: false)?.replacement, "be right back ")
    }

    func testStructuredSnippetJSONRoundTripAndLegacyMigration() {
        let legacy = ";sig = Line 1\\nLine 2\n;brb = be right back"
        let migrated = TextSnippetStore.parse(legacy)
        XCTAssertEqual(migrated.count, 2)
        XCTAssertEqual(migrated[0].trigger, ";sig")
        XCTAssertEqual(migrated[0].content, "Line 1\nLine 2")
        XCTAssertTrue(migrated[0].isEnabled)
        XCTAssertTrue(migrated[0].requireDelimiter)

        let item = TextSnippetItem(trigger: ";hi", content: "Hello\nWorld", isEnabled: false, requireDelimiter: false)
        let json = TextSnippetStore.serialize([item])
        let decoded = TextSnippetStore.parse(json)
        XCTAssertEqual(decoded, [item])
    }

    func testSnippetVariableExpanderClipboardDateTimeAndCursor() {
        let fixed = Date(timeIntervalSince1970: 1_700_000_000)
        let res = SnippetVariableExpander.expand(
            "Link: {clipboard} ({cursor}) on {date} {time}",
            clipboard: "https://example.com",
            now: fixed,
            locale: Locale(identifier: "en_US_POSIX")
        )
        XCTAssertTrue(res.text.hasPrefix("Link: https://example.com () on "))
        XCTAssertFalse(res.text.contains("{cursor}"))
        XCTAssertGreaterThan(res.cursorLeftArrows, 10)
    }

    func testImmediateTriggerExpandsWithoutDelimiterAndRespectsDisabled() {
        var expander = SnippetExpander()
        expander.setSnippets([
            TextSnippetItem(trigger: ";now", content: "NOW", isEnabled: true, requireDelimiter: false),
            TextSnippetItem(trigger: ";off", content: "OFF", isEnabled: false, requireDelimiter: false)
        ])
        XCTAssertNil(expander.feed(";"))
        XCTAssertNil(expander.feed("n"))
        XCTAssertNil(expander.feed("o"))
        let hit = expander.feed("w")
        XCTAssertEqual(hit?.replacement, "NOW")
        XCTAssertEqual(hit?.triggerCount, 4)
        XCTAssertEqual(hit?.swallowedDelimiter, false)

        for ch in ";off" { XCTAssertNil(expander.feed(String(ch))) }
    }
}

final class SlowQuitTests: XCTestCase {
    func testTiming() {
        let timing = SlowQuitTiming(threshold: 0.5)
        XCTAssertEqual(timing.progress(heldFor: 0.25), 0.5)
        XCTAssertEqual(timing.progress(heldFor: 1), 1)
        XCTAssertFalse(timing.shouldFire(heldFor: 0.4))
        XCTAssertTrue(timing.shouldFire(heldFor: 0.5))
    }

    func testPolicy() {
        XCTAssertTrue(SlowQuitPolicy().applies(to: "com.x.Y"))
        XCTAssertTrue(SlowQuitPolicy(allow: ["com.x.Y"]).applies(to: "com.x.Y"))
        XCTAssertFalse(SlowQuitPolicy(allow: ["com.x.Y"]).applies(to: "com.x.Z"))
        XCTAssertFalse(SlowQuitPolicy(deny: ["com.x.Y"]).applies(to: "com.x.Y"))
        XCTAssertFalse(SlowQuitPolicy(allow: ["com.x.Y"]).applies(to: nil), "unknown app only when all allowed")
        XCTAssertTrue(SlowQuitPolicy().applies(to: nil))
    }
}

final class KeyGuardSharedTests: XCTestCase {
    private let q = KeyGuardPipeline.quitKeyCode

    /// A settings/frontmost push in the middle of a hold must not cancel the keyUp that fires the quit.
    func testUpdatePreservesAnInProgressHold() {
        let shared = KeyGuardShared()
        shared.update(state: KeyGuardState(slowQuitEnabled: true, slowQuitApplies: true))
        let down = shared.decide(.keyDown(keyCode: q, modifiers: [.command]))
        XCTAssertEqual(down.decision, .consumeAndFire(.slowQuitPressed))

        shared.update(state: KeyGuardState(slowQuitEnabled: true, slowQuitApplies: true))

        let up = shared.decide(.keyUp(keyCode: q, modifiers: []))
        XCTAssertEqual(up.decision, .consumeAndFire(.slowQuitReleased), "the hold survived the state push")
    }

    func testResetDropsEveryGuard() {
        let shared = KeyGuardShared()
        let unlock = KeyChord(keyCode: 49, modifiers: [.control, .option])
        shared.update(state: KeyGuardState(paused: true, unlockKey: unlock))
        XCTAssertEqual(shared.decide(.keyDown(keyCode: 0, modifiers: [])).decision, .swallow)

        shared.reset()
        XCTAssertEqual(shared.decide(.keyDown(keyCode: 0, modifiers: [])).decision, .passThrough)
        XCTAssertEqual(shared.decide(.keyDown(keyCode: q, modifiers: [.command])).decision, .passThrough)
    }

    /// The visualizer is off by default: the tap thread must not even buffer a keycap until it is on,
    /// and turning it off clears whatever was buffered.
    func testKeycapsAreBufferedOnlyWhileTheVisualizerIsOn() {
        let shared = KeyGuardShared()
        shared.record(symbol: "a")
        XCTAssertTrue(shared.keycaps().isEmpty, "visualizer off by default")

        shared.setVisualizer(enabled: true)
        shared.record(symbol: "a", secureInput: false)
        XCTAssertEqual(shared.keycaps().map(\.symbol), ["a"])

        shared.setVisualizer(enabled: false)
        XCTAssertTrue(shared.keycaps().isEmpty, "turning it off clears the strip")
    }

    /// 24e: the tap thread does this work for every key event. The shared holder (lock + reduce + keycap
    /// buffer) must stay far under one 60 Hz frame, so a stuck key can never back the system up.
    func testTapPathStaysSubFrameUnderLoad() {
        let shared = KeyGuardShared()
        shared.setVisualizer(enabled: true)
        shared.update(state: KeyGuardState(slowQuitEnabled: true, slowQuitApplies: true))
        let q = KeyGuardPipeline.quitKeyCode

        var decisions = 0
        var pressed = 0
        var released = 0
        let start = DispatchTime.now()
        for _ in 0..<100_000 {
            let down = shared.decide(.keyDown(keyCode: q, modifiers: [.command]))
            let up = shared.decide(.keyUp(keyCode: q, modifiers: []))
            shared.record(symbol: "⌘Q", secureInput: false)
            decisions += 2
            if case .consumeAndFire(.slowQuitPressed) = down.decision { pressed += 1 }
            if case .consumeAndFire(.slowQuitReleased) = up.decision { released += 1 }
        }
        let elapsedNanos = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        let perKeyMicros = Double(elapsedNanos) / Double(decisions) / 1_000

        XCTAssertEqual(pressed, 100_000, "every ⌘Q down is held")
        XCTAssertEqual(released, 100_000, "every ⌘Q up releases the hold")
        XCTAssertLessThan(perKeyMicros, 5, "tap path is O(1) per key; got \(String(format: "%.2f", perKeyMicros)) µs")
    }

    /// The strip holds at most `KeyVisualizerBuffer.capacity` keycaps and coalesces a repeat of the
    /// newest one, so a long hold never grows the strip without bound.
    func testKeycapBufferStaysBoundedAndCoalesces() {
        let shared = KeyGuardShared()
        shared.setVisualizer(enabled: true)
        for _ in 0..<20 { shared.record(symbol: "a", secureInput: false) }
        XCTAssertEqual(shared.keycaps().map(\.symbol), ["a"], "a repeat of the newest coalesces")
        for symbol in ["b", "c", "d", "e", "f", "g", "h"] { shared.record(symbol: symbol, secureInput: false) }
        XCTAssertEqual(shared.keycaps().count, KeyVisualizerBuffer.capacity)
    }

    /// Secure input (password fields) must leave no keycap behind, and must not even be probed while the visualizer is off.
    func testSecureInputClearsAndRecordsNothing() {
        let shared = KeyGuardShared()
        var probed = false
        shared.record(symbol: "x", secureInput: { probed = true; return false }())
        XCTAssertFalse(probed, "probe is not read while the visualizer is off")
        shared.setVisualizer(enabled: true)
        shared.record(symbol: "a", secureInput: false)
        XCTAssertEqual(shared.keycaps().map(\.symbol), ["a"])
        shared.record(symbol: "b", secureInput: true)
        XCTAssertTrue(shared.keycaps().isEmpty, "secure input clears the strip and keeps nothing")
    }
}

final class KeyVisualizerBufferTests: XCTestCase {
    func testCoalescesRepeatsAndCaps() {
        var buffer = KeyVisualizerBuffer()
        let now = Date(timeIntervalSince1970: 0)
        for _ in 0..<4 { buffer.push(symbol: "A", at: now) }
        XCTAssertEqual(buffer.items.count, 1, "a repeat coalesces")
        for symbol in ["B", "C", "D", "E", "F", "G", "H"] { buffer.push(symbol: symbol, at: now) }
        XCTAssertEqual(buffer.items.count, KeyVisualizerBuffer.capacity)
        XCTAssertEqual(buffer.items.first?.symbol, "C", "oldest drop first")
    }

    func testPruneAndClear() {
        var buffer = KeyVisualizerBuffer()
        buffer.push(symbol: "A", at: Date(timeIntervalSince1970: 0))
        buffer.prune(olderThan: 2, now: Date(timeIntervalSince1970: 5))
        XCTAssertTrue(buffer.items.isEmpty)
        buffer.push(symbol: "B", at: Date(timeIntervalSince1970: 5))
        buffer.clear()
        XCTAssertTrue(buffer.items.isEmpty)
    }
}

final class KeyAudioPolicyTests: XCTestCase {

    func testTriggersOnKeyDownWhenEnabledAndUninhibited() {
        let event = KeyGuardEvent.keyDown(keyCode: 0, modifiers: [])
        XCTAssertTrue(KeyAudioPolicy.shouldTrigger(
            event: event,
            enabled: true,
            isSecureInput: false,
            isCallActive: false,
            isPaused: false
        ))
    }

    func testSuppressedOnKeyUp() {
        let event = KeyGuardEvent.keyUp(keyCode: 0, modifiers: [])
        XCTAssertFalse(KeyAudioPolicy.shouldTrigger(
            event: event,
            enabled: true,
            isSecureInput: false,
            isCallActive: false,
            isPaused: false
        ))
    }

    func testSuppressedUnderSecureInput() {
        let event = KeyGuardEvent.keyDown(keyCode: 0, modifiers: [])
        XCTAssertFalse(KeyAudioPolicy.shouldTrigger(
            event: event,
            enabled: true,
            isSecureInput: true,
            isCallActive: false,
            isPaused: false
        ), "Must suppress audio feedback in secure input fields (passwords)")
    }

    func testSuppressedDuringActiveCallOrMic() {
        let event = KeyGuardEvent.keyDown(keyCode: 0, modifiers: [])
        XCTAssertFalse(KeyAudioPolicy.shouldTrigger(
            event: event,
            enabled: true,
            isSecureInput: false,
            isCallActive: true,
            isPaused: false
        ), "Must suppress audio feedback when in a meeting or call")
    }

    func testSuppressedWhenPaused() {
        let event = KeyGuardEvent.keyDown(keyCode: 0, modifiers: [])
        XCTAssertFalse(KeyAudioPolicy.shouldTrigger(
            event: event,
            enabled: true,
            isSecureInput: false,
            isCallActive: false,
            isPaused: true
        ), "Must suppress audio feedback when keyboard is paused for cleaning")
    }

    func testSuppressedWhenDisabled() {
        let event = KeyGuardEvent.keyDown(keyCode: 0, modifiers: [])
        XCTAssertFalse(KeyAudioPolicy.shouldTrigger(
            event: event,
            enabled: false,
            isSecureInput: false,
            isCallActive: false,
            isPaused: false
        ))
    }
}

final class KeyModifierDoubleTapDetectorTests: XCTestCase {

    func testDoubleTapDetectedWithinTimeout() {
        var detector = KeyModifierDoubleTapDetector(timeout: 0.3)
        let t0 = Date(timeIntervalSince1970: 1000)

        XCTAssertEqual(detector.registerModifier(modifier: .command, isDown: true, at: t0), .none)
        XCTAssertEqual(detector.registerModifier(modifier: .command, isDown: false, at: t0.addingTimeInterval(0.05)), .none)

        let result = detector.registerModifier(modifier: .command, isDown: true, at: t0.addingTimeInterval(0.20))
        XCTAssertEqual(result, .doubleTap(.command))
    }

    func testDoubleTapIgnoredBeyondTimeout() {
        var detector = KeyModifierDoubleTapDetector(timeout: 0.3)
        let t0 = Date(timeIntervalSince1970: 1000)

        XCTAssertEqual(detector.registerModifier(modifier: .command, isDown: true, at: t0), .none)
        XCTAssertEqual(detector.registerModifier(modifier: .command, isDown: false, at: t0.addingTimeInterval(0.05)), .none)

        let result = detector.registerModifier(modifier: .command, isDown: true, at: t0.addingTimeInterval(0.40))
        XCTAssertEqual(result, .none)
    }

    func testInterveningKeyResetsDoubleTap() {
        var detector = KeyModifierDoubleTapDetector(timeout: 0.3)
        let t0 = Date(timeIntervalSince1970: 1000)

        _ = detector.registerModifier(modifier: .command, isDown: true, at: t0)
        _ = detector.registerModifier(modifier: .command, isDown: false, at: t0.addingTimeInterval(0.05))

        detector.registerInterveningKey()

        let result = detector.registerModifier(modifier: .command, isDown: true, at: t0.addingTimeInterval(0.15))
        XCTAssertEqual(result, .none)
    }

    func testDifferentModifiersDoNotTriggerDoubleTap() {
        var detector = KeyModifierDoubleTapDetector(timeout: 0.3)
        let t0 = Date(timeIntervalSince1970: 1000)

        _ = detector.registerModifier(modifier: .command, isDown: true, at: t0)
        _ = detector.registerModifier(modifier: .command, isDown: false, at: t0.addingTimeInterval(0.05))

        let result = detector.registerModifier(modifier: .shift, isDown: true, at: t0.addingTimeInterval(0.15))
        XCTAssertEqual(result, .none)
    }

    func testCapsLockDoubleTapAndVisualizerFilterFormatting() {
        var guardState = CapsLockGuard()
        let t0 = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(guardState.registerDoubleTap(at: t0))
        XCTAssertTrue(guardState.registerDoubleTap(at: t0.addingTimeInterval(0.20)))
        XCTAssertFalse(guardState.registerDoubleTap(at: t0.addingTimeInterval(0.30)))

        // All keys formats special keys cleanly
        XCTAssertEqual(KeyVisualizerSymbol.format(keyCode: 36, modifiers: [], characters: "\r", filter: .allKeys), "⏎")
        XCTAssertEqual(KeyVisualizerSymbol.format(keyCode: 49, modifiers: [], characters: " ", filter: .allKeys), "␣")

        // Modified keys drops plain typing, keeps shortcuts and special keys
        XCTAssertNil(KeyVisualizerSymbol.format(keyCode: 0, modifiers: [], characters: "a", filter: .modifiedKeys))
        XCTAssertEqual(KeyVisualizerSymbol.format(keyCode: 8, modifiers: [.command], characters: "c", filter: .modifiedKeys), "⌘C")

        // Command keys only drops Control-only and plain keys
        XCTAssertNil(KeyVisualizerSymbol.format(keyCode: 0, modifiers: [.control], characters: "a", filter: .commandKeysOnly))
        XCTAssertEqual(KeyVisualizerSymbol.format(keyCode: 8, modifiers: [.command, .shift], characters: "c", filter: .commandKeysOnly), "⇧⌘C")
    }
}

final class MultitouchClassifierTests: XCTestCase {
    private func cluster(count: Int, cx: Double, cy: Double, spread: Double = 0.08, vx: Double = 0) -> [MultitouchPoint] {
        (0..<count).map { i in
            let offset = (Double(i) - Double(count - 1) / 2.0) * spread
            return MultitouchPoint(id: Int32(i + 1), x: cx + offset, y: cy, vx: vx, vy: 0)
        }
    }

    func testThreeAndFourFingerSwipesAndFlickVelocity() {
        var reducer = GestureClassificationReducer()
        let t0 = Date(timeIntervalSince1970: 1000)

        // 3-finger travel swipe right
        XCTAssertNil(reducer.feed(points: cluster(count: 3, cx: 0.40, cy: 0.50), at: t0))
        XCTAssertEqual(reducer.feed(points: cluster(count: 3, cx: 0.56, cy: 0.50), at: t0.addingTimeInterval(0.05)), .threeFingerSwipeRight)
        // Same touch stays suppressed
        XCTAssertNil(reducer.feed(points: cluster(count: 3, cx: 0.72, cy: 0.50), at: t0.addingTimeInterval(0.08)))
        XCTAssertNil(reducer.feed(points: [], at: t0.addingTimeInterval(0.10)))

        // Debounce blocks immediate re-trigger
        XCTAssertNil(reducer.feed(points: cluster(count: 4, cx: 0.60, cy: 0.50), at: t0.addingTimeInterval(0.20)))
        XCTAssertNil(reducer.feed(points: cluster(count: 4, cx: 0.40, cy: 0.50), at: t0.addingTimeInterval(0.22)))
        XCTAssertNil(reducer.feed(points: [], at: t0.addingTimeInterval(0.24)))

        // After debounce, 4-finger fast flick left fires with shorter travel
        XCTAssertNil(reducer.feed(points: cluster(count: 4, cx: 0.55, cy: 0.50), at: t0.addingTimeInterval(0.60)))
        XCTAssertEqual(reducer.feed(points: cluster(count: 4, cx: 0.47, cy: 0.50, vx: -0.9), at: t0.addingTimeInterval(0.63)), .fourFingerSwipeLeft)
    }

    func testPinchInOutAndFourFingerTap() {
        var reducer = GestureClassificationReducer()
        let t0 = Date(timeIntervalSince1970: 2000)

        // Pinch in (spread shrinks > 22%)
        XCTAssertNil(reducer.feed(points: cluster(count: 4, cx: 0.5, cy: 0.5, spread: 0.12), at: t0))
        XCTAssertEqual(reducer.feed(points: cluster(count: 4, cx: 0.5, cy: 0.5, spread: 0.06), at: t0.addingTimeInterval(0.08)), .pinchIn)
        XCTAssertNil(reducer.feed(points: [], at: t0.addingTimeInterval(0.12)))

        // Pinch out after debounce
        XCTAssertNil(reducer.feed(points: cluster(count: 2, cx: 0.5, cy: 0.5, spread: 0.08), at: t0.addingTimeInterval(0.60)))
        XCTAssertEqual(reducer.feed(points: cluster(count: 2, cx: 0.5, cy: 0.5, spread: 0.14), at: t0.addingTimeInterval(0.68)), .pinchOut)
        XCTAssertNil(reducer.feed(points: [], at: t0.addingTimeInterval(0.72)))

        // Four-finger quick tap
        XCTAssertNil(reducer.feed(points: cluster(count: 4, cx: 0.5, cy: 0.5), at: t0.addingTimeInterval(1.20)))
        XCTAssertEqual(reducer.feed(points: [], at: t0.addingTimeInterval(1.30)), .fourFingerTap)
    }
}
