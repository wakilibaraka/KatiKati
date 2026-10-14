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
}
