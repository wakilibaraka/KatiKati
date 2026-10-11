import XCTest
@testable import KatiKati

final class EdgeBarSlotTests: XCTestCase {
    private let metrics = PanelLayoutMetrics.tungstenEdge

    private func screen(origin: CGPoint = .zero, size: CGSize = CGSize(width: 1728, height: 1117), menuBar: CGFloat = 25) -> PanelScreenGeometry {
        let frame = CGRect(origin: origin, size: size)
        return PanelScreenGeometry(
            frame: frame,
            visibleFrame: CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height - menuBar),
            safeAreaTop: 0
        )
    }

    // MARK: Slot keys

    func testSlotKeyDescription() {
        XCTAssertEqual(EdgeSlotSet.SlotKey(display: nil, side: .right).description, "follow#edge-right")
        XCTAssertEqual(EdgeSlotSet.SlotKey(display: "D1", side: .left).description, "D1#edge-left")
    }

    func testNoSidesMeansNoSlots() {
        XCTAssertTrue(EdgeSlotSet.desiredSlots(placement: .followMouse, connectedKeys: ["A"], sides: []).isEmpty)
    }

    func testFollowPlacementYieldsOneKeyPerSide() {
        let slots = EdgeSlotSet.desiredSlots(placement: .followMouse, connectedKeys: ["A", "B"], sides: [.right, .left])
        XCTAssertEqual(slots, [
            EdgeSlotSet.SlotKey(display: nil, side: .left),
            EdgeSlotSet.SlotKey(display: nil, side: .right),
        ])
    }

    func testEveryDisplayPlacementCrossesDisplaysWithSides() {
        let slots = EdgeSlotSet.desiredSlots(placement: .allScreens, connectedKeys: ["A", "B"], sides: [.right])
        XCTAssertEqual(slots, [
            EdgeSlotSet.SlotKey(display: "A", side: .right),
            EdgeSlotSet.SlotKey(display: "B", side: .right),
        ])
    }

    func testEdgeKeysNeverCollideWithIslandKeys() {
        let edge = EdgeSlotSet.SlotKey(display: "A", side: .right).description
        let island = IslandSlotSet.SlotKey(display: "A", slot: 0).description
        XCTAssertNotEqual(edge, island)
    }

    // MARK: Geometry

    func testRightBarHugsRightEdgeAndLeftBarHugsLeft() {
        let s = screen()
        let r = PanelGeometry.edgeBarTargetFrame(side: .right, contentHeight: 300, width: 56, on: s, metrics: metrics)
        let l = PanelGeometry.edgeBarTargetFrame(side: .left, contentHeight: 300, width: 56, on: s, metrics: metrics)
        XCTAssertEqual(r.maxX, s.visibleFrame.maxX - 8, accuracy: 0.001)
        XCTAssertEqual(l.minX, s.visibleFrame.minX + 8, accuracy: 0.001)
        XCTAssertEqual(r.height, 300)
    }

    func testTallContentIsClampedBetweenMenuBarAndBottomBar() {
        let s = screen()
        let f = PanelGeometry.edgeBarTargetFrame(side: .right, contentHeight: 5000, width: 56, on: s, metrics: metrics)
        XCTAssertGreaterThanOrEqual(f.minY, metrics.bottomGap + metrics.panelHeight)
        XCTAssertLessThanOrEqual(f.maxY, s.topUsableY + 0.001)
        XCTAssertTrue(s.visibleFrame.contains(f))
    }

    func testMinimumSpacingIsEnforced() {
        let s = screen()
        let f = PanelGeometry.edgeBarTargetFrame(side: .right, contentHeight: 5000, width: 56, on: s, gap: 0, margin: 0, metrics: metrics)
        XCTAssertEqual(s.visibleFrame.maxX - f.maxX, PanelGeometry.edgeBarMinimumSpacing, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(f.minY - (metrics.bottomGap + metrics.panelHeight), PanelGeometry.edgeBarMinimumSpacing - 0.001)
    }

    func testNonZeroOriginSecondaryDisplayStaysOnItsOwnDisplay() {
        let s = screen(origin: CGPoint(x: -1920, y: -300), size: CGSize(width: 1920, height: 1080))
        for side in EdgeSide.allCases {
            let f = PanelGeometry.edgeBarTargetFrame(side: side, contentHeight: 600, width: 56, on: s, metrics: metrics)
            XCTAssertTrue(s.visibleFrame.contains(f), "\(side) must stay inside visibleFrame")
        }
    }

    func testShortAndNarrowScreensNeverGoNegative() {
        let short = screen(size: CGSize(width: 1280, height: 60))
        let f = PanelGeometry.edgeBarTargetFrame(side: .left, contentHeight: 400, width: 56, on: short, metrics: metrics)
        XCTAssertGreaterThanOrEqual(f.height, 0)
        XCTAssertEqual(f.height, 0, "no room above the bottom bar collapses the bar")
        let narrow = screen(size: CGSize(width: 40, height: 800))
        let n = PanelGeometry.edgeBarTargetFrame(side: .right, contentHeight: 200, width: 56, on: narrow, metrics: metrics)
        XCTAssertGreaterThanOrEqual(n.width, 0)
        XCTAssertGreaterThanOrEqual(n.minX, narrow.frame.minX)
    }

    func testNotchSafeAreaCapsTheTop() {
        var s = screen()
        s.safeAreaTop = 60
        let f = PanelGeometry.edgeBarTargetFrame(side: .right, contentHeight: 5000, width: 56, on: s, metrics: metrics)
        XCTAssertLessThanOrEqual(f.maxY, s.topUsableY + 0.001)
    }

    // MARK: Presets

    func testPresetsResolveContentPerEdge() {
        XCTAssertTrue(EdgeBarPreset.off.content(statusSide: .right).isEmpty)
        XCTAssertEqual(EdgeBarPreset.notes.content(statusSide: .left), [.right: [.notes]])
        XCTAssertEqual(EdgeBarPreset.status.content(statusSide: .left), [.left: [.status]])
        XCTAssertEqual(EdgeBarPreset.notesAndStatus.content(statusSide: .right), [.right: [.notes, .status]])
        XCTAssertEqual(EdgeBarPreset.notesAndStatus.content(statusSide: .left), [.right: [.notes], .left: [.status]])
    }

    func testActiveSidesAndRawValuesAreStable() {
        XCTAssertEqual(EdgeBarPreset.notesAndStatus.activeSides(statusSide: .left), [.left, .right])
        XCTAssertEqual(EdgeBarPreset.allCases.map(\.rawValue), ["off", "notes", "notesAndStatus", "status"])
    }

    // MARK: Layout + popup

    func testContentHeightStacksTilesWithSpacingAndPadding() {
        XCTAssertEqual(EdgeBarLayout.contentHeight([]), 0)
        XCTAssertEqual(EdgeBarLayout.contentHeight([.notes]), EdgeBarLayout.notesTileHeight + 20)
        XCTAssertEqual(
            EdgeBarLayout.contentHeight([.notes, .status]),
            EdgeBarLayout.notesTileHeight + EdgeBarLayout.statusTileHeight + EdgeBarLayout.tileSpacing + 20
        )
    }

    func testTileFramesFlowTopToBottomInsideTheBar() {
        let content: [EdgeBarContent] = [.notes, .status]
        let height = EdgeBarLayout.contentHeight(content)
        let bar = CGRect(x: 1000, y: 200, width: EdgeBarLayout.width, height: height)
        let notes = EdgeBarLayout.tileFrame(at: 0, of: content, in: bar)
        let status = EdgeBarLayout.tileFrame(at: 1, of: content, in: bar)
        XCTAssertEqual(notes.maxY, bar.maxY - EdgeBarLayout.verticalPadding)
        XCTAssertEqual(status.minY, bar.minY + EdgeBarLayout.verticalPadding, accuracy: 0.001)
        XCTAssertEqual(notes.minY - status.maxY, EdgeBarLayout.tileSpacing, accuracy: 0.001)
        XCTAssertTrue(bar.contains(notes) && bar.contains(status))
        XCTAssertEqual(EdgeBarLayout.tileFrame(at: 5, of: content, in: bar), .zero)
    }

    func testPopupOpensInwardAndClampsToVisibleFrame() {
        let visible = CGRect(x: 0, y: 0, width: 1728, height: 1092)
        let anchor = CGRect(x: 1664, y: 500, width: 56, height: 40)
        let right = PanelGeometry.edgeBarPopupFrame(side: .right, anchor: anchor, size: CGSize(width: 240, height: 160), visibleFrame: visible)
        XCTAssertEqual(right.maxX, anchor.minX - 8, accuracy: 0.001)
        XCTAssertEqual(right.midY, anchor.midY, accuracy: 0.001)
        let leftAnchor = CGRect(x: 8, y: 20, width: 56, height: 40)
        let left = PanelGeometry.edgeBarPopupFrame(side: .left, anchor: leftAnchor, size: CGSize(width: 240, height: 160), visibleFrame: visible)
        XCTAssertEqual(left.minX, leftAnchor.maxX + 8, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(left.minY, visible.minY, "clamped above the bottom")
        XCTAssertTrue(visible.contains(left) && visible.contains(right))
    }

    func testPopupOversizedAndNonZeroOriginStaysInside() {
        let visible = CGRect(x: -1920, y: -300, width: 300, height: 200)
        let f = PanelGeometry.edgeBarPopupFrame(side: .right, anchor: CGRect(x: -1700, y: -200, width: 56, height: 40),
                                                size: CGSize(width: 900, height: 900), visibleFrame: visible)
        XCTAssertTrue(visible.contains(f))
    }

    // MARK: Widgets (7A-8a)

    func testWidgetTileParseDedupesDropsUnknownAndKeepsOrder() {
        XCTAssertEqual(WidgetTile.parse("nowPlaying, weather,nowPlaying,bogus"), [.nowPlaying, .weather])
        XCTAssertEqual(WidgetTile.parse(nil), [])
        XCTAssertEqual(WidgetTile.parse(""), [])
        XCTAssertEqual(WidgetTile.serialize([.weather, .nowPlaying]), "weather,nowPlaying")
        XCTAssertEqual(WidgetTile.allCases.map(\.rawValue), ["weather", "nowPlaying", "bluetooth"], "stored ids are frozen")
    }

    func testCompositionPutsWidgetsOnTheLeftAndKeepsPresetContent() {
        let none = EdgeBarComposition.resolve(preset: .notesAndStatus, statusSide: .right, widgets: [])
        XCTAssertEqual(none, [.right: [.notes, .status]])
        let withWidgets = EdgeBarComposition.resolve(preset: .notes, statusSide: .right, widgets: [.weather, .nowPlaying])
        XCTAssertEqual(withWidgets[.left], [.widget(.weather), .widget(.nowPlaying)])
        XCTAssertEqual(withWidgets[.right], [.notes])
        let onlyWidgets = EdgeBarComposition.resolve(preset: .off, statusSide: .right, widgets: [.weather])
        XCTAssertEqual(onlyWidgets, [.left: [.widget(.weather)]])
    }

    func testLeftStatusSitsBelowWidgets() {
        let r = EdgeBarComposition.resolve(preset: .status, statusSide: .left, widgets: [.weather])
        XCTAssertEqual(r[.left], [.widget(.weather), .status])
    }

    func testWidgetTilesAreIncludedInBarHeight() {
        let h = EdgeBarLayout.contentHeight([.widget(.weather), .widget(.nowPlaying)])
        XCTAssertEqual(h, 2 * EdgeBarLayout.widgetTileHeight + EdgeBarLayout.tileSpacing + 2 * EdgeBarLayout.verticalPadding)
    }
}
