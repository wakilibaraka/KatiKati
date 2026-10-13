import XCTest
@testable import KatiKati

final class WidgetPresetTests: XCTestCase {
    func testBuiltInsAreStableAndFullIsDefault() {
        XCTAssertEqual(WidgetPresets.builtIns.map(\.id),
                       ["builtin.minimal", "builtin.commuter", "builtin.music", "builtin.focus", "builtin.full"])
        XCTAssertEqual(WidgetPresets.builtIns.last?.layout, .default)
        XCTAssertTrue(WidgetPresets.builtIns.allSatisfy(\.isBuiltIn))
    }

    func testBuiltInsKeepAppsVisibleAndClockShown() {
        for preset in WidgetPresets.builtIns {
            XCTAssertTrue(preset.layout.visibleOrder.contains(.apps), preset.id)
            XCTAssertTrue(preset.layout.visibleOrder.contains(.clock), preset.id)
        }
        let music = WidgetPresets.builtIns[2].layout
        XCTAssertEqual(WidgetPresets.builtIns[3].layout.visibleOrder, [.launcher, .apps, .media, .clock])
        XCTAssertEqual(music.instance(for: .media).size, .large)
        XCTAssertFalse(music.visibleOrder.contains(.weather))
    }

    func testSaveReplacesSameNameRejectsBlankAndRemoves() {
        var n = 0
        let id = { n += 1; return "u\(n)" }
        var list = WidgetPresets.saving(.default, as: "  Work ", into: [], makeID: id)
        XCTAssertEqual(list.map(\.name), ["Work"])
        let hidden = WidgetLayout.default.updating(.weather) { $0.isVisible = false }
        list = WidgetPresets.saving(hidden, as: "Work", into: list, makeID: id)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].layout, hidden)
        XCTAssertEqual(WidgetPresets.saving(.default, as: "   ", into: list, makeID: id), list)
        XCTAssertTrue(WidgetPresets.removing(id: "u1", from: list).isEmpty)
    }

    func testCodableRoundTripDropsBuiltInIDs() {
        let user = WidgetPreset(id: "u1", name: "A", layout: .default)
        let data = WidgetPresets.encode([user, WidgetPresets.builtIns[0]])
        XCTAssertEqual(WidgetPresets.decode(data), [user])
        XCTAssertEqual(WidgetPresets.decode(Data("x".utf8)), [])
    }
}
