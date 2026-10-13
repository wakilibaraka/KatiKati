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
}
