import XCTest
@testable import KatiKati

final class HyperkeyEngineTests: XCTestCase {
    private let bound: Set<UInt16> = [13, 8]
    private func feed(_ e: inout HyperkeyEngine, _ code: UInt16, down: Bool, rep: Bool = false) -> HyperkeyEngine.Decision {
        e.handle(keyCode: code, isDown: down, isRepeat: rep) { bound.contains($0) }
    }

    func testBoundKeyWhileHeldFiresOnceAndSwallowsRepeatAndRelease() {
        var e = HyperkeyEngine()
        XCTAssertEqual(feed(&e, 79, down: true), .swallow)
        XCTAssertEqual(feed(&e, 13, down: true), .fire(keyCode: 13))
        XCTAssertEqual(feed(&e, 13, down: true, rep: true), .swallow)
        XCTAssertEqual(feed(&e, 13, down: false), .swallow)
        XCTAssertEqual(feed(&e, 79, down: false), .swallow)
        XCTAssertFalse(e.isHeld)
    }

    func testWithoutHyperKeysPassThrough() {
        var e = HyperkeyEngine()
        XCTAssertEqual(feed(&e, 13, down: true), .passThrough)
        XCTAssertEqual(feed(&e, 13, down: false), .passThrough)
    }

    func testUnboundKeyWhileHeldPassesThrough() {
        var e = HyperkeyEngine()
        _ = feed(&e, 79, down: true)
        XCTAssertEqual(feed(&e, 0, down: true), .passThrough)
        XCTAssertEqual(feed(&e, 0, down: false), .passThrough)
    }

    func testReleasingHyperFirstStillSwallowsLateKeyUpOnlyIfNotCleared() {
        var e = HyperkeyEngine()
        _ = feed(&e, 79, down: true)
        _ = feed(&e, 8, down: true)
        _ = feed(&e, 79, down: false)
        // Hyper released before the key: the key's release is a plain release now.
        XCTAssertEqual(feed(&e, 8, down: false), .passThrough)
    }
}

final class HyperkeyRemapTests: XCTestCase {
    func testAddingKeepsUserMappingsAndReplacesCapsLock() {
        let user: [HyperkeyRemap.Mapping] = [["HIDKeyboardModifierMappingSrc": 1, "HIDKeyboardModifierMappingDst": 2],
                                             ["HIDKeyboardModifierMappingSrc": HyperkeyRemap.capsLock, "HIDKeyboardModifierMappingDst": 9]]
        let added = HyperkeyRemap.adding(to: user)
        XCTAssertEqual(added.count, 2)
        XCTAssertTrue(added.contains(HyperkeyRemap.ours))
        XCTAssertTrue(added.contains(user[0]))
    }

    func testRemovingRestoresUserMappings() {
        let user: [HyperkeyRemap.Mapping] = [["HIDKeyboardModifierMappingSrc": 1, "HIDKeyboardModifierMappingDst": 2]]
        XCTAssertEqual(HyperkeyRemap.removing(from: HyperkeyRemap.adding(to: user)), user)
        XCTAssertEqual(HyperkeyRemap.removing(from: []), [])
    }

    func testJSONShape() {
        XCTAssertEqual(HyperkeyRemap.json([]), "{\"UserKeyMapping\":[]}")
        XCTAssertTrue(HyperkeyRemap.json([HyperkeyRemap.ours]).contains("\"HIDKeyboardModifierMappingDst\":30064771181"))
    }

    func testParseReadsTheTableAndTheBarePlist() {
        let ours = [HyperkeyRemap.ours]
        let table = """
        RegistryID  Key                   Value
        10000075d   UserKeyMapping   (null)
        100000a16   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771181;
                HIDKeyboardModifierMappingSrc = 30064771129;
            }
        )
        100000b70   UserKeyMapping   (null)
        """
        XCTAssertEqual(HyperkeyRemap.parse(table), ours)
        XCTAssertEqual(HyperkeyRemap.parse("(\n    {\n    HIDKeyboardModifierMappingDst = 30064771181;\n    HIDKeyboardModifierMappingSrc = 30064771129;\n    }\n)"), ours)
        XCTAssertEqual(HyperkeyRemap.parse("RegistryID  Key  Value\n1  UserKeyMapping   (null)"), [])
        XCTAssertEqual(HyperkeyRemap.parse(""), [])
    }

    func testSuperKeyForwardsModifiersForUnboundKeys() {
        var engine = HyperkeyEngine()
        let cfg = HyperkeyConfig(modifierMode: .superKey, tapAction: .off, forwardToSystem: true)
        XCTAssertEqual(engine.handle(keyCode: HyperkeyEngine.hyperKeyCode, isDown: true, isRepeat: false, config: cfg) { _ in false }, .swallow)
        XCTAssertEqual(engine.handle(keyCode: 4, isDown: true, isRepeat: false, config: cfg) { _ in false }, .forwardWithModifiers(.superKey))
        XCTAssertEqual(engine.handle(keyCode: 4, isDown: false, isRepeat: false, config: cfg) { _ in false }, .forwardWithModifiers(.superKey))
    }

    func testTapIfAloneEmitsActionOnlyOnQuickUncombinedTap() {
        var engine = HyperkeyEngine()
        let t0 = Date(timeIntervalSince1970: 1000)
        let cfg = HyperkeyConfig(modifierMode: .hyper, tapAction: .escape, forwardToSystem: true, tapThreshold: 0.20)

        // Quick tap alone -> escape
        XCTAssertEqual(engine.handle(keyCode: HyperkeyEngine.hyperKeyCode, isDown: true, isRepeat: false, at: t0, config: cfg) { _ in false }, .swallow)
        XCTAssertEqual(engine.handle(keyCode: HyperkeyEngine.hyperKeyCode, isDown: false, isRepeat: false, at: t0.addingTimeInterval(0.08), config: cfg) { _ in false }, .tapIfAlone(.escape))

        // Combined with another key -> no tapIfAlone
        XCTAssertEqual(engine.handle(keyCode: HyperkeyEngine.hyperKeyCode, isDown: true, isRepeat: false, at: t0, config: cfg) { _ in false }, .swallow)
        _ = engine.handle(keyCode: 4, isDown: true, isRepeat: false, at: t0.addingTimeInterval(0.02), config: cfg) { _ in false }
        XCTAssertEqual(engine.handle(keyCode: HyperkeyEngine.hyperKeyCode, isDown: false, isRepeat: false, at: t0.addingTimeInterval(0.08), config: cfg) { _ in false }, .swallow)

        // Held past threshold -> no tapIfAlone
        XCTAssertEqual(engine.handle(keyCode: HyperkeyEngine.hyperKeyCode, isDown: true, isRepeat: false, at: t0, config: cfg) { _ in false }, .swallow)
        XCTAssertEqual(engine.handle(keyCode: HyperkeyEngine.hyperKeyCode, isDown: false, isRepeat: false, at: t0.addingTimeInterval(0.35), config: cfg) { _ in false }, .swallow)
    }

    func testSourceKeySwitchingReplacesOldF18Mapping() {
        let withCaps = HyperkeyRemap.adding(source: HyperkeyRemap.capsLock, to: [])
        let switched = HyperkeyRemap.adding(source: HyperkeyRemap.rightCommand, to: withCaps)
        XCTAssertEqual(switched, [HyperkeyRemap.mapping(for: HyperkeyRemap.rightCommand)])
        XCTAssertEqual(HyperkeyRemap.removing(from: switched), [])
    }
}
