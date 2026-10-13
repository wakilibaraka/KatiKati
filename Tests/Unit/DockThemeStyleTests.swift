import XCTest
@testable import KatiKati

final class DockThemeStyleTests: XCTestCase {
    
    func testTokenRoundTrip() {
        let presets: [DockThemeStyle] = [
            .system, .translucent, .crystalClear, .obsidianDark, .monochrome,
            .titaniumFrost, .auroraGlow, .deepOcean, .forestMoss, .cyberpunkGlass,
            .emberSunset, .roseQuartz, .auto
        ]
        
        for preset in presets {
            XCTAssertEqual(DockThemeStyle(token: preset.token), preset)
        }
        
        let custom = DockThemeStyle.customRGBA(r: 0.1, g: 0.2, b: 0.3, a: 0.4)
        XCTAssertEqual(DockThemeStyle(token: custom.token), custom)
    }
    
    func testUnknownKeyFallback() {
        XCTAssertNil(DockThemeStyle(token: ""))
        XCTAssertNil(DockThemeStyle(token: "invalidPreset"))
        XCTAssertNil(DockThemeStyle(token: "custom:1,2,3"))
        XCTAssertNil(DockThemeStyle(token: "custom:1,2,3,4,5"))
    }
    
    func testAutoResolutionMatrix() {
        let auto = DockThemeStyle.auto
        
        XCTAssertEqual(auto.resolved(for: .light), .roseQuartz)
        XCTAssertEqual(auto.resolved(for: .dark), .obsidianDark)
        XCTAssertEqual(auto.resolved(for: .system), .roseQuartz)
    }
    
    func testPinnedOverrideIgnoresAppearance() {
        let pinned = DockThemeStyle.titaniumFrost
        
        XCTAssertEqual(pinned.resolved(for: .light), .titaniumFrost)
        XCTAssertEqual(pinned.resolved(for: .dark), .titaniumFrost)
        XCTAssertEqual(pinned.resolved(for: .system), .titaniumFrost)
    }
    
    func testDebugSwitchOverride() {
        // Just verify it uses the env properly if we write a helper later, or just verify the debug switch exists
        XCTAssertEqual(DebugSwitch.dockTheme.rawValue, "DOCK_THEME")
    }

    // MARK: - Phase 11c: plate overlay

    func testAutoAndSystemKeepTheUntintedNativePlate() {
        let tint = DockRGBA(r: 0.1, g: 0.2, b: 0.3, a: 0.8)
        XCTAssertNil(DockThemeStyle.auto.plateOverlay(baseTint: tint))
        XCTAssertNil(DockThemeStyle.system.plateOverlay(baseTint: tint))
    }

    func testPresetsTintThePlateAtReducedStrength() {
        let tint = DockRGBA(r: 0.05, g: 0.15, b: 0.25, a: 0.7)
        let overlay = DockThemeStyle.deepOcean.plateOverlay(baseTint: tint)
        XCTAssertEqual(overlay, DockRGBA(r: 0.05, g: 0.15, b: 0.25, a: 0.7 * DockThemeStyle.plateOverlayStrength))
        XCTAssertNotNil(DockThemeStyle.customRGBA(r: 1, g: 0, b: 0, a: 0.5).plateOverlay(baseTint: tint))
    }
}

