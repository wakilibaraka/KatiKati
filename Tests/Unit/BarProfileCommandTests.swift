import XCTest

/// 命令栏里的 `profile ` 模式：列出、过滤、`profile save <name>`。
final class BarProfileCommandTests: XCTestCase {
    private let work = BarProfileSummary(id: "1", name: "Work", appCount: 4)
    private let play = BarProfileSummary(id: "2", name: "Gaming", appCount: 2)

    private func rows(_ query: String) -> [CommandBarResult] {
        CommandBarResults.build(query: query, apps: [], usage: [:], running: [], profiles: [work, play])
    }

    /// `profile ` with nothing after the space is not a mode yet (the parser trims it), so the empty
    /// argument is exercised on the row builder directly.
    func testEmptyArgumentListsEveryProfileByName() {
        XCTAssertEqual(CommandBarResults.profileRows("", [work, play]), [.profile(play), .profile(work)])
    }

    func testArgumentFiltersByCaseInsensitiveContains() {
        XCTAssertEqual(rows("profile WOR"), [.profile(work)])
        XCTAssertTrue(rows("profile zzz").isEmpty)
    }

    func testSaveOffersTheTypedName() {
        XCTAssertEqual(rows("profile save Evening"), [.saveProfile("Evening")])
        XCTAssertEqual(rows("profile SAVE  Evening  "), [.saveProfile("Evening")])
    }

    func testSaveWithoutNameOffersNothing() {
        XCTAssertTrue(rows("profile save").isEmpty)
        XCTAssertTrue(rows("profile save   ").isEmpty)
    }

    func testAProfileNamedLikeSaveStillMatchesByPrefixOnly() {
        let saver = BarProfileSummary(id: "3", name: "Saver", appCount: 1)
        let out = CommandBarResults.build(query: "profile sav", apps: [], usage: [:], running: [], profiles: [saver])
        XCTAssertEqual(out, [.profile(saver)])
    }

    func testRowIdsAreDistinct() {
        XCTAssertNotEqual(CommandBarResult.profile(work).id, CommandBarResult.saveProfile("Work").id)
    }
}
