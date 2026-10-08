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
}
