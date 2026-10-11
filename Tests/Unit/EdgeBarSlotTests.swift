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

    private func resolve(_ preset: EdgeBarPreset, primary: EdgeSide = .right, widgets: [WidgetTile] = [],
                         productivity: [ProductivityItem] = [], custom: [EdgeItem: EdgePlacement] = [:],
                         built: Set<ProductivityItem> = []) -> [EdgeSide: [EdgeBarContent]] {
        EdgeBarComposition.resolve(preset: preset, primary: primary, widgets: widgets, productivity: productivity,
                                   custom: custom, built: built)
    }

    func testPresetsResolveContentPerEdge() {
        XCTAssertTrue(resolve(.off, widgets: [.weather]).isEmpty, "off = nothing, widgets included")
        XCTAssertEqual(resolve(.notes), [.right: [.notes, .newNote, .settings]])
        XCTAssertEqual(resolve(.status, primary: .left), [.left: [.status]])
        XCTAssertEqual(resolve(.notesAndStatus), [.right: [.notes, .newNote, .status, .settings]])
    }

    func testPrimarySideFlipsEveryPreset() {
        XCTAssertEqual(resolve(.notes, primary: .left), [.left: [.notes, .newNote, .settings]])
        XCTAssertEqual(resolve(.notesAndStatus, primary: .left, widgets: [.weather]),
                       [.left: [.notes, .newNote, .status, .settings], .right: [.widget(.weather)]])
    }

    func testProductivityAndRestSplitsTheSides() {
        let r = resolve(.productivityAndRest, widgets: WidgetTile.allCases, productivity: ProductivityItem.allCases,
                        built: [.reminders, .time])
        XCTAssertEqual(r[.right], [.notes, .newNote, .productivity(.reminders), .productivity(.time), .settings])
        XCTAssertEqual(r[.left], [.widget(.weather), .widget(.nowPlaying), .widget(.bluetooth), .status])
        let swapped = resolve(.productivityAndRest, primary: .left, widgets: [.bluetooth], productivity: [.time], built: [.time])
        XCTAssertEqual(swapped[.left], [.notes, .newNote, .productivity(.time), .settings])
        XCTAssertEqual(swapped[.right], [.widget(.bluetooth), .status])
    }

    func testUnbuiltAndDisabledProductivityItemsNeverRender() {
        let none = resolve(.productivityAndRest, productivity: ProductivityItem.allCases)
        XCTAssertEqual(none[.right], [.notes, .newNote, .settings], "no placeholders for unbuilt items")
        let off = resolve(.productivityAndRest, productivity: [.time], built: [.time, .tasks])
        XCTAssertEqual(off[.right], [.notes, .newNote, .productivity(.time), .settings])
    }

    func testCustomLayoutMovesHidesAndFallsBack() {
        let custom: [EdgeItem: EdgePlacement] = [.notes: .left, .newNote: .left, .status: .right, .weather: .hidden, .settings: .hidden]
        let r = resolve(.custom, custom: custom)
        XCTAssertEqual(r[.left]?.prefix(2), [.notes, .newNote][...])
        XCTAssertTrue(r[.right]?.contains(.status) ?? false)
        XCTAssertFalse((r[.left] ?? []).contains(.widget(.weather)) || (r[.right] ?? []).contains(.widget(.weather)))
        XCTAssertFalse((r[.left] ?? []).contains(.settings) || (r[.right] ?? []).contains(.settings))
        XCTAssertTrue(r[.left]?.contains(.widget(.nowPlaying)) ?? false, "missing item uses the Productivity + Rest side")
    }

    func testCustomPlacementsParseAndSerialize() {
        let parsed = EdgeItem.parsePlacements("notes:right, bogus:left,weather:hidden,time:up,status:left,status:right")
        XCTAssertEqual(parsed, [.notes: .right, .weather: .hidden, .status: .right])
        XCTAssertEqual(EdgeItem.serialize(parsed), "notes:right,weather:hidden,status:right", "canonical order")
        XCTAssertTrue(EdgeItem.parsePlacements(nil).isEmpty)
    }

    func testProductivityIdsAndPresetRawValuesAreFrozen() {
        XCTAssertEqual(ProductivityItem.allCases.map(\.rawValue),
                       ["reminders", "alarms", "time", "tasks", "clipboard", "capture", "windows"])
        XCTAssertEqual(ProductivityItem.parse("time,bogus,time,tasks"), [.time, .tasks])
        XCTAssertEqual(EdgeBarPreset.allCases.map(\.rawValue),
                       ["off", "notes", "notesAndStatus", "status", "productivityAndRest", "custom"])
        XCTAssertEqual(EdgeBarPreset.default, .productivityAndRest)
        XCTAssertEqual(EdgeItem.allCases.count, 14)
    }

    func testWidgetTilesAreIncludedInBarHeight() {
        let h = EdgeBarLayout.contentHeight([.widget(.weather), .widget(.nowPlaying)])
        XCTAssertEqual(h, 2 * EdgeBarLayout.widgetTileHeight + EdgeBarLayout.tileSpacing + 2 * EdgeBarLayout.verticalPadding)
    }
}
