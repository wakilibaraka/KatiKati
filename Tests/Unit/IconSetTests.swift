import XCTest

final class IconSetTests: XCTestCase {
    func testMissingOrUnknownValueFallsBackToModern() {
        XCTAssertEqual(IconSet(storedValue: nil), .modern)
        XCTAssertEqual(IconSet(storedValue: "neon"), .modern)
        XCTAssertEqual(IconSet(storedValue: "classic"), .classic)
    }

    func testClassicTrashSymbolFollowsFullness() {
        XCTAssertEqual(IconSet.classicTrashSymbol(isFull: false), "trash")
        XCTAssertEqual(IconSet.classicTrashSymbol(isFull: true), "trash.fill")
    }

    @MainActor
    func testStorePersistsIconSetIndependentlyOfTheme() {
        let defaults = TestDefaults.make("IconSetTests", for: self)
        let store = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(store.iconSet, .modern)
        store.setThemeMaterial(.deepOcean)
        store.setIconSet(.classic)
        let reloaded = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.iconSet, .classic)
        XCTAssertEqual(reloaded.themeMaterial, .deepOcean)
        XCTAssertEqual(defaults.string(forKey: "com.katikati.iconSet"), "classic")
    }
}
