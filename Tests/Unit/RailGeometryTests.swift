import CoreGraphics
import XCTest
@testable import KatiKati

/// Phase 18b: island frames on a side rail (pure geometry; no panels).
final class RailGeometryTests: XCTestCase {
    private let screen = PanelScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1710, height: 1112),
        visibleFrame: CGRect(x: 0, y: 0, width: 1710, height: 1074),
        safeAreaTop: 38)
    private let metrics = PanelLayoutMetrics.tungstenEdge
    private let layout = WidgetLayout.default

    private func frames(_ mode: BarLayoutMode, _ placement: StripPlacement) -> [CGRect] {
        (0..<mode.slotCount).map { slot in
            // The apps island's solver width follows its measured content; a fixed island is sized
            // chrome-true from `widgetLayout`, so this 120 only stands in for a measurement.
            PanelGeometry.stripTargetFrame(slot: slot, contentLength: BarSection.islands(for: mode)[slot].contains(.apps) ? 420 : 120,
                                           mode: mode, stripPlacement: placement, on: screen,
                                           metrics: metrics, gap: 10, margin: 12, widgetLayout: layout)
        }
    }

    func testBottomIsExactlyTheIslandFrame() {
        for mode in BarLayoutMode.allCases {
            for slot in 0..<BarSection.islands(for: mode).count {
                XCTAssertEqual(
                    PanelGeometry.stripTargetFrame(slot: slot, contentLength: 400, mode: mode, stripPlacement: .bottom,
                                                   on: screen, metrics: metrics, gap: 10, margin: 12, widgetLayout: layout),
                    PanelGeometry.islandTargetFrame(slot: slot, contentWidth: 400, mode: mode, on: screen,
                                                    metrics: metrics, gap: 10, margin: 12, widgetLayout: layout),
                    "\(mode) slot \(slot)")
            }
        }
    }

    func testRailsHugTheirEdgeBelowTheMenuBarWithoutOverlap() {
        for placement in [StripPlacement.left, .right] {
            for mode in BarLayoutMode.allCases {
                let plates = frames(mode, placement).map { $0.insetBy(dx: metrics.shadowPadding, dy: metrics.shadowPadding) }
                XCTAssertEqual(plates.count, mode.slotCount)
                for plate in plates {
                    XCTAssertEqual(plate.width, metrics.panelHeight, accuracy: 0.001, "\(placement) \(mode): rail thickness")
                    XCTAssertLessThanOrEqual(plate.maxY, screen.topUsableY + 0.001, "\(placement) \(mode): under the menu bar")
                    XCTAssertGreaterThanOrEqual(plate.minY, screen.frame.minY - 0.001)
                    if placement == .left {
                        XCTAssertEqual(plate.minX, screen.frame.minX + metrics.bottomGap, accuracy: 0.001)
                    } else {
                        XCTAssertEqual(plate.maxX, screen.frame.maxX - metrics.bottomGap, accuracy: 0.001)
                    }
                }
                let sorted = plates.sorted { $0.maxY > $1.maxY }
                for (upper, lower) in zip(sorted, sorted.dropFirst()) {
                    XCTAssertLessThanOrEqual(lower.maxY, upper.minY + 0.001, "\(placement) \(mode): islands overlap")
                }
            }
        }
    }

    /// Phase 41a: a rail carries **every** mode with the mode's own island count — Phase 18 folded
    /// split4/split5 into three islands, so two of the five mode choices did nothing on a rail.
    func testRailsCarryEveryModeWithTheSameSlotCount() {
        XCTAssertEqual(BarLayoutMode.split4.slotCount, 4)
        XCTAssertEqual(BarLayoutMode.split5.slotCount, 5)
        for placement in [StripPlacement.left, .right] {
            for mode in BarLayoutMode.allCases {
                let plates = frames(mode, placement).map { $0.insetBy(dx: metrics.shadowPadding, dy: metrics.shadowPadding) }
                XCTAssertEqual(plates.count, mode.slotCount, "\(placement) \(mode): one panel per island")
                // Every island lives inside the rail: below the menu bar, above the bottom edge.
                for plate in plates {
                    XCTAssertGreaterThanOrEqual(plate.minY, screen.frame.minY - 0.001, "\(placement) \(mode)")
                    XCTAssertLessThanOrEqual(plate.maxY, screen.topUsableY + 0.001, "\(placement) \(mode)")
                    XCTAssertEqual(plate.width, metrics.panelHeight, accuracy: 0.001, "\(placement) \(mode): thickness")
                }
            }
        }
        // Split 5's five islands must not overlap or leave the rail on the long axis.
        let split5 = frames(.split5, .left).map { $0.insetBy(dx: metrics.shadowPadding, dy: metrics.shadowPadding) }
            .sorted { $0.maxY > $1.maxY }
        for (upper, lower) in zip(split5, split5.dropFirst()) {
            XCTAssertLessThanOrEqual(lower.maxY, upper.minY + 0.001, "split5 rail islands overlap")
        }
    }

    /// Phase 49 (owner: "Hug content with balanced insets"): a rail's apps island hugs its measured
    /// content rather than stretching across the empty span between the fixed end islands, and the
    /// drawer capsule slot below it stays clear of the trailing island.
    func testRailAppsIslandHugsContentAndKeepsTheCapsuleSlotClear() {
        for placement in [StripPlacement.left, .right] {
            for mode in [BarLayoutMode.split3, .split4, .split5] {
                let label = "\(placement) \(mode)"
                let fill = PanelGeometry.railAppsFillLength(
                    mode: mode, stripPlacement: placement, on: screen, metrics: metrics,
                    gap: 10, margin: 12, widgetLayout: layout)
                XCTAssertEqual(fill, 0, "\(label): rail apps island hugs content instead of filling")

                let appsSlot = BarSection.islands(for: mode).firstIndex { $0.contains(.apps) }!
                let appsPlate = PanelGeometry.stripTargetFrame(slot: appsSlot, contentLength: 420, mode: mode,
                                                               stripPlacement: placement, on: screen, metrics: metrics,
                                                               gap: 10, margin: 12, widgetLayout: layout)
                    .insetBy(dx: metrics.shadowPadding, dy: metrics.shadowPadding)
                XCTAssertEqual(appsPlate.height, 420, accuracy: 0.5, "\(label): hugs the 420 pt content")

                // The drawer capsule rides below this island, so the gap it leaves to the next island
                // down is at least the capsule's own slot (gap + width) — never less, or the two overlap.
                let others = frames(mode, placement)
                    .map { $0.insetBy(dx: metrics.shadowPadding, dy: metrics.shadowPadding) }
                    .filter { $0.maxY <= appsPlate.minY + 0.001 }
                let nearestBelow = others.map(\.maxY).max() ?? screen.frame.minY
                XCTAssertGreaterThanOrEqual(appsPlate.minY - nearestBelow,
                                            metrics.capsuleGap + metrics.capsuleWidth - 0.001,
                                            "\(label): the capsule slot must stay clear")
            }
        }
    }

    /// Phase 42 / Phase 49: a rail's islands are solved with `IslandChrome.railContentInset` (8 pt), and
    /// `stripTargetFrame` is the path that carries it — the frame it returns is byte-for-byte the
    /// rail-inset solve mapped onto the edge.
    func testRailIslandFramesCarryTheRailEndInset() {
        let virtual = PanelGeometry.railVirtualScreen(on: screen, placement: .left)
        func solved(_ inset: CGFloat) -> CGRect {
            PanelGeometry.islandTargetFrame(slot: 0, contentWidth: 120, mode: .split3, on: virtual,
                                            placement: .right, metrics: metrics, gap: 10, margin: 12,
                                            widgetLayout: PanelGeometry.railWidgetLayout(layout),
                                            tileStride: IslandChrome.railChipStride(barHeight: metrics.panelHeight),
                                            contentInset: inset)
        }
        let rail = PanelGeometry.stripTargetFrame(slot: 0, contentLength: 120, mode: .split3,
                                                  stripPlacement: .left, on: screen, metrics: metrics,
                                                  gap: 10, margin: 12, widgetLayout: layout)
        XCTAssertEqual(rail.height, solved(IslandChrome.railContentInset).width, accuracy: 0.001,
                       "the rail path is the rail-inset solve")
        XCTAssertEqual(solved(16).width - solved(IslandChrome.railContentInset).width,
                       2 * (16 - IslandChrome.railContentInset), accuracy: 0.001,
                       "2 × (16 − 8): tightened end insets")
    }

    /// Phase 42's 4 pt rail ends are only legal while the end tile stays clear of the island's rounded
    /// corner. The strip clips its content to that plate, so the bottom bar needs `inset ≥ radius`; on a
    /// rail the tile is centred across the thickness and has slack on that axis instead — pinned here at
    /// every bar height, including the S and L ends of the slider.
    func testRailEndInsetKeepsEveryTileClearOfThePlateCorner() {
        for barHeight: CGFloat in [32, 54, 90] {
            let scale = barHeight / 54
            let radius = DockShape.panelCornerRadius * scale
            let side = (barHeight - BarSection.railTileSize * scale) / 2   // cross-axis slack
            let end = IslandChrome.railContentInset * scale
            // The corner region a rounded rect removes is `(r − x)² + (r − y)² > r²`; the tile's own
            // corner sits at (side, end) from the plate's.
            let dx = radius - side
            let dy = radius - end
            XCTAssertLessThanOrEqual(dx * dx + dy * dy, radius * radius,
                                     "\(barHeight): the first rail tile's corner is clipped")
        }
    }

    /// The bottom bar has no fill: `railAppsFillLength` reports 0 there, and on the single-island modes.
    func testAppsFillIsRailAndSplitOnly() {
        XCTAssertEqual(PanelGeometry.railAppsFillLength(mode: .split3, stripPlacement: .bottom, on: screen),
                       0, "bottom bar keeps measuring its content")
        for mode in [BarLayoutMode.windows, .centered] {
            XCTAssertEqual(PanelGeometry.railAppsFillLength(mode: mode, stripPlacement: .left, on: screen), 0,
                           "\(mode): the frame is already the authority")
        }
    }

    func testCapsuleSitsBelowTheAppsIslandOnARail() {
        let apps = PanelGeometry.stripTargetFrame(slot: 1, contentLength: 420, mode: .split3, stripPlacement: .left,
                                                  on: screen, metrics: metrics, gap: 10, margin: 12, widgetLayout: layout)
        let capsule = PanelGeometry.stripCapsuleTargetFrame(forDock: apps, stripPlacement: .left, on: screen,
                                                            drawerPlacement: .right, metrics: metrics)
        let plate = apps.insetBy(dx: metrics.shadowPadding, dy: metrics.shadowPadding)
        let capsulePlate = capsule.insetBy(dx: metrics.shadowPadding, dy: metrics.shadowPadding)
        XCTAssertEqual(capsulePlate.maxY, plate.minY - metrics.capsuleGap, accuracy: 0.001)
        XCTAssertEqual(capsulePlate.midX, plate.midX, accuracy: 0.001)
    }

    func testTopIslandStartsJustBelowTheMenuBar() {
        let top = PanelGeometry.stripTargetFrame(slot: 0, contentLength: 120, mode: .split3, stripPlacement: .left,
                                                 on: screen, metrics: metrics, gap: 10, margin: 12, widgetLayout: layout)
            .insetBy(dx: metrics.shadowPadding, dy: metrics.shadowPadding)
        XCTAssertEqual(top.maxY, screen.topUsableY - 12, accuracy: 0.001, "margin below the menu bar")
    }

    // MARK: 18d popups

    func testStackPopupOpensInwardBesideARailAndStaysOnScreen() {
        let anchor = CGRect(x: 8, y: 500, width: 54, height: 54)   // a chip on a left rail
        let size = CGSize(width: 400, height: 300)
        let left = PanelGeometry.folderPopupTargetFrame(anchorVisibleRect: anchor, size: size, on: screen,
                                                        stripPlacement: .left)
        let plate = PanelGeometry.folderPopupPlateFrame(panelFrame: left)
        XCTAssertEqual(plate.minX, anchor.maxX + StackPopupMetrics.tipGap, accuracy: 0.001, "opens right of a left rail")
        XCTAssertEqual(left.midY, anchor.midY, accuracy: 0.001, "centred on the anchor")

        let rightAnchor = CGRect(x: 1648, y: 40, width: 54, height: 54)   // low on a right rail
        let right = PanelGeometry.folderPopupTargetFrame(anchorVisibleRect: rightAnchor, size: size, on: screen,
                                                         stripPlacement: .right)
        let rightPlate = PanelGeometry.folderPopupPlateFrame(panelFrame: right)
        XCTAssertEqual(rightPlate.maxX, rightAnchor.minX - StackPopupMetrics.tipGap, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(rightPlate.minY, screen.frame.minY - 0.001, "clamped above the screen bottom")
    }

    func testTooltipAndChipPanelOpenBesideARail() {
        let anchor = CGRect(x: 8, y: 600, width: 54, height: 54)
        let tip = PanelGeometry.windowTitleTooltipTargetFrame(anchorVisibleRect: anchor, size: CGSize(width: 120, height: 40),
                                                             tipGap: 6, on: screen, stripPlacement: .left)
        XCTAssertGreaterThan(tip.minX, anchor.maxX - PanelGeometry.windowTitleTooltipShadowPadding)
        let panel = ChipPanelLayout.placement(anchor: anchor, plate: CGSize(width: 240, height: 160),
                                              screen: screen.frame, stripPlacement: .left)
        XCTAssertGreaterThan(panel.panelFrame.midX, anchor.maxX)
        XCTAssertEqual(panel.arrowOffsetFromCenter, 0)
        let bottom = ChipPanelLayout.placement(anchor: anchor, plate: CGSize(width: 240, height: 160), screen: screen.frame)
        XCTAssertEqual(bottom, ChipPanelLayout.placement(anchor: anchor, plate: CGSize(width: 240, height: 160),
                                                         screen: screen.frame, stripPlacement: .bottom))
    }

    // MARK: 18e window clearance

    func testMaximizedWindowNarrowsAwayFromALeftRail() {
        let visible = CGRect(x: 0, y: 0, width: 1710, height: 1074)
        let geometry = WindowLiftAvoidance.Geometry(screenFrame: screen.frame, visibleFrame: visible,
                                                    taskbarTop: 8 + 54, placement: .left)
        let target = geometry.liftTargetFrame(for: visible, includesTiles: true)
        XCTAssertNotNil(target)
        guard let target else { return }
        XCTAssertEqual(target.minX, 62 + WindowLiftAvoidance.clearance, accuracy: 0.001)
        XCTAssertEqual(target.maxX, visible.maxX, accuracy: 0.001, "far side unchanged")
        XCTAssertEqual(target.minY, visible.minY, accuracy: 0.001)
        XCTAssertEqual(target.maxY, visible.maxY, accuracy: 0.001, "full height kept")
    }

    func testRightRailClearsTheRightEdgeAndLeavesLeftHalvesAlone() {
        let visible = CGRect(x: 0, y: 0, width: 1710, height: 1074)
        let edge = screen.frame.maxX - 62
        let geometry = WindowLiftAvoidance.Geometry(screenFrame: screen.frame, visibleFrame: visible,
                                                    taskbarTop: edge, placement: .right)
        let rightHalf = CGRect(x: 855, y: 0, width: 855, height: 1074)
        let target = geometry.liftTargetFrame(for: rightHalf, includesTiles: true)
        XCTAssertEqual(target?.maxX ?? 0, edge - WindowLiftAvoidance.clearance, accuracy: 0.001)
        XCTAssertEqual(target?.minX ?? 0, 855, accuracy: 0.001)
        let leftHalf = CGRect(x: 0, y: 0, width: 855, height: 1074)
        XCTAssertNil(geometry.liftTargetFrame(for: leftHalf, includesTiles: true), "not docked against the rail")
    }

    func testBottomGeometryIsUnchangedByThePlacementField() {
        let visible = CGRect(x: 0, y: 0, width: 1710, height: 1074)
        let a = WindowLiftAvoidance.Geometry(screenFrame: screen.frame, visibleFrame: visible, taskbarTop: 62)
        let b = WindowLiftAvoidance.Geometry(screenFrame: screen.frame, visibleFrame: visible, taskbarTop: 62, placement: .bottom)
        XCTAssertEqual(a.liftTargetFrame(for: visible, includesTiles: true), b.liftTargetFrame(for: visible, includesTiles: true))
    }
}

