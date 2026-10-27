import XCTest

// Port plan #4a: the rules for applying a bar profile. The promise under test is that applying one only
// edits kept apps, pinned folders, the widget preset and the layout, never anything about windows, and
// that applying the same profile twice does nothing the second time.

final class BarProfileTests: XCTestCase {
    private let finder = "com.apple.finder", safari = "com.apple.Safari", mail = "com.apple.mail"
    private let xcode = "com.apple.dt.Xcode", steam = "com.valvesoftware.steam"

    private func state(kept: [String] = [], folders: [String] = [], preset: String? = nil, layout: String? = nil) -> BarProfileState {
        BarProfileState(keptApps: kept, pinnedFolders: folders, widgetPresetID: preset, layoutMode: layout)
    }

    private func edits(_ current: BarProfileState, _ profile: BarProfile,
                       missingApps: Set<String> = [], missingFolders: Set<String> = []) -> BarProfilePlan.Edits {
        BarProfilePlan.edits(from: current, to: profile,
                             isInstalled: { !missingApps.contains($0) }, folderExists: { !missingFolders.contains($0) })
    }

    func testAppsNotInTheProfileLoseTheirSlotAndNewOnesAreAddedInOrder() {
        let plan = edits(state(kept: [finder, safari, steam]), BarProfile(name: "Work", keptApps: [finder, xcode, mail]))
        XCTAssertEqual(plan.keptToRemove, [safari, steam])
        XCTAssertEqual(plan.keptToAdd, [xcode, mail])
        XCTAssertEqual(plan.finalKeptOrder, [finder, xcode, mail])
    }

    func testPlanHasNoWindowVocabulary() {
        // Edits only names kept apps and folders; there is no quit, open or move in the type to misuse.
        let plan = edits(state(kept: [safari]), BarProfile(name: "Empty"))
        XCTAssertEqual(plan.keptToRemove, [safari], "a running app only loses its kept slot")
    }

    func testSameSetInANewOrderIsAReorderNotAnEdit() {
        let plan = edits(state(kept: [finder, safari]), BarProfile(name: "Swap", keptApps: [safari, finder]))
        XCTAssertTrue(plan.keptToRemove.isEmpty && plan.keptToAdd.isEmpty)
        XCTAssertTrue(plan.reordersKept)
        XCTAssertFalse(plan.isNoOp)
        XCTAssertEqual(plan.finalKeptOrder, [safari, finder])
    }

    func testApplyingTheSameProfileTwiceIsANoOp() {
        let profile = BarProfile(name: "Work", keptApps: [finder, mail], pinnedFolders: ["/Users/a/Docs"],
                                 widgetPresetID: "builtin.focus", layoutMode: "split3")
        let applied = state(kept: [finder, mail], folders: ["/Users/a/Docs"], preset: "builtin.focus", layout: "split3")
        XCTAssertTrue(edits(applied, profile).isNoOp)
    }

    func testUninstalledAppsAndMissingFoldersAreSkippedAndReported() {
        let plan = edits(state(), BarProfile(name: "Old", keptApps: [finder, steam], pinnedFolders: ["/gone", "/here"]),
                         missingApps: [steam], missingFolders: ["/gone"])
        XCTAssertEqual(plan.keptToAdd, [finder])
        XCTAssertEqual(plan.skippedApps, [steam])
        XCTAssertEqual(plan.foldersToPin, ["/here"])
        XCTAssertEqual(plan.skippedFolders, ["/gone"])
    }

    func testFoldersFollowTheSameRules() {
        let plan = edits(state(folders: ["/a", "/b"]), BarProfile(name: "F", pinnedFolders: ["/b", "/c"]))
        XCTAssertEqual(plan.foldersToUnpin, ["/a"])
        XCTAssertEqual(plan.foldersToPin, ["/c"])
        XCTAssertEqual(plan.finalFolderOrder, ["/b", "/c"])
    }

    func testPresetAndLayoutOnlyChangeWhenTheProfileSetsThem() {
        let none = edits(state(preset: "builtin.music", layout: "centered"), BarProfile(name: "Leave"))
        XCTAssertNil(none.widgetPresetID)
        XCTAssertNil(none.layoutMode)
        let set = edits(state(preset: "builtin.music", layout: "centered"),
                        BarProfile(name: "Set", widgetPresetID: "builtin.focus", layoutMode: "split4"))
        XCTAssertEqual(set.widgetPresetID, "builtin.focus")
        XCTAssertEqual(set.layoutMode, .split4)
    }

    func testAnUnknownLayoutFromANewerBuildIsIgnored() {
        let plan = edits(state(layout: "windows"), BarProfile(name: "Future", layoutMode: "hologram"))
        XCTAssertNil(plan.layoutMode)
        XCTAssertTrue(plan.isNoOp)
    }

    func testDuplicatesAndBlanksInAProfileCollapse() {
        let plan = edits(state(), BarProfile(name: "Dupes", keptApps: [finder, "", finder, mail]))
        XCTAssertEqual(plan.finalKeptOrder, [finder, mail])
    }

    func testSnapshotRoundTripsThroughApply() {
        let current = state(kept: [finder, safari, mail], folders: ["/a"], preset: "builtin.full", layout: "split5")
        let profile = BarProfilePlan.snapshot(of: current, name: "Now", id: "p1")
        XCTAssertEqual(profile.keptApps, [finder, safari, mail])
        XCTAssertTrue(edits(current, profile).isNoOp, "saving the bar and applying it straight away changes nothing")
    }

    func testDecodeToleratesMissingAndExtraFields() throws {
        let json = #"{"id":"x","name":"Old","keptApps":["a"],"someFutureField":1}"#.data(using: .utf8)!
        let profile = try JSONDecoder().decode(BarProfile.self, from: json)
        XCTAssertEqual(profile.name, "Old")
        XCTAssertEqual(profile.keptApps, ["a"])
        XCTAssertEqual(profile.pinnedFolders, [])
        XCTAssertNil(profile.layoutMode)
    }

    func testEncodeDecodeRoundTrip() throws {
        let profile = BarProfile(id: "p", name: "Gaming", keptApps: [steam], pinnedFolders: ["/g"], widgetPresetID: "builtin.music", layoutMode: "centered")
        let data = try JSONEncoder().encode(profile)
        XCTAssertEqual(try JSONDecoder().decode(BarProfile.self, from: data), profile)
    }
}
