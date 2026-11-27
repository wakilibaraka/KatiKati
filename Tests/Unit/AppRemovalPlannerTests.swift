import XCTest
@testable import KatiKati

final class AppRemovalPlannerTests: XCTestCase {

    func testUninstallTargetsTheBundle() {
        let plan = AppRemovalPlanner.plan(bundleID: "com.x.Y", name: "Y", appPath: "/Applications/Y.app", removal: .uninstall)
        XCTAssertEqual(plan.paths, ["/Applications/Y.app"])
        XCTAssertTrue(AppRemoval.uninstall.needsQuitFirst)
    }

    func testDeleteDataFiltersToExisting() {
        let home = "/Users/me"
        let candidates = AppRemovalPlanner.dataPaths(bundleID: "com.x.Y", name: "Y", home: home)
        XCTAssertTrue(candidates.contains("\(home)/Library/Caches/com.x.Y"))
        XCTAssertTrue(candidates.contains("\(home)/Library/Preferences/com.x.Y.plist"))

        let existing = Set([candidates[0], candidates[2]])
        let plan = AppRemovalPlanner.plan(bundleID: "com.x.Y", name: "Y", appPath: "/Applications/Y.app",
                                          removal: .deleteData, home: home, exists: { existing.contains($0) })
        XCTAssertEqual(plan.paths, [candidates[0], candidates[2]])
    }

    func testDeleteDataWithNothingOnDiskIsEmpty() {
        let plan = AppRemovalPlanner.plan(bundleID: "com.x.Y", name: "Y", appPath: "/Applications/Y.app",
                                          removal: .deleteData, exists: { _ in false })
        XCTAssertTrue(plan.paths.isEmpty)
    }

    func testDeleteDataRejectsEmptyAndTraversalTargets() {
        for (bundleID, name) in [("", "App"), ("..", "App"), ("com.x/../../", "App"), ("com.x.App", "../") ] {
            XCTAssertTrue(AppRemovalPlanner.dataPaths(bundleID: bundleID, name: name, home: "/Users/me").isEmpty,
                          "unsafe identity must never produce Trash candidates: \(bundleID), \(name)")
        }
    }
}

/// MB-11: the opt-in Uninstaller's catalogue.
final class UninstallerCatalogTests: XCTestCase {
    private func app(_ id: String, _ name: String, _ path: String, added: TimeInterval = 0) -> LauncherApp {
        LauncherApp(bundleID: id, name: name, path: path, installedAt: Date(timeIntervalSince1970: added))
    }

    func testSystemBundlesAreNeverOffered() {
        let entries = UninstallerCatalog.entries(from: [
            app("com.apple.Safari", "Safari", "/System/Applications/Safari.app"),
            app("com.x.Y", "Y", "/Applications/Y.app"),
        ])
        XCTAssertEqual(entries.map(\.bundleID), ["com.x.Y"])
    }

    func testOneEntryPerBundleAndTheShortestPathWins() {
        let entries = UninstallerCatalog.entries(from: [
            app("com.x.Y", "Y", "/Users/me/Downloads/Y.app"),
            app("com.x.Y", "Y", "/Applications/Y.app"),
        ])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.path, "/Applications/Y.app")
    }

    func testSortedByNameAndSearchableByBundle() {
        let entries = UninstallerCatalog.entries(from: [
            app("com.x.Z", "Zeta", "/Applications/Zeta.app"),
            app("com.x.A", "alpha", "/Applications/alpha.app"),
        ])
        XCTAssertEqual(entries.map(\.name), ["alpha", "Zeta"])
        XCTAssertEqual(UninstallerCatalog.filter(entries, query: "com.x.Z").map(\.name), ["Zeta"])
        XCTAssertEqual(UninstallerCatalog.filter(entries, query: "  ").count, 2)
    }
}
