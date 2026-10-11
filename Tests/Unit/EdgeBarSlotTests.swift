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
        XCTAssertEqual(r[.left], [.widget(.weather), .widget(.nowPlaying), .widget(.bluetooth), .widget(.systemMonitor), .status])
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
        XCTAssertEqual(EdgeItem.allCases.count, 15)
    }

    func testShippedProductivityButtonsAppearOnTheMainSideByDefault() {
        XCTAssertEqual(ProductivityItem.built, Set(ProductivityItem.allCases))
        let r = EdgeBarComposition.resolve(preset: .productivityAndRest, primary: .right, widgets: [],
                                           productivity: ProductivityItem.allCases, custom: [:])
        XCTAssertEqual(r[.right], [.notes, .newNote, .productivity(.reminders), .productivity(.alarms), .productivity(.time), .productivity(.tasks), .productivity(.clipboard), .productivity(.capture), .productivity(.windows), .settings])
    }

    func testWidgetTileIdsAreFrozenAndParseIsTolerant() {
        XCTAssertEqual(WidgetTile.allCases.map(\.rawValue), ["weather", "nowPlaying", "bluetooth", "systemMonitor"])
        XCTAssertEqual(WidgetTile.parse("systemMonitor, weather,bogus,weather"), [.systemMonitor, .weather])
        XCTAssertEqual(WidgetTile.parse(""), [])
        XCTAssertEqual(WidgetTile.serialize([.weather, .nowPlaying]), "weather,nowPlaying")
    }
}
