import CoreGraphics
import XCTest
@testable import KatiKati

final class NotchFallbackPlanTests: XCTestCase {

    func testHardwareNotchDetection() {
        XCTAssertTrue(NotchFallbackPlan.isNotchedDisplay(safeAreaTop: 32.0))
        XCTAssertTrue(NotchFallbackPlan.isNotchedDisplay(safeAreaTop: 44.0))
        XCTAssertFalse(NotchFallbackPlan.isNotchedDisplay(safeAreaTop: 0.0))
    }

    func testFloatingTopOffsetCalculation() {
        XCTAssertEqual(NotchFallbackPlan.floatingTopOffset(menuBarHeight: 24.0), 32.0)
        XCTAssertEqual(NotchFallbackPlan.floatingTopOffset(menuBarHeight: 30.0), 38.0)
        // Fallback for zero menu bar height
        XCTAssertEqual(NotchFallbackPlan.floatingTopOffset(menuBarHeight: 0.0), 32.0)
    }

    func testUsableWingWidthWithAndWithoutHardwareKeepout() {
        // With hardware notch (160pt central keepout zone)
        let notchedWidth = NotchFallbackPlan.usableWingWidth(closedWidth: 240, hasHardwareNotch: true)
        XCTAssertEqual(notchedWidth, 40.0) // (240 - 160) / 2

        // Without hardware notch (no camera keepout zone needed on external display)
        let floatingWidth = NotchFallbackPlan.usableWingWidth(closedWidth: 240, hasHardwareNotch: false)
        XCTAssertEqual(floatingWidth, 120.0) // 240 / 2
    }

    func testPanelFramePlacementForNotchedVsExternalDisplays() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        // Case 1: Hardware notch display
        let notchedMetrics = NotchMetrics(
            closedSize: CGSize(width: 200, height: 34),
            hasHardwareNotch: true,
            cameraKeepoutBox: CGRect(x: 20, y: 0, width: 160, height: 34)
        )
        let notchedFrame = NotchFallbackPlan.panelFrame(
            metrics: notchedMetrics,
            screenBounds: screen,
            isOpen: false,
            menuBarHeight: 24
        )
        XCTAssertEqual(notchedFrame.origin.x, (1920 - 200) / 2)
        XCTAssertEqual(notchedFrame.origin.y, 0)
        XCTAssertEqual(notchedFrame.width, 200)
        XCTAssertEqual(notchedFrame.height, 34)

        // Case 2: External non-notched display (floating island)
        let externalMetrics = NotchMetrics(
            closedSize: CGSize(width: 185, height: 28),
            hasHardwareNotch: false,
            cameraKeepoutBox: .zero
        )
        let externalFrame = NotchFallbackPlan.panelFrame(
            metrics: externalMetrics,
            screenBounds: screen,
            isOpen: false,
            menuBarHeight: 24
        )
        XCTAssertEqual(externalFrame.origin.x, (1920 - 185) / 2)
        XCTAssertEqual(externalFrame.origin.y, 32.0) // 24 menu bar + 8 margin
        XCTAssertEqual(externalFrame.width, 185)
        XCTAssertEqual(externalFrame.height, 28)
    }

    func testNotchGlassPolicyResolvesStyles() {
        // Dynamic Glass open
        let dynamic = NotchGlassPolicy.resolve(style: .dynamicGlass, isLowPowerMode: false, hasHardwareNotch: false, isOpen: true)
        XCTAssertEqual(dynamic.effectiveStyle, .dynamicGlass)
        XCTAssertEqual(dynamic.plateOpacity, 0.82)
        XCTAssertFalse(dynamic.isPowerSavingOpaque)

        // Liquid Clear open
        let clear = NotchGlassPolicy.resolve(style: .liquidClear, isLowPowerMode: false, hasHardwareNotch: false, isOpen: true)
        XCTAssertEqual(clear.effectiveStyle, .liquidClear)
        XCTAssertEqual(clear.plateOpacity, 0.55)

        // Low Power Mode forces solid black regardless of selected style
        let lowPower = NotchGlassPolicy.resolve(style: .liquidClear, isLowPowerMode: true, hasHardwareNotch: false, isOpen: true)
        XCTAssertEqual(lowPower.effectiveStyle, .solidBlack)
        XCTAssertEqual(lowPower.plateOpacity, 1.0)
        XCTAssertTrue(lowPower.isPowerSavingOpaque)

        // Hardware notch in closed state forces solid black to seamlessly blend with bezel
        let hwClosed = NotchGlassPolicy.resolve(style: .dynamicGlass, isLowPowerMode: false, hasHardwareNotch: true, isOpen: false)
        XCTAssertEqual(hwClosed.effectiveStyle, .solidBlack)
        XCTAssertEqual(hwClosed.plateOpacity, 1.0)
        XCTAssertFalse(hwClosed.isPowerSavingOpaque)
    }

    // MARK: - Slice DN-1: Priority Queue & Geometry Calculator

    func testActivityQueuePrioritySortingAndEviction() {
        let t0 = Date(timeIntervalSince1970: 1000)
        var queue = NotchActivityQueue(maxItems: 3)

        let infoOld = NotchActivityItem(id: "dl-1", priority: .systemInfo, title: "Download", icon: "arrow.down.circle", createdAt: t0)
        let media = NotchActivityItem(id: "music", priority: .media, title: "Now Playing", icon: "music.note", createdAt: t0.addingTimeInterval(1))
        let call = NotchActivityItem(id: "call", priority: .critical, title: "Incoming Call", icon: "phone.fill", createdAt: t0.addingTimeInterval(2))
        let infoNew = NotchActivityItem(id: "vol", priority: .systemInfo, title: "Volume", icon: "speaker.wave.2.fill", level: 0.75, createdAt: t0.addingTimeInterval(3))

        queue.enqueue(infoOld, now: t0)
        queue.enqueue(media, now: t0.addingTimeInterval(1))
        queue.enqueue(call, now: t0.addingTimeInterval(2))
        queue.enqueue(infoNew, now: t0.addingTimeInterval(3))

        // Critical > Media > newer SystemInfo; older SystemInfo evicted by maxItems = 3
        XCTAssertEqual(queue.items.map(\.id), ["call", "music", "vol"])
        XCTAssertEqual(queue.current?.id, "call")
        XCTAssertEqual(queue.secondary?.id, "music")
    }

    func testActivityQueueUpdatesExistingIDAndPrunesTimeouts() {
        let t0 = Date(timeIntervalSince1970: 2000)
        var queue = NotchActivityQueue(maxItems: 4)

        let persistent = NotchActivityItem(id: "music", priority: .media, title: "Track", icon: "music.note", timeout: nil, createdAt: t0)
        let hud1 = NotchActivityItem(id: "volume", priority: .systemInfo, title: "Volume", icon: "speaker.wave.2.fill", timeout: 1.5, level: 0.4, createdAt: t0)
        let hud2 = NotchActivityItem(id: "volume", priority: .systemInfo, title: "Volume", icon: "speaker.wave.3.fill", timeout: 1.5, level: 0.8, createdAt: t0.addingTimeInterval(0.5))

        queue.enqueue(persistent, now: t0)
        queue.enqueue(hud1, now: t0)
        queue.enqueue(hud2, now: t0.addingTimeInterval(0.5))

        XCTAssertEqual(queue.items.count, 2)
        XCTAssertEqual(queue.items.first(where: { $0.id == "volume" })?.level, 0.8)
        XCTAssertEqual(queue.nextExpirationDate(after: t0), t0.addingTimeInterval(2.0))

        // Before expiry: still present
        XCTAssertFalse(queue.pruneExpired(at: t0.addingTimeInterval(1.9)))
        XCTAssertEqual(queue.items.count, 2)

        // At expiry: HUD evicted, persistent media stays
        XCTAssertTrue(queue.pruneExpired(at: t0.addingTimeInterval(2.0)))
        XCTAssertEqual(queue.items.map(\.id), ["music"])
        XCTAssertNil(queue.nextExpirationDate(after: t0.addingTimeInterval(2.0)))
    }

    func testNotchGeometryCalculatorHardwareVsFloatingCapsule() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let closed = CGSize(width: 200, height: 32)
        let open = CGSize(width: 600, height: 200)

        // Hardware notch (topInset > 0): flush top, flaring ears
        let hwClosed = NotchGeometryCalculator.calculate(
            screenBounds: screen, topInset: 32, menuBarHeight: 37,
            closedSize: closed, openSize: open, isExpanded: false
        )
        XCTAssertEqual(hwClosed.mode, .hardwareNotch)
        XCTAssertTrue(hwClosed.flaringTopEars)
        XCTAssertEqual(hwClosed.panelFrame, CGRect(x: 860, y: 1080 - 32, width: 200, height: 32))

        // External display (topInset == 0): floating capsule below menu bar, 4 symmetrical corners
        let extClosed = NotchGeometryCalculator.calculate(
            screenBounds: screen, topInset: 0, menuBarHeight: 24,
            closedSize: closed, openSize: open, isExpanded: false
        )
        XCTAssertEqual(extClosed.mode, .floatingCapsule)
        XCTAssertFalse(extClosed.flaringTopEars)
        XCTAssertEqual(extClosed.topCornerRadius, NotchFallbackPlan.floatingClosedCornerRadius)
        XCTAssertEqual(extClosed.bottomCornerRadius, NotchFallbackPlan.floatingClosedCornerRadius)
        XCTAssertEqual(extClosed.panelFrame, CGRect(x: 860, y: 1080 - 32 - 32, width: 200, height: 32))

        let extOpen = NotchGeometryCalculator.calculate(
            screenBounds: screen, topInset: 0, menuBarHeight: 24,
            closedSize: closed, openSize: open, isExpanded: true
        )
        XCTAssertEqual(extOpen.topCornerRadius, NotchFallbackPlan.floatingOpenCornerRadius)
        XCTAssertEqual(extOpen.panelFrame, CGRect(x: 660, y: 1080 - 32 - 200, width: 600, height: 200))
    }
}
