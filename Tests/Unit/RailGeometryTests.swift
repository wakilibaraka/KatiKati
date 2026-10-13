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
        let slots = BarSection.islands(for: placement.effectiveMode(mode)).count
        return (0..<slots).map { slot in
            PanelGeometry.stripTargetFrame(slot: slot, contentLength: slot == 1 || slots == 1 ? 420 : 120,
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
                XCTAssertEqual(plates.count, BarSection.islands(for: placement.effectiveMode(mode)).count)
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

