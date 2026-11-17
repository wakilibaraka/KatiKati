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

    // MARK: - Slice NS-1: Notch surface appearance

    /// The default owner-visible state: opaque OLED black, no blur material, nothing to see through.
    func testSurfaceDefaultsToOpaqueOLEDBlack() {
        let appearance = NotchSurfaceAppearance()
        XCTAssertEqual(appearance.preset, .oledBlack)
        XCTAssertEqual(appearance.customHex, "#000000")
        XCTAssertEqual(appearance.transparency, 0.0)

        let resolved = appearance.effectiveAppearance(isLowPowerMode: false)
        XCTAssertEqual(resolved.preset, .oledBlack)
        XCTAssertEqual(resolved.transparency, 0.0)
        XCTAssertEqual(resolved.baseOpacity, 1.0)
        XCTAssertFalse(resolved.shouldRenderBlurMaterial)
        XCTAssertFalse(resolved.isPowerSavingOpaque)
        XCTAssertEqual(resolved.baseColor.r, 0)
        XCTAssertEqual(resolved.baseColor.g, 0)
        XCTAssertEqual(resolved.baseColor.b, 0)
        XCTAssertEqual(resolved.baseColor.a, 1)
    }

    func testTransparencyClampsAndOnlyThenAsksForBlur() {
        XCTAssertEqual(NotchSurfaceAppearance(transparency: -1).clampedTransparency, 0.0)
        XCTAssertEqual(NotchSurfaceAppearance(transparency: 2).clampedTransparency, 0.85)
        XCTAssertEqual(NotchSurfaceAppearance(transparency: .nan).clampedTransparency, 0.0)
        XCTAssertEqual(NotchSurfaceAppearance(transparency: .infinity).clampedTransparency, 0.0)

        // Under the 0.1% threshold the plate is opaque in practice, so no vibrancy pass is spent on it.
        let invisible = NotchSurfaceAppearance(transparency: 0.0005).effectiveAppearance(isLowPowerMode: false)
        XCTAssertFalse(invisible.shouldRenderBlurMaterial)
        XCTAssertEqual(invisible.baseOpacity, 1.0, accuracy: 0.001)

        let frosted = NotchSurfaceAppearance(transparency: 0.85).effectiveAppearance(isLowPowerMode: false)
        XCTAssertTrue(frosted.shouldRenderBlurMaterial)
        XCTAssertEqual(frosted.baseOpacity, 0.15, accuracy: 0.001)
        XCTAssertEqual(frosted.transparency, 0.85, accuracy: 0.001)
    }

    func testPresetHexAndRimResolution() {
        for preset in NotchColorPreset.allCases where preset != .custom {
            let resolved = NotchSurfaceAppearance(preset: preset).effectiveAppearance(isLowPowerMode: false)
            XCTAssertEqual(resolved.baseColor, preset.baseHex, "\(preset) plate must be its own colour")
            XCTAssertEqual(resolved.rimColor, preset.rimHex, "\(preset) rim must be its own colour")
            XCTAssertEqual(resolved.rimOpacity, preset.rimOpacity)
            XCTAssertGreaterThan(resolved.rimOpacity, 0)
            XCTAssertLessThanOrEqual(resolved.rimOpacity, 1)
        }
        // The six presets are distinguishable plates, and only OLED black is pure black.
        let bases = NotchColorPreset.allCases.filter { $0 != .custom }.map(\.baseHex)
        XCTAssertEqual(Set(bases.map { "\($0.r),\($0.g),\($0.b)" }).count, bases.count)
        XCTAssertEqual(NotchColorPreset.oledBlack.baseHex.r, 0)
    }

    func testCustomHexParsingAndLiftedRim() {
        XCTAssertEqual(NotchHexColor.rgba("#FF8000").r, 1.0, accuracy: 0.001)
        XCTAssertEqual(NotchHexColor.rgba("#FF8000").g, 128.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(NotchHexColor.rgba("FF8000").b, 0.0, accuracy: 0.001)
        XCTAssertEqual(NotchHexColor.rgba("#11223380").a, 128.0 / 255.0, accuracy: 0.001)
        // Malformed input is black, never a crash and never a guess.
        XCTAssertEqual(NotchHexColor.rgba("nonsense"), DockRGBA(r: 0, g: 0, b: 0, a: 1))
        XCTAssertEqual(NotchHexColor.rgba("#FFF"), DockRGBA(r: 0, g: 0, b: 0, a: 1))

        let custom = NotchSurfaceAppearance(preset: .custom, customHex: "#FF0000")
            .effectiveAppearance(isLowPowerMode: false)
        XCTAssertEqual(custom.baseColor.r, 1.0, accuracy: 0.001)
        XCTAssertEqual(custom.baseColor.g, 0.0, accuracy: 0.001)
        XCTAssertGreaterThan(custom.rimColor.g, custom.baseColor.g, "a custom rim is lifted toward white")
        XCTAssertEqual(custom.rimColor.r, 1.0, accuracy: 0.001)
        XCTAssertEqual(custom.rimOpacity, NotchColorPreset.custom.rimOpacity)
    }

    func testLowPowerModeForcesOpaqueOLEDBlack() {
        let stored = NotchSurfaceAppearance(preset: .midnightIndigo, customHex: "#FF0000", transparency: 0.6)
        let resolved = stored.effectiveAppearance(isLowPowerMode: true)
        XCTAssertEqual(resolved.preset, .oledBlack)
        XCTAssertEqual(resolved.transparency, 0.0)
        XCTAssertEqual(resolved.baseOpacity, 1.0)
        XCTAssertEqual(resolved.baseColor, NotchColorPreset.oledBlack.baseHex)
        XCTAssertEqual(resolved.rimColor, NotchColorPreset.oledBlack.rimHex)
        XCTAssertFalse(resolved.shouldRenderBlurMaterial)
        XCTAssertTrue(resolved.isPowerSavingOpaque)
    }

    func testSurfaceAppearanceRoundTripsThroughDefaults() {
        let defaults = UserDefaults(suiteName: "NotchSurfaceAppearanceTests.\(UUID())")!
        XCTAssertEqual(NotchSurfaceAppearance.load(defaults), NotchSurfaceAppearance())

        var stored = NotchSurfaceAppearance(preset: .crimsonVelvet, customHex: "#22AAFF", transparency: 0.4)
        stored.save(defaults)
        XCTAssertEqual(NotchSurfaceAppearance.load(defaults), stored)

        // An out-of-range stored value is saved clamped, so the view never reads something the slider cannot.
        NotchSurfaceAppearance(transparency: 3).save(defaults)
        XCTAssertEqual(NotchSurfaceAppearance.load(defaults).transparency, 0.85)
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

    func testActivityQueueFourTierPriorityWithNotifications() {
        let t0 = Date(timeIntervalSince1970: 3000)
        var queue = NotchActivityQueue(maxItems: 6)

        queue.enqueue(NotchActivityItem(id: "info", priority: .systemInfo, title: "Volume", icon: "speaker.wave.2.fill", createdAt: t0), now: t0)
        queue.enqueue(NotchActivityItem(id: "notif", priority: .notification, title: "AirDrop", icon: "airplayaudio", createdAt: t0.addingTimeInterval(1)), now: t0)
        queue.enqueue(NotchActivityItem(id: "media", priority: .media, title: "Music", icon: "music.note", createdAt: t0.addingTimeInterval(2)), now: t0)
        queue.enqueue(NotchActivityItem(id: "crit", priority: .critical, title: "Call", icon: "phone.fill", createdAt: t0.addingTimeInterval(3)), now: t0)

        XCTAssertEqual(queue.items.map(\.id), ["crit", "media", "notif", "info"])
        XCTAssertEqual(queue.items.first(where: { $0.id == "notif" })?.systemImage, "airplayaudio")
    }

    func testNotchGeometryCalculatorMultiDisplayOffsets() {
        let closed = CGSize(width: 185, height: 28)
        let open = CGSize(width: 600, height: 200)

        // Secondary right-side external monitor (non-notched, offset origin)
        let rightScreen = CGRect(x: 1920, y: 120, width: 2560, height: 1440)
        let rightLayout = NotchGeometryCalculator.calculate(
            screenBounds: rightScreen, topInset: 0, menuBarHeight: 24,
            closedSize: closed, openSize: open, isExpanded: false
        )
        XCTAssertEqual(rightLayout.mode, .floatingCapsule)
        XCTAssertEqual(rightLayout.panelFrame.minX, 1920 + (2560 - 185) / 2)
        XCTAssertEqual(rightLayout.panelFrame.maxY, 120 + 1440 - 32) // 24pt menu bar + 8pt margin

        // Secondary left-side external monitor (negative X origin)
        let leftScreen = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let leftOpen = NotchGeometryCalculator.calculate(
            screenBounds: leftScreen, topInset: 0, menuBarHeight: 24,
            closedSize: closed, openSize: open, isExpanded: true
        )
        XCTAssertEqual(leftOpen.panelFrame.minX, -1440 + (1440 - 600) / 2)
        XCTAssertEqual(leftOpen.panelFrame.maxY, 900 - 32)
    }
}
