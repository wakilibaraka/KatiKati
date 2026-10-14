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
