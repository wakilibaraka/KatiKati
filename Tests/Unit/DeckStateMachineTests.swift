import XCTest
@testable import KatiKati

final class DeckStateMachineTests: XCTestCase {
    private func step(_ s: DeckState, _ e: DeckEvent, _ c: DeckContext = DeckContext()) -> DeckState {
        DeckStateMachine.reduce(s, e, c)
    }

    func testPointerEntryFansOnlyFromRest() {
        XCTAssertEqual(step(.rest, .pointerEntered), .fan)
        XCTAssertEqual(step(.fan, .pointerEntered), .fan)
        XCTAssertEqual(step(.expanded("a"), .pointerEntered), .expanded("a"))
    }

    func testConfirmedExitFoldsAFanButNeverAnOpenNote() {
        XCTAssertEqual(step(.fan, .pointerExitConfirmed), .rest)
        XCTAssertEqual(step(.expanded("a"), .pointerExitConfirmed), .expanded("a"))
        XCTAssertEqual(step(.rest, .pointerExitConfirmed), .rest)
    }

    func testDraggingAndKeepOpenSuppressFolding() {
        var ctx = DeckContext(); ctx.isDragging = true
        XCTAssertEqual(step(.fan, .pointerExitConfirmed, ctx), .fan)
        XCTAssertEqual(step(.fan, .idle(99), ctx), .fan)
        ctx = DeckContext(keepOpen: true)
        XCTAssertEqual(step(.fan, .pointerExitConfirmed, ctx), .fan)
        XCTAssertEqual(step(.fan, .idle(99), ctx), .fan)
    }

    func testClickingTabsTogglesTheSheet() {
        XCTAssertEqual(step(.fan, .tabClicked("a")), .expanded("a"))
        XCTAssertEqual(step(.expanded("a"), .tabClicked("a")), .fan)
        XCTAssertEqual(step(.expanded("a"), .tabClicked("b")), .expanded("b"))
    }

    func testHoverOpensOnlyWhenEnabledAndNotDragging() {
        XCTAssertEqual(step(.fan, .hoverRested("a")), .fan)
        var ctx = DeckContext(); ctx.openOnHover = true
        XCTAssertEqual(step(.fan, .hoverRested("a"), ctx), .expanded("a"))
        XCTAssertEqual(step(.expanded("a"), .hoverRested("a"), ctx), .expanded("a"))
        ctx.isDragging = true
        XCTAssertEqual(step(.fan, .hoverRested("a"), ctx), .fan)
    }

    func testIdleTimeoutsDifferForFanAndNote() {
        XCTAssertEqual(step(.fan, .idle(DeckTiming.fanIdleTimeout)), .fan, "needs to exceed, not equal")
        XCTAssertEqual(step(.fan, .idle(DeckTiming.fanIdleTimeout + 0.1)), .rest)
        XCTAssertEqual(step(.expanded("a"), .idle(30)), .expanded("a"))
        XCTAssertEqual(step(.expanded("a"), .idle(61)), .rest)
        var ctx = DeckContext(); ctx.openNoteIsPinned = true
        XCTAssertEqual(step(.expanded("a"), .idle(999), ctx), .expanded("a"), "pinned notes never idle shut")
        XCTAssertEqual(step(.expanded("a"), .idle(61), DeckContext(keepOpen: true)), .fan, "kept-open deck falls back to the fan")
    }

    func testEscapePeelsOneLayerAtATime() {
        XCTAssertEqual(step(.expanded("a"), .escape), .fan)
        XCTAssertEqual(step(.fan, .escape), .rest)
        XCTAssertEqual(step(.fan, .escape, DeckContext(keepOpen: true)), .fan)
        XCTAssertEqual(step(.rest, .escape), .rest)
    }

    func testOutsideClickClosesTheSheetToTheRestingState() {
        XCTAssertEqual(step(.expanded("a"), .outsideClick), .rest)
        XCTAssertEqual(step(.expanded("a"), .outsideClick, DeckContext(keepOpen: true)), .fan)
        XCTAssertEqual(step(.fan, .outsideClick), .fan, "only an open note reacts")
    }

    func testRemovedNoteClosesItsSheetOnly() {
        XCTAssertEqual(step(.expanded("a"), .noteRemoved("a")), .fan)
        XCTAssertEqual(step(.expanded("a"), .noteRemoved("b")), .expanded("a"))
        XCTAssertEqual(step(.fan, .noteRemoved("a")), .fan)
    }

    func testKeepOpenToggleRepointsAnIdleDeck() {
        XCTAssertEqual(step(.rest, .keepOpenChanged, DeckContext(keepOpen: true)), .fan)
        XCTAssertEqual(step(.fan, .keepOpenChanged, DeckContext(keepOpen: false)), .rest)
        XCTAssertEqual(step(.expanded("a"), .keepOpenChanged, DeckContext(keepOpen: true)), .expanded("a"))
    }

    func testRankOrdersStatesForGrowShrinkDecisions() {
        XCTAssertLessThan(DeckState.rest.rank, DeckState.fan.rank)
        XCTAssertLessThan(DeckState.fan.rank, DeckState.expanded("a").rank)
        XCTAssertEqual(DeckState.expanded("a").expandedID, "a")
        XCTAssertNil(DeckState.fan.expandedID)
    }

    func testSettingsRulesClampAndFallBack() {
        XCTAssertEqual(DeckSettingsRules.clampedScale(nil), 1)
        XCTAssertEqual(DeckSettingsRules.clampedScale(.nan), 1)
        XCTAssertEqual(DeckSettingsRules.clampedScale(5), 1.4)
        XCTAssertEqual(DeckSettingsRules.clampedScale(0.1), 0.8)
        XCTAssertEqual(DeckSettingsRules.clampedRatio(nil), 0.5)
        XCTAssertEqual(DeckSettingsRules.clampedRatio(-3), 0)
        XCTAssertEqual(DeckSettingsRules.clampedRatio(7), 1)
        XCTAssertEqual(EdgeTileStyle.allCases.map(\.rawValue), ["glass", "coloured"], "stored ids are frozen")
    }
}
