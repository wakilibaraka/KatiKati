import XCTest
@testable import KatiKati

final class SettingsSearchIndexTests: XCTestCase {
    func testFuzzyTyposAndSynonymsResolveExpectedTabs() {
        XCTAssertEqual(SettingsSearchIndex.matchingTabs(for: "wether").first, .weather)
        XCTAssertEqual(SettingsSearchIndex.matchingTabs(for: "launchr").first, .launcher)
        XCTAssertEqual(SettingsSearchIndex.matchingTabs(for: "autohide").first, .dockItems)
        XCTAssertTrue(SettingsSearchIndex.matchingTabs(for: "spaces").contains(.experimental))
        XCTAssertTrue(SettingsSearchIndex.matchingTabs(for: "raycast").contains(.commandBar))
        XCTAssertTrue(SettingsSearchIndex.matchingTabs(for: "wings").contains(.dockItems))
        XCTAssertTrue(SettingsSearchIndex.matchingTabs(for: "glass").contains(.appearance))
    }

    func testRowContentSearchIndexesMovedAndNestedSettings() {
        XCTAssertTrue(SettingsSearchIndex.matchingTabs(for: "Detached Capsule").contains(.dockItems))
        XCTAssertTrue(SettingsSearchIndex.matchingTabs(for: "Left Wing").contains(.dockItems))
        XCTAssertTrue(SettingsSearchIndex.matchingTabs(for: "Lock Screen Card").contains(.experimental))
        XCTAssertTrue(SettingsSearchIndex.matchingTabs(for: "Album Art Wallpaper").contains(.experimental))
        XCTAssertTrue(SettingsSearchIndex.matchingTabs(for: "Mission Control").contains(.experimental))
        XCTAssertTrue(SettingsSearchIndex.matchingTabs(for: "F2 Rename").contains(.keyboard))
    }

    func testResolvedRowQueryMapsSynonymsToConcreteRowTitles() {
        let resolved = SettingsSearchIndex.resolvedRowQuery(for: .dockItems, userQuery: "autohide")
        XCTAssertEqual(resolved.lowercased(), "hide dock")
    }
}
