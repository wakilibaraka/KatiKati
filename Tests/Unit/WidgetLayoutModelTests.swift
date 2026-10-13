import XCTest
@testable import KatiKati

final class WidgetLayoutModelTests: XCTestCase {
    func testDefaultLayoutReproducesTodaysBehaviour() {
        let layout = WidgetLayout.default
        XCTAssertEqual(layout.order, BarSection.canonicalOrder)
        XCTAssertTrue(layout.hiddenSections.isEmpty)
        XCTAssertEqual(layout.solverWidths(), [:])
    }

    func testMediumWidthMatchesLegacyDefaultsForSizableSections() {
        for section in BarSection.allCases {
            XCTAssertEqual(section.widgetWidth(for: .medium), section.defaultWidgetWidth, "\(section)")
        }
    }

    func testPolicyDegradesLargeToMediumToSmall() {
        XCTAssertEqual(WidgetSizePolicy.resolve(.weather, requested: .large, availableWidth: 300), .large)
        XCTAssertEqual(WidgetSizePolicy.resolve(.weather, requested: .large, availableWidth: 200), .medium)
        XCTAssertEqual(WidgetSizePolicy.resolve(.weather, requested: .large, availableWidth: 100), .small)
        XCTAssertEqual(WidgetSizePolicy.resolve(.weather, requested: .large, availableWidth: 10), .small)
        XCTAssertEqual(WidgetSizePolicy.resolve(.media, requested: .medium, availableWidth: 300), .medium)
        XCTAssertEqual(WidgetSizePolicy.resolve(.apps, requested: .large, availableWidth: 1), .large)
    }

    func testSolverWidthsHonourSizeAndExactOverride() {
        var layout = WidgetLayout.default
        layout = WidgetLayout(instances: layout.instances.map { inst in
            var i = inst
            if i.section == .weather { i.size = .large }
            if i.section == .media { i.exactWidth = 200 }
            return i
        })
        XCTAssertEqual(layout.solverWidths(), [.weather: 230, .media: 200])
        // Large weather degrades to medium (= solver default, so no override) when space is short.
        XCTAssertNil(layout.solverWidths(availableWidth: 160)[.weather])
    }

    func testInitNormalizesToFullPermutation() {
        let layout = WidgetLayout(instances: [
            WidgetInstance(section: .clock), WidgetInstance(section: .clock), WidgetInstance(section: .weather)
        ])
        XCTAssertEqual(layout.order, [.clock, .weather, .launcher, .apps, .media, .widgets])
    }

    func testCodableRoundTrip() throws {
        var inst = WidgetInstance(section: .media, size: .large, isVisible: false, exactWidth: 180)
        inst.size = .large
        let layout = WidgetLayout(instances: [inst])
        let decoded = WidgetLayout.decode(layout.encoded())
        XCTAssertEqual(decoded, layout)
        XCTAssertEqual(decoded?.hiddenSections, [.media])
        XCTAssertNil(WidgetLayout.decode(Data("junk".utf8)))
    }

    func testMigrationKeepsLegacyWidthsAsExactOverrides() {
        let layout = WidgetLayout.migrating(legacyWidths: ["clock": 200])
        XCTAssertEqual(layout.order, BarSection.canonicalOrder)
        XCTAssertEqual(layout.solverWidths(), [.clock: 200])
        XCTAssertEqual(WidgetLayout.migrating(legacyWidths: [:]), .default)
    }
}

extension WidgetLayoutModelTests {
    func testWidthPrefersExactOverrideThenSizeAndFloorsAtMinimum() {
        var layout = WidgetLayout.default
        XCTAssertEqual(layout.width(for: .clock), BarSection.clock.defaultWidgetWidth)
        layout = layout.updating(.clock) { $0.size = .small }
        XCTAssertEqual(layout.width(for: .clock), BarSection.clock.minimumWidgetWidth, "S (76) floors at the 120 clock minimum")
        layout = layout.updating(.clock) { $0.exactWidth = 300 }
        XCTAssertEqual(layout.width(for: .clock), 300)
        XCTAssertEqual(layout.width(for: .launcher), 40)
    }
}

extension WidgetLayoutModelTests {
    func testMovingFollowsOnMoveSemantics() {
        let moved = WidgetLayout.default.moving(from: IndexSet(integer: 4), to: 1) // clock before weather
        XCTAssertEqual(moved.order, [.launcher, .clock, .weather, .apps, .media, .widgets])
        let down = WidgetLayout.default.moving(from: IndexSet(integer: 0), to: 3) // launcher after weather+apps
        XCTAssertEqual(down.order, [.weather, .apps, .launcher, .media, .clock, .widgets])
    }

    func testVisibleOrderDropsHiddenButNeverApps() {
        let layout = WidgetLayout.default.updating(.weather) { $0.isVisible = false }.updating(.apps) { $0.isVisible = false }
        XCTAssertEqual(layout.visibleOrder, [.launcher, .apps, .media, .clock, .widgets])
    }
}
