import XCTest

@MainActor
final class DictionaryTerminalSettingsTests: XCTestCase {
    private func makeStore() -> (AppSettingsStore, UserDefaults) {
        let suite = "DictionaryTerminalSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (AppSettingsStore(defaults: defaults), defaults)
    }

    func testChipsDefaultOn() {
        let (store, _) = makeStore()
        XCTAssertTrue(store.showDictionaryChip)
        XCTAssertTrue(store.showTerminalChip)
    }

    func testChipTogglesPersistIndependently() {
        let (store, defaults) = makeStore()
        store.setShowDictionaryChip(false)
        let reloaded = AppSettingsStore(defaults: defaults)
        XCTAssertFalse(reloaded.showDictionaryChip)
        XCTAssertTrue(reloaded.showTerminalChip)
    }
}
