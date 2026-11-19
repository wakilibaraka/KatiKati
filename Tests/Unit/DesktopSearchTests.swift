import CoreGraphics
import Foundation
import XCTest

final class DesktopSearchTests: XCTestCase {
    // MARK: - Path filter

    func testPathFilterExcludesCachesSystemAndUserPaths() {
        let filter = SearchPathFilter(userExcludedPaths: ["~/Projects/archive", "/Volumes/Old"])
        XCTAssertTrue(filter.allows("\(NSHomeDirectory())/Documents/Report.pdf"))
        XCTAssertTrue(filter.allows("/Applications/Safari.app"))
        XCTAssertFalse(filter.allows("/System/Library/CoreServices/Finder.app"))
        XCTAssertFalse(filter.allows("\(NSHomeDirectory())/Library/Caches/com.example/data"))
        XCTAssertFalse(filter.allows("\(NSHomeDirectory())/Projects/app/node_modules/pkg/index.js"))
        XCTAssertFalse(filter.allows("\(NSHomeDirectory())/Projects/archive/old.txt"))
        XCTAssertFalse(filter.allows("/Volumes/Old/backup.zip"))
    }

    func testPathFilterAllowsSiblingWithSharedPrefix() {
        let filter = SearchPathFilter(userExcludedPaths: ["/Users/me/Library/Caches2"])
        XCTAssertTrue(filter.allows("/Users/me/Library/CachesBackup/keep.txt"))
    }

    // MARK: - History & favorites

    func testHistoryDeduplicatesAndStaysBounded() {
        var history = DesktopSearchHistory()
        for index in 0..<(DesktopSearchConfig.historyLimit + 4) {
            history = history.recording("query \(index)")
        }
        XCTAssertEqual(history.queries.count, DesktopSearchConfig.historyLimit)
        XCTAssertEqual(history.queries.first, "query \(DesktopSearchConfig.historyLimit + 3)")

        history = history.recording("QUERY 15")
        XCTAssertEqual(history.queries.first, "QUERY 15")
        XCTAssertEqual(history.queries.filter { $0.caseInsensitiveCompare("query 15") == .orderedSame }.count, 1)
    }

    func testFavoritesToggleAndCodableRoundTrip() throws {
        let result = DesktopSearchResult(
            id: "app:com.apple.Safari",
            provider: .app,
            title: "Safari",
            subtitle: "/Applications/Safari.app",
            path: "/Applications/Safari.app",
            payload: "com.apple.Safari",
            symbol: "app"
        )
        var favorites = DesktopSearchFavorites()
        XCTAssertFalse(favorites.contains(result.id))
        favorites = favorites.toggling(result)
        XCTAssertTrue(favorites.contains(result.id))

        let data = try JSONEncoder().encode(favorites)
        let decoded = try JSONDecoder().decode(DesktopSearchFavorites.self, from: data)
        XCTAssertEqual(decoded, favorites)

        favorites = favorites.toggling(result)
        XCTAssertFalse(favorites.contains(result.id))
    }

    // MARK: - Ranking

    func testRankerDeduplicatesAndPrefersExactProviderMatches() {
        let app = DesktopSearchResult(id: "app:safari", provider: .app, title: "Safari", subtitle: "/Applications", symbol: "app")
        let file = DesktopSearchResult(id: "file:safari", provider: .file, title: "safari-notes.txt", subtitle: "~/Documents", path: "~/Documents/safari-notes.txt", symbol: "doc")
        let duplicate = DesktopSearchResult(id: "app:safari", provider: .app, title: "Safari", subtitle: "/Applications", symbol: "app")
        let ranked = DesktopSearchRanker.rank([file, app, duplicate], query: "safari", limit: 10)
        XCTAssertEqual(ranked.map(\.id), ["app:safari", "file:safari"])
    }

    func testRankerHonoursLimitAndEmptyQueryOrder() {
        let rows = (0..<8).map {
            DesktopSearchResult(id: "file:\($0)", provider: .file, title: "File \($0)", subtitle: "", symbol: "doc")
        }
        XCTAssertEqual(DesktopSearchRanker.rank(rows, query: "", limit: 3).count, 3)
        XCTAssertEqual(DesktopSearchRanker.rank(rows, query: "File", limit: 5).count, 5)
    }

    // MARK: - Selection

    func testSelectionToggleRangeAndRubberBand() {
        let ids = ["a", "b", "c", "d"]
        var selection = DesktopSearchSelectionModel()
        selection.toggle("b", in: ids)
        XCTAssertEqual(selection.selectedIDs, ["b"])

        selection.selectRange(to: "d", in: ids)
        XCTAssertEqual(selection.selectedIDs, ["b", "c", "d"])

        selection.toggle("c", in: ids)
        XCTAssertEqual(selection.selectedIDs, ["b", "d"])

        let frames: [String: CGRect] = [
            "a": CGRect(x: 0, y: 0, width: 100, height: 20),
            "b": CGRect(x: 0, y: 22, width: 100, height: 20),
            "c": CGRect(x: 0, y: 44, width: 100, height: 20),
            "d": CGRect(x: 0, y: 66, width: 100, height: 20)
        ]
        selection.rubberBand(CGRect(x: 0, y: 21, width: 100, height: 25), rowFrames: frames, additive: false)
        XCTAssertEqual(selection.selectedIDs, ["b", "c"])

        selection.rubberBand(CGRect(x: 0, y: 65, width: 100, height: 25), rowFrames: frames, additive: true)
        XCTAssertEqual(selection.selectedIDs, ["b", "c", "d"])
    }

    // MARK: - Batch actions

    func testBatchActionsFollowAvailableProviders() {
        let file = DesktopSearchResult(id: "file:1", provider: .file, title: "A", subtitle: "", path: "/tmp/a", symbol: "doc")
        let note = DesktopSearchResult(id: "note:1", provider: .note, title: "B", subtitle: "", payload: "n1", symbol: "note.text")
        let setting = DesktopSearchResult(id: "setting:1", provider: .setting, title: "C", subtitle: "", payload: "desktop", symbol: "gearshape")

        XCTAssertEqual(
            DesktopSearchBatchAction.available(for: [file]),
            [.open, .reveal, .copy, .moveToBox, .trash]
        )
        XCTAssertEqual(DesktopSearchBatchAction.available(for: [note]), [.copy])
        XCTAssertEqual(DesktopSearchBatchAction.available(for: [setting]), [.open, .copy])
        XCTAssertEqual(DesktopSearchBatchAction.filePaths(in: [file, note]), ["/tmp/a"])
        XCTAssertEqual(
            DesktopSearchBatchAction.clipboardText(for: [file, note]),
            "/tmp/a\nB"
        )
        XCTAssertTrue(DesktopSearchBatchAction.trash.requiresConfirmation)
    }

    func testConfigClampsResultLimitAndParsesExcludedPaths() {
        XCTAssertEqual(DesktopSearchConfig.resultLimitKey, "com.katikati.desktop.searchResultLimit")
        XCTAssertEqual(DesktopSearchConfig.excludedPathsKey, "com.katikati.desktop.searchExcludedPaths")
        XCTAssertEqual(DesktopSearchConfig.clampedResultLimit(1), 10)
        XCTAssertEqual(DesktopSearchConfig.clampedResultLimit(500), 120)
        XCTAssertEqual(DesktopSearchConfig.clampedResultLimit(55), 55)
        XCTAssertEqual(
            DesktopSearchConfig.encodedExcludedPaths(["/a", "/b"]),
            "/a\n/b"
        )
    }
}
