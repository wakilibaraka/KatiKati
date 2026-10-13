import XCTest
@testable import KatiKati

final class LauncherFoldersTests: XCTestCase {
    private func app(_ id: String) -> LauncherApp { LauncherApp(bundleID: id, name: id, path: "/\(id)", installedAt: .distantPast) }
    private let f1 = "katikati.folder.1", f2 = "katikati.folder.2"

    func testCreateMovesAppsOutOfOtherFoldersAndDropsEmptyOnes() {
        var folders = LauncherFolders.create([], id: f1, name: "A", appIDs: ["x"])
        folders = LauncherFolders.create(folders, id: f2, name: "B", appIDs: ["x", "y"])
        XCTAssertEqual(folders.map(\.id), [f2], "the first folder emptied out and vanished")
        XCTAssertEqual(folders[0].appIDs, ["x", "y"])
    }

    func testAddRemoveRenameDelete() {
        var folders = LauncherFolders.create([], id: f1, name: "A", appIDs: ["x"])
        folders = LauncherFolders.add(folders, appID: "y", to: f1)
        folders = LauncherFolders.add(folders, appID: "y", to: f1)
        XCTAssertEqual(folders[0].appIDs, ["x", "y"])
        XCTAssertEqual(LauncherFolders.add(folders, appID: "z", to: "nope"), folders)
        folders = LauncherFolders.rename(folders, id: f1, to: "  Work ")
        XCTAssertEqual(folders[0].name, "Work")
        XCTAssertEqual(LauncherFolders.rename(folders, id: f1, to: "   ")[0].name, "Work")
        folders = LauncherFolders.remove(folders, appID: "x")
        XCTAssertEqual(folders[0].appIDs, ["y"])
        XCTAssertTrue(LauncherFolders.remove(folders, appID: "y").isEmpty)
        XCTAssertTrue(LauncherFolders.delete(folders, id: f1).isEmpty)
    }

    func testLooseMembersAndCell() {
        let folders = [LauncherFolder(id: f1, name: "F", appIDs: ["a", "gone"])]
        let apps = [app("a"), app("b")]
        XCTAssertEqual(LauncherFolders.loose(apps, folders: folders).map(\.bundleID), ["b"])
        XCTAssertEqual(LauncherFolders.members(of: folders[0], in: apps).map(\.bundleID), ["a"])
        XCTAssertTrue(LauncherFolders.isFolderID(LauncherFolders.cell(folders[0]).bundleID))
        XCTAssertTrue(LauncherFolders.isFolderID(LauncherFolders.newID()))
    }

    func testOrderReplacement() {
        XCTAssertEqual(LauncherFolders.order(["a", "b", "c"], replacing: "b", with: f1), ["a", f1, "c"])
        XCTAssertEqual(LauncherFolders.order(["a"], replacing: "zz", with: f1), ["a"])
    }

    func testFocusArrowsRowsAndPages() {
        // page0: one section of 5 ids at 3 columns → rows [a b c][d e]; page1: [f g h]
        let pages: [[[String]]] = [[["a", "b", "c", "d", "e"]], [["f", "g", "h"]]]
        func go(_ from: String?, page: Int = 0, dx: Int = 0, dy: Int = 0) -> LauncherFocus.Position? {
            LauncherFocus.move(pages: pages, columns: 3, from: from, currentPage: page, dx: dx, dy: dy)
        }
        XCTAssertEqual(go(nil), .init(page: 0, id: "a"))
        XCTAssertEqual(go(nil, page: 1), .init(page: 1, id: "f"))
        XCTAssertEqual(go("c", dx: 1), .init(page: 0, id: "d"), "right wraps to the next row")
        XCTAssertEqual(go("e", dx: 1), .init(page: 1, id: "f"), "right crosses to the next page")
        XCTAssertEqual(go("f", dx: -1), .init(page: 0, id: "e"))
        XCTAssertEqual(go("a", dx: -1), .init(page: 0, id: "a"))
        XCTAssertEqual(go("c", dy: 1), .init(page: 0, id: "e"), "column clamps to the shorter row")
        XCTAssertEqual(go("e", dy: 1), .init(page: 0, id: "e"))
        XCTAssertEqual(go("b", dy: -1), .init(page: 0, id: "b"))
        XCTAssertEqual(go("zzz", page: 1), .init(page: 1, id: "f"))
        XCTAssertNil(LauncherFocus.move(pages: [], columns: 3, from: nil, currentPage: 0, dx: 0, dy: 0))
    }

    func testPageHidesFolderMembersAndShowsOneFolderCell() {
        let apps = [app("a"), app("b"), app("c")]
        let folder = LauncherFolder(id: f1, name: "Work", appIDs: ["a", "b"])
        let page = LauncherAppIndex.page(apps: apps, usage: [:], pinned: [], presets: [], columns: 4,
                                         now: Date(), folders: [folder])
        XCTAssertEqual(Set(page.all.map(\.bundleID)), ["c", f1])
        XCTAssertTrue(page.mostUsed.isEmpty && page.recentlyInstalled.isEmpty)
        // An emptied (uninstalled) folder shows no cell.
        let ghost = LauncherFolder(id: f2, name: "Ghost", appIDs: ["zzz"])
        XCTAssertFalse(LauncherAppIndex.page(apps: apps, usage: [:], pinned: [], presets: [], columns: 4, now: Date(),
                                             folders: [ghost]).all.contains { $0.bundleID == f2 })
    }

    func testStateRoundTripsFoldersAndOldFilesStillDecode() throws {
        var state = LauncherState()
        state.folders = [LauncherFolder(id: f1, name: "F", appIDs: ["a"])]
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(LauncherState.self, from: data).folders, state.folders)
        let old = #"{"usage":{},"pinned":["x"],"hidden":[],"order":[]}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(LauncherState.self, from: old).folders, [])
    }
}
