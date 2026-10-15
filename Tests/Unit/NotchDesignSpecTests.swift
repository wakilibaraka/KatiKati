import CoreGraphics
import XCTest
@testable import KatiKati

final class NotchDesignSpecTests: XCTestCase {
    // MARK: - Hardware Notch Resolution
    func testRealNotchWidthAndKeepoutFromAuxiliaryAreas() {
        // 1728 x 1117 screen (16" MacBook Pro): auxLeft = 760, auxRight = 760, safeAreaTop = 38
        // notch width = 1728 - 760 - 760 + 4 = 212
        let m = NotchDesignSpec.resolve(
            screenWidth: 1728,
            safeAreaTop: 38,
            auxLeftWidth: 760,
            auxRightWidth: 760,
            menuBarHeight: 38
        )
        XCTAssertTrue(m.hasHardwareNotch)
        XCTAssertEqual(m.closedSize.width, 212)
        XCTAssertEqual(m.closedSize.height, 38)

        // Camera keepout is centered horizontally in the 212px closed notch
        // originX = (212 - 160) / 2 = 26
        XCTAssertEqual(m.cameraKeepoutBox.origin.x, 26)
        XCTAssertEqual(m.cameraKeepoutBox.origin.y, 0)
        XCTAssertEqual(m.cameraKeepoutBox.size.width, 160)
        XCTAssertEqual(m.cameraKeepoutBox.size.height, 38)
    }

    func testNotchlessDisplayHasNoHardwareNotchAndEmptyKeepout() {
        // External monitor: 2560 x 1440, safeAreaTop = 0, menuBarHeight = 24
        let m = NotchDesignSpec.resolve(
            screenWidth: 2560,
            safeAreaTop: 0,
            auxLeftWidth: nil,
            auxRightWidth: nil,
            menuBarHeight: 24
        )
        XCTAssertFalse(m.hasHardwareNotch)
        XCTAssertEqual(m.closedSize.width, NotchDesignSpec.fallbackClosedWidth)
        XCTAssertEqual(m.closedSize.height, 24)
        XCTAssertEqual(m.cameraKeepoutBox, .zero)
    }

    func testBadAuxiliaryAreasFallBackGracefully() {
        // Negative or overflowing auxiliary widths
        let m = NotchDesignSpec.resolve(
            screenWidth: 1440,
            safeAreaTop: 32,
            auxLeftWidth: -10,
            auxRightWidth: 700,
            menuBarHeight: 32
        )
        XCTAssertTrue(m.hasHardwareNotch)
        XCTAssertEqual(m.closedSize.width, NotchDesignSpec.fallbackClosedWidth)
        XCTAssertEqual(m.closedSize.height, 32)
        XCTAssertEqual(m.cameraKeepoutBox.width, 160)
    }

    // MARK: - Wing Width Clamping
    func testWingWidthClampedWithinSafeRange() {
        XCTAssertEqual(NotchDesignSpec.clampWingWidth(20), 48)
        XCTAssertEqual(NotchDesignSpec.clampWingWidth(64), 64)
        XCTAssertEqual(NotchDesignSpec.clampWingWidth(120), 88)
    }

    // MARK: - Open Panel Sizing
    func testOpenPanelSizeClampedToScreen() {
        // Wide screen: takes standard 660pt width
        let standard = NotchDesignSpec.openPanelSize(screenWidth: 1728, closedWidth: 212)
        XCTAssertEqual(standard.width, 660)
        XCTAssertEqual(standard.height, 216)

        // Compact mode: takes compact 520pt width
        let compact = NotchDesignSpec.openPanelSize(screenWidth: 1728, closedWidth: 212, isCompact: true)
        XCTAssertEqual(compact.width, 520)
        XCTAssertEqual(compact.height, 160)

        // Extremely narrow screen (e.g. 600pt width): clamped to screenWidth - 24 = 576
        let narrow = NotchDesignSpec.openPanelSize(screenWidth: 600, closedWidth: 212)
        XCTAssertEqual(narrow.width, 576)
        XCTAssertEqual(narrow.height, 216)
    }

    // MARK: - Motion Spec Springs
    func testMotionSpringParameters() {
        // Open spring is under-damped for tactile momentum overshoot
        XCTAssertLessThan(NotchMotionSpec.openSpring.dampingRatio, 1.0)
        XCTAssertEqual(NotchMotionSpec.openSpring.response, 0.38)
        XCTAssertEqual(NotchMotionSpec.openSpring.dampingRatio, 0.82)

        // Close spring is critically damped (1.0) to prevent bouncing past the screen bezel
        XCTAssertEqual(NotchMotionSpec.closeSpring.dampingRatio, 1.0)
        XCTAssertEqual(NotchMotionSpec.closeSpring.response, 0.32)

        // Reduced motion timing is 150ms
        XCTAssertEqual(NotchMotionSpec.reducedMotionDuration, 0.15)
    }

    func testMomentumProjection() {
        // Forward fling: velocity = 500 pt/s, current = 100
        let projected = NotchMotionSpec.projectEndpoint(current: 100, velocity: 500)
        XCTAssertGreaterThan(projected, 100)

        // Negative fling: velocity = -500 pt/s
        let projectedBack = NotchMotionSpec.projectEndpoint(current: 100, velocity: -500)
        XCTAssertLessThan(projectedBack, 100)

        // Zero velocity stays exactly at current position
        let stationary = NotchMotionSpec.projectEndpoint(current: 100, velocity: 0)
        XCTAssertEqual(stationary, 100)
    }

    // MARK: - Phase 12: the notch's plate and content scheme

    /// The invariant the owner's decision rests on: a hardware notch is always black with light
    /// content, whatever theme is pinned. Only a floating island may carry a tint.
    func testHardwareNotchStaysBlackWithLightContentUnderEveryTheme() {
        for style in [DockThemeStyle.auto, .system, .emberSunset, .titaniumFrost, .deepOcean] {
            let tokens = DockThemeStyleTokens.resolve(style: style, appearance: .dark)
            for tints in [true, false] {
                let resolved = NotchTheme.resolve(hasHardwareNotch: true, tintsPlate: tints, tokens: tokens)
                XCTAssertEqual(resolved.plate, NotchTheme.blackPlate, "\(style.token) tinted a hardware notch")
                XCTAssertFalse(resolved.prefersDarkContent, "\(style.token) flipped the notch's content scheme")
            }
        }
    }

    func testOnlyATintedFloatingIslandChangesThePlate() {
        let sunset = DockThemeStyleTokens.resolve(style: .emberSunset, appearance: .dark)
        let island = NotchTheme.resolve(hasHardwareNotch: false, tintsPlate: true, tokens: sunset)
        XCTAssertNotEqual(island.plate, NotchTheme.blackPlate)
        XCTAssertEqual(island.plate.r, sunset.baseTint.r)
        XCTAssertGreaterThanOrEqual(island.plate.a, 0.94, "the silhouette has to stay solid")

        // auto / system tint nothing, so the island keeps the black plate it has always drawn.
        let auto = NotchTheme.resolve(
            hasHardwareNotch: false,
            tintsPlate: DockThemeStyle.auto.tintsPlate,
            tokens: DockThemeStyleTokens.resolve(style: .auto, appearance: .dark)
        )
        XCTAssertEqual(auto.plate, NotchTheme.blackPlate)
        XCTAssertFalse(auto.prefersDarkContent)
    }
}
