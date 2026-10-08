import XCTest
@testable import KatiKati

final class DockThemeStyleTokensTests: XCTestCase {
    
    func testPresetsAreValueFrozen() {
        let roseLight = DockThemeStyleTokens.resolve(style: .roseQuartz, appearance: .light)
        XCTAssertEqual(roseLight.baseTint.r, 0.95)
        XCTAssertEqual(roseLight.baseTint.g, 0.85)
        XCTAssertEqual(roseLight.baseTint.b, 0.88)
        XCTAssertEqual(roseLight.prefersDarkContent, true)
        
        let obsDark = DockThemeStyleTokens.resolve(style: .obsidianDark, appearance: .dark)
        XCTAssertEqual(obsDark.baseTint.r, 0.05)
        XCTAssertEqual(obsDark.baseTint.g, 0.05)
        XCTAssertEqual(obsDark.baseTint.b, 0.05)
        XCTAssertEqual(obsDark.prefersDarkContent, false)
    }
    
    func testAutoResolvesToRoseAndObsidian() {
        let autoLight = DockThemeStyleTokens.resolve(style: .auto, appearance: .light)
        let roseLight = DockThemeStyleTokens.resolve(style: .roseQuartz, appearance: .light)
        XCTAssertEqual(autoLight, roseLight)
        
        let autoDark = DockThemeStyleTokens.resolve(style: .auto, appearance: .dark)
        let obsDark = DockThemeStyleTokens.resolve(style: .obsidianDark, appearance: .dark)
        XCTAssertEqual(autoDark, obsDark)
    }
    
    func testAllFieldsFinite() {
        let allStyles: [DockThemeStyle] = [
            .system, .translucent, .crystalClear, .obsidianDark, .monochrome,
            .titaniumFrost, .auroraGlow, .deepOcean, .forestMoss, .cyberpunkGlass,
            .emberSunset, .roseQuartz, .customRGBA(r: 0.5, g: 0.5, b: 0.5, a: 0.5)
        ]
        
        for style in allStyles {
            for appearance in [AppearanceMode.light, AppearanceMode.dark, AppearanceMode.system] {
                let token = DockThemeStyleTokens.resolve(style: style, appearance: appearance)
                XCTAssertTrue(token.baseTint.a.isFinite)
                XCTAssertTrue(token.gradientSheen.a.isFinite)
                XCTAssertTrue(token.glow.a.isFinite)
                XCTAssertTrue(token.rim.a.isFinite)
                XCTAssertTrue(token.blurRadius.isFinite)
            }
        }
    }
}
