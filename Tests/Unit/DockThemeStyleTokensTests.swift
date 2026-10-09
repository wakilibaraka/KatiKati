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
        
        let deepOceanLight = DockThemeStyleTokens.resolve(style: .deepOcean, appearance: .light)
        XCTAssertEqual(deepOceanLight.baseTint.r, 0.80)
        XCTAssertEqual(deepOceanLight.baseTint.g, 0.88)
        XCTAssertEqual(deepOceanLight.baseTint.b, 0.98)
        
        let emberSunsetDark = DockThemeStyleTokens.resolve(style: .emberSunset, appearance: .dark)
        XCTAssertEqual(emberSunsetDark.baseTint.r, 0.25)
        XCTAssertEqual(emberSunsetDark.baseTint.g, 0.12)
        XCTAssertEqual(emberSunsetDark.baseTint.b, 0.08)
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
        let all: [DockThemeStyleTokens] = [
            .systemLight, .systemDark,
            .translucentLight, .translucentDark,
            .crystalClearLight, .crystalClearDark,
            .obsidianDarkLight, .obsidianDarkDark,
            .monochromeLight, .monochromeDark,
            .titaniumFrostLight, .titaniumFrostDark,
            .auroraGlowLight, .auroraGlowDark,
            .deepOceanLight, .deepOceanDark,
            .forestMossLight, .forestMossDark,
            .cyberpunkGlassLight, .cyberpunkGlassDark,
            .emberSunsetLight, .emberSunsetDark,
            .roseQuartzLight, .roseQuartzDark
        ]
        for token in all {
            XCTAssertTrue(token.baseTint.r.isFinite)
            XCTAssertTrue(token.gradientSheen.r.isFinite)
            XCTAssertTrue(token.glow.r.isFinite)
            XCTAssertTrue(token.rim.r.isFinite)
            XCTAssertTrue(token.blurRadius.isFinite)
        }
    }
}
