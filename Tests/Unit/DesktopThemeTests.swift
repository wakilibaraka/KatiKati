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

    @MainActor
    func testAppearanceRoundTripsThroughDesktopBoxStoreAndSettingsBackup() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suiteName = "katikati.desktop.theme.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: dir)
        }

        let boxesURL = dir.appendingPathComponent("desktop-boxes.json", isDirectory: false)
        let customAppearance = DesktopWidgetAppearance(
            materialOverride: .tintedGlass,
            borderStyle: .glow,
            accentHex: "#8B5CF6",
            textTreatment: .highContrast,
            iconBadge: .emoji("🎨"),
            background: .panorama,
            cornerRadiusOverride: 22
        )
        let item = DesktopWidgetItem(title: "Studio", appearance: customAppearance)

        let store = DesktopBoxStore(storageURL: boxesURL, debounceInterval: 0.01)
        store.add(item)
        store.flushNow()

        let reloadedStore = DesktopBoxStore(storageURL: boxesURL, debounceInterval: 0.01)
        XCTAssertEqual(reloadedStore.items.first?.appearance, customAppearance)

        defaults.set(DesktopBoxMaterialStyle.solidCard.rawValue, forKey: DesktopCanvasConfig.materialStyleKey)
        defaults.set(true, forKey: DesktopCanvasConfig.panoramaEnabledKey)
        defaults.set("/tmp/panorama.png", forKey: DesktopCanvasConfig.panoramaImagePathKey)
        defaults.set(0.42, forKey: DesktopCanvasConfig.panoramaOpacityKey)
        defaults.set(6.0, forKey: DesktopCanvasConfig.panoramaBlurKey)
        defaults.set(DesktopPanoramaScaleMode.aspectFit.rawValue, forKey: DesktopCanvasConfig.panoramaScaleModeKey)
        let expectedTheme = DesktopCanvasThemeState.load(defaults: defaults)

        let service = SettingsBackupService(
            defaults: defaults,
            domainName: suiteName,
            supportDirectory: dir,
            appVersion: "1.0"
        )
        let backup = service.makeBackup(categories: [.settingsAndShortcuts])
        for key in [
            DesktopCanvasConfig.materialStyleKey,
            DesktopCanvasConfig.panoramaEnabledKey,
            DesktopCanvasConfig.panoramaImagePathKey,
            DesktopCanvasConfig.panoramaOpacityKey,
            DesktopCanvasConfig.panoramaBlurKey,
            DesktopCanvasConfig.panoramaScaleModeKey,
        ] {
            XCTAssertNotNil(backup.defaults[key], "Missing Phase 62 key \(key) in backup defaults")
        }
        XCTAssertNotNil(backup.files["desktop-boxes.json"])

        defaults.removePersistentDomain(forName: suiteName)
        try FileManager.default.removeItem(at: boxesURL)
        try service.restore(backup, categories: [.settingsAndShortcuts])

        XCTAssertEqual(DesktopCanvasThemeState.load(defaults: defaults), expectedTheme)
        let restoredStore = DesktopBoxStore(storageURL: boxesURL, debounceInterval: 0.01)
        XCTAssertEqual(restoredStore.items.first?.appearance, customAppearance)
    }
}
