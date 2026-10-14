import XCTest
@testable import KatiKati

final class CommandBarTests: XCTestCase {

    private func app(_ id: String, _ name: String) -> LauncherApp {
        LauncherApp(bundleID: id, name: name, path: "/Applications/\(name).app", installedAt: Date(timeIntervalSince1970: 0))
    }
    private func running(_ id: String, _ name: String) -> RunningAppRef {
        RunningAppRef(bundleID: id, name: name, pid: 42, path: "/Applications/\(name).app")
    }

    func testMathRouteYieldsOnlyTheAnswer() {
        let rows = CommandBarResults.build(query: "=2+2", apps: [app("s", "Safari")], usage: [:], running: [])
        XCTAssertEqual(rows, [.answer(.math(expression: "2+2", value: "4"))])
    }

    func testWebRouteYieldsOnlyTheSearchAnswer() {
        let rows = CommandBarResults.build(query: "@swift news", apps: [], usage: [:], running: [])
        XCTAssertEqual(rows, [.answer(.web(query: "swift news"))])
    }

    func testAppMatchComesBeforeItsQuitRow() {
        let rows = CommandBarResults.build(query: "safari",
                                           apps: [app("com.apple.Safari", "Safari")],
                                           usage: [:],
                                           running: [running("com.apple.Safari", "Safari")])
        XCTAssertEqual(rows, [.app(app("com.apple.Safari", "Safari")),
                              .quit(running("com.apple.Safari", "Safari"))])
    }

    func testWordRoutesProduceTheirRows() {
        XCTAssertEqual(CommandBarResults.build(query: ">ls -la", apps: [], usage: [:], running: []), [.script("ls -la")])
        XCTAssertEqual(CommandBarResults.build(query: ":Clean Up", apps: [], usage: [:], running: []), [.shortcut("Clean Up")])
        XCTAssertEqual(CommandBarResults.build(query: "/tmp/x", apps: [], usage: [:], running: []), [.path("/tmp/x")])
    }

    func testNotRunningAppHasNoQuitRow() {
        let rows = CommandBarResults.build(query: "notes", apps: [app("n", "Notes")], usage: [:], running: [])
        XCTAssertEqual(rows, [.app(app("n", "Notes"))])
    }

    func testEmptyQueryYieldsNothing() {
        XCTAssertTrue(CommandBarResults.build(query: "", apps: [app("s", "Safari")], usage: [:], running: []).isEmpty)
        XCTAssertTrue(CommandBarResults.build(query: "   ", apps: [], usage: [:], running: []).isEmpty)
    }

    func testQuitRowsAreBestMatchFirst() {
        let canary = RunningAppRef(bundleID: "a", name: "Chrome Canary", pid: 1, path: "/a.app")
        let chrome = RunningAppRef(bundleID: "b", name: "Chrome", pid: 2, path: "/b.app")
        let rows = CommandBarResults.build(query: "chrome", apps: [], usage: [:], running: [canary, chrome])
        XCTAssertEqual(rows.first, .quit(chrome))
    }
}

final class CommandGeneratorTests: XCTestCase {
    private struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    func testMatch() {
        XCTAssertEqual(CommandGenerator.match("uuid"), .uuid)
        XCTAssertEqual(CommandGenerator.match("UUID"), .uuid)
        XCTAssertEqual(CommandGenerator.match("nanoid"), .nanoID)
        XCTAssertEqual(CommandGenerator.match("lorem"), .loremIpsum)
        XCTAssertNil(CommandGenerator.match("uu"), "partial words do not match")
        XCTAssertNil(CommandGenerator.match(""))
        XCTAssertNil(CommandGenerator.match("zzz"))
    }

    func testNanoIDLengthAndCharset() {
        var rng = SeededRNG(state: 1)
        let id = CommandGenerator.nanoID.value(using: &rng)
        XCTAssertEqual(id.count, CommandGenerator.nanoIDLength)
        XCTAssertTrue(id.allSatisfy { "_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ".contains($0) })
    }

    func testLoremIsASentence() {
        var rng = SeededRNG(state: 7)
        let text = CommandGenerator.loremIpsum.value(using: &rng)
        XCTAssertFalse(text.isEmpty)
        XCTAssertTrue(text.hasSuffix("."))
    }

    func testBuildPrependsGeneratorRow() {
        let rows = CommandBarResults.build(query: "uuid", apps: [], usage: [:], running: [], generate: { _ in "fixed" })
        guard case .generator(.uuid, "fixed") = rows.first else { return XCTFail("expected generator row, got \(rows)") }
    }

    func testProcessRouteListsMatchingProcesses() {
        let processes = [ProcessEntry(pid: 1, name: "Safari", path: "/Applications/Safari.app"),
                         ProcessEntry(pid: 2, name: "Finder", path: "/System/Finder")]
        let rows = CommandBarResults.build(query: "!saf", apps: [], usage: [:], running: [], processes: processes)
        guard case .process(let entry) = rows.first else { return XCTFail("expected process row, got \(rows)") }
        XCTAssertEqual(entry.name, "Safari")
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(CommandBarResults.build(query: "!", apps: [], usage: [:], running: [], processes: processes).isEmpty,
                      "a bare ! shows nothing until there is a filter")
    }

    func testSystemKeywordsMatch() {
        XCTAssertEqual(CommandGenerator.match("json"), .formatJSON)
        XCTAssertEqual(CommandGenerator.match("ip"), .ipAddress)
        XCTAssertEqual(CommandGenerator.match("wifi"), .wifiPassword)
        XCTAssertTrue(CommandGenerator.formatJSON.isSystemBacked)
        XCTAssertFalse(CommandGenerator.uuid.isSystemBacked)
    }

    func testPrettyJSON() {
        let pretty = JSONPrettyPrinter.pretty(#"{"a":1,"b":[2,3]}"#)
        XCTAssertNotNil(pretty)
        XCTAssertTrue(pretty?.contains("\n") == true)
        XCTAssertNil(JSONPrettyPrinter.pretty("not json"))
    }
}

final class CustomCommandTests: XCTestCase {
    func testParsesNameAndTargetPerLine() {
        let commands = CustomCommand.parse("Open GitHub = https://github.com\n\nNotepad = open -a Notes")
        XCTAssertEqual(commands.count, 2)
        XCTAssertEqual(commands[0], CustomCommand(name: "Open GitHub", target: "https://github.com", kind: .link))
        XCTAssertEqual(commands[1].kind, .command)
    }

    func testLinkDetection() {
        XCTAssertEqual(CustomCommand.kind(of: "https://a.com"), .link)
        XCTAssertEqual(CustomCommand.kind(of: "http://a.com"), .link)
        XCTAssertEqual(CustomCommand.kind(of: "open -a Notes"), .command)
    }

    func testMatchingIsCaseInsensitivePrefix() {
        let commands = CustomCommand.parse("Deploy = deploy.sh\nDocs = https://docs.example")
        XCTAssertEqual(CustomCommand.matching("dep", in: commands).map(\.name), ["Deploy"])
        XCTAssertEqual(CustomCommand.matching("DOCS", in: commands).map(\.name), ["Docs"])
        XCTAssertTrue(CustomCommand.matching("", in: commands).isEmpty)
    }

    func testSerializeRoundTrips() {
        let commands = CustomCommand.parse("A = https://a\nB = b")
        XCTAssertEqual(CustomCommand.parse(CustomCommand.serialize(commands)), commands)
    }
}

final class CommandKeywordTests: XCTestCase {
    func testMacroParse() {
        XCTAssertEqual(CommandKeyword.parse("ocr"), .macro(.ocr))
        XCTAssertEqual(CommandKeyword.parse("LOCK"), .macro(.lock))
        XCTAssertEqual(CommandKeyword.parse("cs"), .macro(.shortcutsApp))
        XCTAssertEqual(CommandKeyword.parse("emptytrash"), .macro(.emptyTrash))
        XCTAssertNil(CommandKeyword.parse("trash"), "trash is the action list, not a macro")
    }

    func testModeParse() {
        XCTAssertEqual(CommandKeyword.parse("fq chrome"), .mode(.forceQuit, "chrome"))
        XCTAssertEqual(CommandKeyword.parse("kp saf"), .mode(.killProcess, "saf"))
        XCTAssertEqual(CommandKeyword.parse("sc My Shortcut"), .mode(.shortcut, "My Shortcut"))
        XCTAssertNil(CommandKeyword.parse("kill"), "no trailing space → not a mode")
        XCTAssertNil(CommandKeyword.parse("hello world"))
    }

    func testMacroRow() {
        XCTAssertEqual(CommandBarResults.build(query: "ocr", apps: [], usage: [:], running: []), [.action(.ocr)])
    }

    func testForceQuitModeRows() {
        let safari = RunningAppRef(bundleID: "s", name: "Safari", pid: 1, path: "/Safari.app")
        XCTAssertEqual(CommandBarResults.build(query: "fq saf", apps: [], usage: [:], running: [safari]), [.forceQuit(safari)])
        XCTAssertEqual(CommandBarResults.build(query: "kill saf", apps: [], usage: [:], running: [safari]), [.quit(safari)])
    }

    func testClipboardModeRows() {
        let hello = ClipEntry(text: "hello world")
        let goodbye = ClipEntry(text: "goodbye")
        let rows = CommandBarResults.build(query: "clip hello", apps: [], usage: [:], running: [], clips: [hello, goodbye])
        XCTAssertEqual(rows, [.clip(hello)])
    }

    func testTrashKeywordListsOpenAndEmpty() {
        XCTAssertEqual(CommandBarResults.build(query: "trash", apps: [], usage: [:], running: []),
                       [.trash(.open), .trash(.empty)])
    }

    func testEmojiModeMatchesByName() {
        XCTAssertTrue(EmojiCatalog.matching("heart").contains { $0.char == "❤️" })
        let rows = CommandBarResults.build(query: "emoji heart", apps: [], usage: [:], running: [])
        guard case .emoji? = rows.first else { return XCTFail("expected emoji rows, got \(rows)") }
    }

    func testEventModeRows() {
        let event = EventEntry(id: "e", title: "Standup", start: Date(timeIntervalSince1970: 0), allDay: false)
        XCTAssertEqual(CommandBarResults.build(query: "ev standup", apps: [], usage: [:], running: [], events: [event]),
                       [.event(event)])
    }
}

final class FileQueryTests: XCTestCase {
    func testParseOperators() {
        let query = FileQuery.parse("report ext:pdf;docx kind:doc in:~/Docs !draft")
        XCTAssertEqual(query.terms, ["report"])
        XCTAssertEqual(query.extensions, ["pdf", "docx"])
        XCTAssertEqual(query.kinds, ["doc"])
        XCTAssertEqual(query.excluded, ["draft"])
        XCTAssertEqual(query.path, (NSHomeDirectory() as NSString).appendingPathComponent("Docs"))
    }

    func testValidityAndPredicate() {
        XCTAssertFalse(FileQuery.parse("").isValid)
        XCTAssertTrue(FileQuery.parse("report").predicate().contains("kMDItemFSName"))
        XCTAssertTrue(FileQuery.parse("cat", imageOnly: true).predicate().contains("public.image"))
    }

    func testImageModeRowsPassThroughFiles() {
        let entry = FileEntry(path: "/tmp/cat.png", name: "cat.png")
        let rows = CommandBarResults.build(query: "img cat", apps: [], usage: [:], running: [], files: [entry])
        XCTAssertEqual(rows, [.file(entry)])
    }
}

final class BookmarkImportTests: XCTestCase {
    func testChromeParse() {
        let json = #"{"roots":{"bookmark_bar":{"children":[{"name":"Swift","url":"https://swift.org"},{"children":[{"name":"Docs","url":"https://docs.example"}]}]}}}"#
        let marks = BookmarkImport.parseChrome(Data(json.utf8))
        XCTAssertEqual(Set(marks.map(\.title)), ["Swift", "Docs"])
    }

    func testSafariParse() {
        let plist: [String: Any] = ["Children": [["URLString": "https://a.com", "URIDictionary": ["title": "A"]]]]
        XCTAssertEqual(BookmarkImport.parseSafari(plist), [Bookmark(title: "A", url: "https://a.com")])
    }

    func testMatchingAndModeRow() {
        let marks = [Bookmark(title: "Swift Blog", url: "https://swift.org/blog"),
                     Bookmark(title: "News", url: "https://news.example")]
        XCTAssertEqual(BookmarkImport.matching("swift", in: marks).map(\.title), ["Swift Blog"])
        XCTAssertEqual(BookmarkImport.matching("example", in: marks).map(\.title), ["News"])
        let rows = CommandBarResults.build(query: "bm swift", apps: [], usage: [:], running: [], bookmarks: marks)
        XCTAssertEqual(rows, [.bookmark(marks[0])])
    }
}

final class SpotlightHandoffTests: XCTestCase {

    func testStepsAreOrderedAndNonEmpty() {
        let steps = SpotlightHandoff.steps()
        XCTAssertEqual(steps.first, .openKeyboard)
        XCTAssertEqual(steps.last, .testHere)
        XCTAssertEqual(steps.count, SpotlightHandoff.Step.allCases.count)
    }

    func testSettingsURLDeepLinksSystemSettings() {
        let url = URL(string: SpotlightHandoff.settingsURL)
        XCTAssertEqual(url?.scheme, "x-apple.systempreferences")
    }
}
