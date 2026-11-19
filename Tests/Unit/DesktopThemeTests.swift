import CoreGraphics
import Foundation
import XCTest

final class DesktopThemeTests: XCTestCase {
    func testHexColorParseAndNormalization() {
        XCTAssertEqual(DesktopHexColor.normalized("#f80"), "#FF8800")
        XCTAssertEqual(DesktopHexColor.normalized("3b82f6"), "#3B82F6")
        XCTAssertNil(DesktopHexColor.parse("not-hex"))
        XCTAssertNil(DesktopHexColor.normalized("#12345"))
        let rgb = DesktopHexColor.parse("#FF0080")
        XCTAssertEqual(rgb?.r ?? -1, 1.0, accuracy: 0.001)
        XCTAssertEqual(rgb?.g ?? -1, 0.0, accuracy: 0.001)
    }

    func testAppearanceClampsValuesAndRoundTripsAllVariants() throws {
        let appearance = DesktopWidgetAppearance(
            materialOverride: .tintedGlass,
            borderStyle: .glow,
            accentHex: "0fa",
            textTreatment: .shadowed,
            iconBadge: .emoji(" 🚀🔥 "),
            background: .image(path: "/tmp/bg.png", opacity: 2.5, blurRadius: 99),
            cornerRadiusOverride: 100
        )

        XCTAssertEqual(appearance.accentHex, "#00FFAA")
        XCTAssertEqual(appearance.iconBadge, .emoji("🚀"))
        XCTAssertEqual(appearance.background, .image(path: "/tmp/bg.png", opacity: 1.0, blurRadius: 24.0))
        XCTAssertEqual(appearance.cornerRadiusOverride, DesktopCanvasConfig.cornerRadiusRange.upperBound)

        let data = try JSONEncoder().encode(appearance)
        let decoded = try JSONDecoder().decode(DesktopWidgetAppearance.self, from: data)
        XCTAssertEqual(decoded, appearance)

        let tintItem = DesktopWidgetAppearance(background: .tint(hex: "#123456", opacity: 0.01))
        XCTAssertEqual(tintItem.background, .tint(hex: "#123456", opacity: 0.05))
    }

    func testLegacyWidgetJSONDecodesToStandardAppearance() throws {
        let legacyJSON = #"{"title":"Downloads","frame":{"x":10,"y":20,"width":240,"height":200}}"#
        let item = try JSONDecoder().decode(DesktopWidgetItem.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(item.appearance, .standard)
    }
}
