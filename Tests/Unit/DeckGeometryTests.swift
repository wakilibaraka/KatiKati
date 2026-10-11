import XCTest
@testable import KatiKati

final class DeckGeometryTests: XCTestCase {
    private let m = DeckMetrics()
    private let visible = CGRect(x: 0, y: 0, width: 1728, height: 1092)

    func testScaleMultipliesAndRoundsToWholePoints() {
        XCTAssertEqual(m.tabWidth, 30)
        let big = DeckMetrics(scale: 1.4)
        XCTAssertEqual(big.tabWidth, 42)
        XCTAssertEqual(big.tabLap, 56)
        for v in [big.pillWidth, big.dashHeight, big.bleed, big.buttonSize, DeckMetrics(scale: 1.13).tabLap] {
            XCTAssertEqual(v, v.rounded(), "whole points only")
        }
        XCTAssertEqual(DeckMetrics(scale: 99).scale, 2, "scale is clamped")
        XCTAssertEqual(DeckMetrics(scale: 0).scale, 0.5)
    }

    func testPillHeightGrowsWithItemsAndCapsAtMaxDashesPlusOverflowDash() {
        XCTAssertEqual(DeckGeometry.pillHeight(m, itemCount: 1), 14 + 14)
        XCTAssertEqual(DeckGeometry.pillHeight(m, itemCount: 0), DeckGeometry.pillHeight(m, itemCount: 1), "never zero-height")
        let capped = DeckGeometry.pillHeight(m, itemCount: 14)
        XCTAssertEqual(DeckGeometry.pillHeight(m, itemCount: 40), capped + m.dashHeight + m.dashGap)
    }

    func testLayoutPitchTracksLongestLabelWithinClamp() {
        let short = DeckGeometry.layout(m, panelHeight: 1000, count: 3, hasMore: false, longestLabel: 10)
        XCTAssertEqual(short.pitch, m.pitchMin)
        let long = DeckGeometry.layout(m, panelHeight: 1000, count: 3, hasMore: false, longestLabel: 500)
        XCTAssertEqual(long.pitch, m.pitchMax)
        let mid = DeckGeometry.layout(m, panelHeight: 1000, count: 3, hasMore: false, longestLabel: 60)
        XCTAssertEqual(mid.pitch, 80)
        XCTAssertEqual(mid.itemHeight, mid.pitch + m.tabLap)
        XCTAssertEqual(mid.spacing, -m.tabLap)
    }

    func testShortScreensShrinkPitchToTheFloorNotBelow() {
        let tight = DeckGeometry.layout(m, panelHeight: 400, count: 5, hasMore: true, longestLabel: 200)
        XCTAssertLessThan(tight.pitch, m.pitchMax)
        XCTAssertGreaterThanOrEqual(tight.pitch, m.pitchFloor)
        let tiny = DeckGeometry.layout(m, panelHeight: 120, count: 5, hasMore: false, longestLabel: 200)
        XCTAssertEqual(tiny.pitch, m.pitchFloor)
    }

    func testStackHeightAddsMoreTabAndButtons() {
        let base = DeckGeometry.layout(m, panelHeight: 1000, count: 3, hasMore: false)
        XCTAssertEqual(base.stackHeight, 2 * base.pitch + base.itemHeight)
        let more = DeckGeometry.layout(m, panelHeight: 1000, count: 3, hasMore: true)
        XCTAssertEqual(more.stackHeight, base.stackHeight + m.tabGap + m.moreTabHeight)
        let withButtons = DeckGeometry.layout(m, panelHeight: 1000, count: 3, hasMore: false, buttons: 2)
        XCTAssertEqual(withButtons.stackHeight, base.stackHeight + 2 * (m.buttonGap + m.buttonSize))
        XCTAssertEqual(base.center(0), base.pitch / 2)
        XCTAssertEqual(base.center(2), base.pitch * 2 + base.itemHeight / 2)
    }

    // MARK: Panel frames

    func testRestFrameHugsTheEdgeAndFollowsYRatio() {
        let bottom = DeckGeometry.restFrame(m, side: .right, visible: visible, itemCount: 3, yRatio: 0)
        let top = DeckGeometry.restFrame(m, side: .right, visible: visible, itemCount: 3, yRatio: 1)
        XCTAssertEqual(bottom.maxX, visible.maxX)
        XCTAssertEqual(bottom.minY, visible.minY)
        XCTAssertEqual(top.maxY, visible.maxY)
        let left = DeckGeometry.restFrame(m, side: .left, visible: visible, itemCount: 3, yRatio: 0.5)
        XCTAssertEqual(left.minX, visible.minX)
        XCTAssertTrue(visible.contains(left) && visible.contains(top) && visible.contains(bottom))
        XCTAssertEqual(DeckGeometry.restFrame(m, side: .right, visible: visible, itemCount: 3, yRatio: 9),
                       top, "ratio clamps")
    }

    func testFanFrameIsCentredOnThePillAndClampedInside() {
        let mid = DeckGeometry.fanFrame(m, side: .right, visible: visible, stackHeight: 300, itemCount: 3, yRatio: 0.5)
        let rest = DeckGeometry.restFrame(m, side: .right, visible: visible, itemCount: 3, yRatio: 0.5)
        XCTAssertEqual(mid.midY, rest.midY, accuracy: 1)
        XCTAssertEqual(mid.maxX, visible.maxX)
        XCTAssertEqual(mid.width, m.tabWidth + m.bleed + m.shadowRoom)
        let low = DeckGeometry.fanFrame(m, side: .left, visible: visible, stackHeight: 300, itemCount: 3, yRatio: 0)
        XCTAssertGreaterThanOrEqual(low.minY, visible.minY + 12)
        let tall = DeckGeometry.fanFrame(m, side: .right, visible: visible, stackHeight: 5000, itemCount: 3, yRatio: 0.5)
        XCTAssertTrue(visible.contains(tall))
    }

    func testNonZeroOriginDisplayStaysInsideItsVisibleFrame() {
        let v = CGRect(x: -1920, y: -300, width: 1920, height: 1055)
        for side in EdgeSide.allCases {
            for ratio in [0, 0.5, 1] as [CGFloat] {
                XCTAssertTrue(v.contains(DeckGeometry.restFrame(m, side: side, visible: v, itemCount: 5, yRatio: ratio)))
                XCTAssertTrue(v.contains(DeckGeometry.fanFrame(m, side: side, visible: v, stackHeight: 400, itemCount: 5, yRatio: ratio)))
            }
        }
    }

    func testPillDragMapsPointerToRatioAndSnapsSide() {
        let h = DeckGeometry.pillHeight(m, itemCount: 3)
        XCTAssertEqual(DeckGeometry.yRatio(forPointerY: visible.minY, pillHeight: h, visible: visible), 0)
        XCTAssertEqual(DeckGeometry.yRatio(forPointerY: visible.maxY + 500, pillHeight: h, visible: visible), 1)
        let mid = DeckGeometry.yRatio(forPointerY: visible.midY, pillHeight: h, visible: visible)
        XCTAssertEqual(mid, 0.5, accuracy: 0.01)
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        XCTAssertEqual(DeckGeometry.snapSide(pointerX: 100, screenFrame: screen), .left)
        XCTAssertEqual(DeckGeometry.snapSide(pointerX: 1700, screenFrame: screen), .right)
    }

    // MARK: Drag reorder

    func testDragTargetNeedsSixtyPercentOfASlot() {
        XCTAssertEqual(DeckGeometry.dragTarget(from: 2, dy: 0.5 * 80, pitch: 80, count: 5), 2, "halfway is not enough")
        XCTAssertEqual(DeckGeometry.dragTarget(from: 2, dy: 0.61 * 80, pitch: 80, count: 5), 3)
        XCTAssertEqual(DeckGeometry.dragTarget(from: 2, dy: -0.61 * 80, pitch: 80, count: 5), 1)
        XCTAssertEqual(DeckGeometry.dragTarget(from: 0, dy: -999, pitch: 80, count: 5), 0)
        XCTAssertEqual(DeckGeometry.dragTarget(from: 4, dy: 999, pitch: 80, count: 5), 4)
    }

    func testDragShiftStepsNeighboursAside() {
        XCTAssertEqual(DeckGeometry.dragShift(index: 1, from: 0, to: 2, pitch: 80), -80)
        XCTAssertEqual(DeckGeometry.dragShift(index: 2, from: 0, to: 2, pitch: 80), -80)
        XCTAssertEqual(DeckGeometry.dragShift(index: 3, from: 0, to: 2, pitch: 80), 0)
        XCTAssertEqual(DeckGeometry.dragShift(index: 1, from: 3, to: 1, pitch: 80), 80)
        XCTAssertEqual(DeckGeometry.dragShift(index: 0, from: 3, to: 1, pitch: 80), 0)
        XCTAssertEqual(DeckGeometry.dragShift(index: 3, from: 3, to: 1, pitch: 80), 0, "the dragged tab itself")
    }
}

final class VerticalLabelLayoutTests: XCTestCase {
    private let measure = VerticalLabelMeasure(rotatedWidth: { CGFloat($0.count) * 8 }, uprightAdvance: 16)

    func testLatinStaysOneRotatedRun() {
        XCTAssertEqual(VerticalLabelLayout.runs(for: "SHIP CHECKLIST"), [VerticalLabelRun(text: "SHIP CHECKLIST", orientation: .rotated)])
    }

    func testCJKAndEmojiAreUprightOneGlyphEach() {
        let runs = VerticalLabelLayout.runs(for: "买菜🛒")
        XCTAssertEqual(runs.map(\.orientation), [.upright, .upright, .upright])
        XCTAssertEqual(runs.map(\.text), ["买", "菜", "🛒"])
    }

    func testMixedScriptKeepsWordsTogetherAndSpacesAttachToRotatedText() {
        let runs = VerticalLabelLayout.runs(for: "WIFI 密码")
        XCTAssertEqual(runs, [
            VerticalLabelRun(text: "WIFI ", orientation: .rotated),
            VerticalLabelRun(text: "密", orientation: .upright),
            VerticalLabelRun(text: "码", orientation: .upright),
        ])
    }

    func testSpaceBetweenUprightGlyphsStaysUpright() {
        XCTAssertEqual(VerticalLabelLayout.runs(for: "买 菜").map(\.orientation), [.upright, .upright, .upright])
        XCTAssertTrue(VerticalLabelLayout.runs(for: "").isEmpty)
    }

    func testFittingRunsTruncatesWithAnUprightEllipsis() {
        let full = VerticalLabelLayout.fittingRuns(for: "short", maxAdvance: 200, measure: measure)
        XCTAssertEqual(full, [VerticalLabelRun(text: "SHORT", orientation: .rotated)])
        let cut = VerticalLabelLayout.fittingRuns(for: "a very long title indeed", maxAdvance: 60, measure: measure)
        XCTAssertEqual(cut.last, VerticalLabelRun(text: "…", orientation: .upright))
        XCTAssertLessThanOrEqual(measure.total(cut), 60)
        XCTAssertGreaterThan(cut.count, 1)
        let none = VerticalLabelLayout.fittingRuns(for: "title", maxAdvance: 10, measure: measure)
        XCTAssertEqual(none, [VerticalLabelRun(text: "…", orientation: .upright)], "no room: ellipsis only")
    }
}
