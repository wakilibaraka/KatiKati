import XCTest
@testable import KatiKati

final class BarLayoutModeTests: XCTestCase {
    func testAllFiveModesExist() {
        XCTAssertEqual(BarLayoutMode.allCases.count, 5)
        XCTAssertEqual(BarLayoutMode.allCases, [.windows, .split3, .split4, .split5, .centered])
    }

    func testSplit5SeparatesEveryOuterSection() {
        let islands = BarSection.islands(for: .split5)
        // DP-2: `.ai` is opt-in, so it leaves the fresh default order.
        XCTAssertEqual(islands, [[.launcher], [.weather], [.apps, .media, .utilities], [.clock], [.widgets]])
        XCTAssertEqual(BarLayoutMode.split5.slotCount, 5)
        XCTAssertTrue(BarLayoutMode.split5.isSplit)
        XCTAssertEqual(BarSection.widgets.slotIndex(for: .split5), 4)
    }

    func testSplitModesAreAllDistinct() {
        let counts = [BarLayoutMode.split3, .split4, .split5].map { $0.slotCount }
        XCTAssertEqual(counts, [3, 4, 5])
    }

    func testSlotCountsAndSplitFlags() {
        XCTAssertEqual(BarLayoutMode.windows.slotCount, 1)
        XCTAssertTrue(BarLayoutMode.windows.isSingleIsland)
        XCTAssertFalse(BarLayoutMode.windows.isSplit)

        XCTAssertEqual(BarLayoutMode.split3.slotCount, 3)
        XCTAssertFalse(BarLayoutMode.split3.isSingleIsland)
        XCTAssertTrue(BarLayoutMode.split3.isSplit)

        XCTAssertEqual(BarLayoutMode.split4.slotCount, 4)
        // 4U-A: split4 detaches media into its own island (launcher·weather | apps | media | clock·widgets).
        XCTAssertFalse(BarLayoutMode.split4.isSingleIsland)
        XCTAssertTrue(BarLayoutMode.split4.isSplit)

        XCTAssertEqual(BarLayoutMode.centered.slotCount, 1)
        XCTAssertTrue(BarLayoutMode.centered.isSingleIsland)
        XCTAssertFalse(BarLayoutMode.centered.isSplit)
    }

    func testTitlesAndDetailsNotEmpty() {
        for mode in BarLayoutMode.allCases {
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertFalse(mode.detail.isEmpty)
            XCTAssertEqual(mode.id, mode.rawValue)
        }
    }

    func testCodableRoundTrip() throws {
        for mode in BarLayoutMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(BarLayoutMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }

    func testSectionIslandsPerMode() {
        let windowsIslands = BarSection.islands(for: .windows)
        XCTAssertEqual(windowsIslands.count, 1)
        XCTAssertEqual(windowsIslands[0], BarSection.defaultOrder)

        let split3Islands = BarSection.islands(for: .split3)
        XCTAssertEqual(split3Islands.count, 3)
        XCTAssertEqual(split3Islands[0], [.launcher, .weather])
        XCTAssertEqual(split3Islands[1], [.apps, .media])
        XCTAssertEqual(split3Islands[2], [.utilities, .clock, .widgets])

        let split4Islands = BarSection.islands(for: .split4)
        XCTAssertEqual(split4Islands.count, 4)
        XCTAssertEqual(split4Islands[0], [.launcher, .weather])
        XCTAssertEqual(split4Islands[1], [.apps])
        XCTAssertEqual(split4Islands[2], [.media])
        XCTAssertEqual(split4Islands[3], [.utilities, .clock, .widgets])

        let centeredIslands = BarSection.islands(for: .centered)
        XCTAssertEqual(centeredIslands.count, 1)
        XCTAssertEqual(centeredIslands[0], BarSection.defaultOrder)
    }

    func testEverySectionLivesInExactlyOneIslandPerMode() {
        for mode in BarLayoutMode.allCases {
            let groups = BarSection.islands(for: mode)
            let flattened = groups.flatMap { $0 }
            XCTAssertEqual(flattened.count, BarSection.defaultOrder.count)
            XCTAssertEqual(Set(flattened), Set(BarSection.defaultOrder))
        }
    }

    func testSlotIndexForSections() {
        XCTAssertEqual(BarSection.weather.slotIndex(for: .split3), 0)
        XCTAssertEqual(BarSection.apps.slotIndex(for: .split3), 1)
        XCTAssertEqual(BarSection.clock.slotIndex(for: .split3), 2)

        XCTAssertEqual(BarSection.weather.slotIndex(for: .split4), 0)
        XCTAssertEqual(BarSection.apps.slotIndex(for: .split4), 1)
        XCTAssertEqual(BarSection.clock.slotIndex(for: .split4), 3)

        XCTAssertEqual(BarSection.apps.slotIndex(for: .windows), 0)
        XCTAssertEqual(BarSection.apps.slotIndex(for: .centered), 0)
    }

    // MARK: - Hardcoded order + settings-only widths (Phase 4U decision 3, 2026-10-09)

    func testCanonicalOrderIsHardcoded() {
        // Declaration order IS the canonical widget order: no reader, no writer.
        XCTAssertEqual(BarSection.allCases, BarSection.canonicalOrder)
        // DP-2: AI Tracking is opt-in, so the fresh visible set no longer includes `.ai`.
        XCTAssertEqual(BarSection.defaultOrder, [.launcher, .weather, .apps, .media, .utilities, .clock, .widgets])
    }

    func testDefaultWidgetWidths() {
        XCTAssertEqual(BarSection.weather.defaultWidgetWidth, 150)
        XCTAssertEqual(BarSection.apps.defaultWidgetWidth, 0)
        XCTAssertEqual(BarSection.media.defaultWidgetWidth, 215)
        XCTAssertEqual(BarSection.clock.defaultWidgetWidth, 160)
    }

    func testFABSectionsAreSquareAndIdentified() {
        for fab in [BarSection.launcher, .widgets] {
            XCTAssertEqual(fab.defaultWidgetWidth, 40)
            XCTAssertEqual(fab.minimumWidgetWidth, 40)
        }
        XCTAssertEqual(BarSection.launcher.title, "Launcher")
        XCTAssertEqual(BarSection.widgets.title, "Widgets")
        XCTAssertEqual(BarSection.launcher.placeholderEntryID, "sec-launcher")
        XCTAssertEqual(BarSection.widgets.placeholderEntryID, "sec-widgets")
    }

    func testDockUtilitiesConfigModularityAndDeduplication() throws {
        var cfg = DockUtilitiesConfig.default
        XCTAssertEqual(cfg.visibleUtilities.map(\.rawValue),
                       ["drawer", "screenshots", "clipboard", "dictionary", "terminal", "downloads", "trash"])
        XCTAssertEqual(cfg.suppressedAppBundleIDs(), ["com.apple.Dictionary", "com.apple.Terminal"])

        cfg = cfg.moving(.screenshots, by: -1)
        XCTAssertEqual(cfg.order.first, .screenshots)

        cfg = cfg.setting(.terminal, visible: false)
        XCTAssertFalse(cfg.visibleUtilities.contains(.terminal))
        XCTAssertEqual(cfg.suppressedAppBundleIDs(), ["com.apple.Dictionary"])

        let decoded = try XCTUnwrap(DockUtilitiesConfig.decode(cfg.encoded()))
        XCTAssertEqual(decoded, cfg)

        // Legacy payload missing placement/preset/dismissal decodes safely with recommended defaults
        let legacyJSON = #"{"order":["terminal","downloads"],"hidden":[]}"#.data(using: .utf8)
        let legacyDecoded = try XCTUnwrap(DockUtilitiesConfig.decode(legacyJSON))
        XCTAssertEqual(legacyDecoded.popoverPlacement, .anchored)
        XCTAssertEqual(legacyDecoded.flyoutPreset, .shelfDeck)
        XCTAssertEqual(legacyDecoded.dismissalBehavior, .persistentTerminal)
    }

    func testUtilityFlyoutPresetsAndPlacementGeometry() {
        XCTAssertTrue(UtilityFlyoutPreset.shelfDeck.resolvesArrowVisible(for: .anchored))
        XCTAssertTrue(UtilityFlyoutPreset.compactGrid.resolvesArrowVisible(for: .anchored))
        XCTAssertFalse(UtilityFlyoutPreset.cleanFloat.resolvesArrowVisible(for: .anchored))
        XCTAssertFalse(UtilityFlyoutPreset.shelfDeck.resolvesArrowVisible(for: .bottomFloat))
        XCTAssertFalse(UtilityFlyoutPreset.shelfDeck.resolvesArrowVisible(for: .centerFloat))
        // A side rail points sideways (`<` / `>`), it does not stop pointing: the anchored preset
        // keeps its arrow there. The edge, not the orientation, decides the shape — the rail case is
        // asserted against the real geometry below and in RailGeometryTests.

        XCTAssertFalse(UtilityDismissalBehavior.persistentTerminal.dismissesOnOutsideClick(
            isTerminal: true, placement: .anchored, isPinned: false))
        XCTAssertTrue(UtilityDismissalBehavior.persistentTerminal.dismissesOnOutsideClick(
            isTerminal: false, placement: .anchored, isPinned: false))
        XCTAssertFalse(UtilityDismissalBehavior.transientWhenAnchored.dismissesOnOutsideClick(
            isTerminal: true, placement: .bottomFloat, isPinned: false))
        XCTAssertFalse(UtilityDismissalBehavior.unifiedWithPin.dismissesOnOutsideClick(
            isTerminal: false, placement: .anchored, isPinned: true))

        let screen = PanelScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1710, height: 1112),
            visibleFrame: CGRect(x: 0, y: 0, width: 1710, height: 1075),
            safeAreaTop: 37
        )
        let anchor = CGRect(x: 920, y: 8, width: 40, height: 40)
        let size = CGSize(width: 680, height: 420)

        let anchored = PanelGeometry.utilityPanelFrame(
            plateSize: size, anchorVisibleRect: anchor,
            placement: .anchored, flyoutPreset: .shelfDeck, on: screen
        )
        XCTAssertTrue(anchored.showsArrow)
        XCTAssertEqual(anchored.arrowOffsetFromCenter, anchor.midX - anchored.frame.midX, accuracy: 0.5)

        let bottom = PanelGeometry.utilityPanelFrame(
            plateSize: size, anchorVisibleRect: anchor,
            placement: .bottomFloat, flyoutPreset: .shelfDeck, on: screen
        )
        XCTAssertFalse(bottom.showsArrow)
        XCTAssertEqual(bottom.frame.midX, screen.visibleFrame.midX, accuracy: 0.5)
        XCTAssertEqual(bottom.frame.minY + StackPopupMetrics.panelMargin, 80, accuracy: 0.5)

        let centered = PanelGeometry.utilityPanelFrame(
            plateSize: size, anchorVisibleRect: anchor,
            placement: .centerFloat, flyoutPreset: .shelfDeck, on: screen
        )
        XCTAssertFalse(centered.showsArrow)
        XCTAssertEqual(centered.frame.midY, screen.visibleFrame.midY, accuracy: 0.5)

        // A side rail keeps the anchored pointer and reserves it on the horizontal axis: the arrow
        // becomes the plate's leading chevron instead of the downward `v`.
        let rail = PanelGeometry.utilityPanelFrame(
            plateSize: size, anchorVisibleRect: anchor,
            placement: .anchored, flyoutPreset: .shelfDeck,
            stripPlacement: .left, on: screen
        )
        XCTAssertTrue(rail.showsArrow, "an anchored rail popup still points at its chip")
        XCTAssertEqual(rail.frame.width,
                       size.width + StackPopupMetrics.arrowHeight + StackPopupMetrics.panelMargin * 2,
                       accuracy: 0.5, "the rail reserves the arrow beside the plate, not below it")
    }
}
