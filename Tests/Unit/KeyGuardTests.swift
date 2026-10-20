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
        shared.record(symbol: "a")
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
            shared.record(symbol: "⌘Q")
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
        for _ in 0..<20 { shared.record(symbol: "a") }
        XCTAssertEqual(shared.keycaps().map(\.symbol), ["a"], "a repeat of the newest coalesces")
        for symbol in ["b", "c", "d", "e", "f", "g", "h"] { shared.record(symbol: symbol) }
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
