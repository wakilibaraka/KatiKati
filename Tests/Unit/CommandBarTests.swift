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

    func testEmptyQueryShowsMacEssentials() {
        let rows = CommandBarResults.build(query: "", apps: [], usage: [:], running: [])
        XCTAssertEqual(Array(rows.prefix(CommandBarLearning.essentials.count)),
                       CommandBarLearning.essentials.map(CommandBarResult.action))
    }

    func testEmptyQuerySuggestsFrequentlyLaunchedApps() {
        let safari = app("s", "Safari"), notes = app("n", "Notes"), unused = app("u", "Unused")
        let now = Date(timeIntervalSince1970: 1_000_000)
        let usage = ["s": LauncherUsage(launches: 2, lastLaunched: now),
                     "n": LauncherUsage(launches: 4, lastLaunched: now)]
        XCTAssertEqual(CommandBarResults.build(query: "", apps: [safari, notes, unused], usage: usage, running: []),
                       CommandBarLearning.essentials.map(CommandBarResult.action) + [.app(notes), .app(safari)])
    }

    func testPinnedAppsLeadAndHiddenAppsStayOut() {
        let safari = app("s", "Safari"), notes = app("n", "Notes")
        let learning = CommandBarLearning(pinnedIDs: ["n"], hiddenIDs: ["s"], aliases: [:])
        let rows = CommandBarResults.build(query: "", apps: [safari, notes], usage: [:], running: [], learning: learning)
        XCTAssertEqual(rows.first, .app(notes))
        XCTAssertFalse(rows.contains(.app(safari)))
    }

    func testAliasResolvesBeforeSearch() {
        let learning = CommandBarLearning(pinnedIDs: [], hiddenIDs: [], aliases: ["br": "Safari"])
        let rows = CommandBarResults.build(query: "br", apps: [app("s", "Safari")], usage: [:], running: [], learning: learning)
        XCTAssertEqual(rows.first, .app(app("s", "Safari")))
    }

    func testFrecencyDecaysWithAge() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let recent = LauncherUsage(launches: 2, lastLaunched: now)
        let old = LauncherUsage(launches: 2, lastLaunched: now.addingTimeInterval(-14 * 86_400))
        XCTAssertGreaterThan(CommandBarFrecency.score(recent, now: now),
                             CommandBarFrecency.score(old, now: now))
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
        XCTAssertEqual(CommandGenerator.match("wifipw"), .wifiPassword)
        XCTAssertEqual(CommandGenerator.match("  WIFIPW "), .wifiPassword)
        XCTAssertNil(CommandGenerator.match("wifi"))
        XCTAssertTrue(CommandGenerator.formatJSON.isSystemBacked)
        XCTAssertFalse(CommandGenerator.uuid.isSystemBacked)
        XCTAssertFalse(CommandGenerator.matching("pass").isEmpty)
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

        // Space delimiter allows empty argument to activate mode
        XCTAssertEqual(CommandKeyword.parse("clip "), .mode(.clipboard, ""))
        XCTAssertEqual(CommandKeyword.parse("c "), .mode(.clipboard, ""))
        XCTAssertEqual(CommandKeyword.parse("emoji "), .mode(.emoji, ""))
        XCTAssertEqual(CommandKeyword.parse("emo "), .mode(.emoji, ""))
        XCTAssertEqual(CommandKeyword.parse("bm "), .mode(.bookmark, ""))
        XCTAssertEqual(CommandKeyword.parse("kill "), .mode(.kill, ""))
        XCTAssertEqual(CommandKeyword.parse("fq "), .mode(.forceQuit, ""))
        XCTAssertEqual(CommandKeyword.parse("m "), .mode(.menu, ""))
        XCTAssertEqual(CommandKeyword.parse("profile "), .mode(.profile, ""))
        XCTAssertEqual(CommandKeyword.parse("bs git"), .mode(.brewSearch, "git"))
    }

    func testWindowManagementMacros() {
        XCTAssertEqual(CommandKeyword.parse("left"), .macro(.snapLeft))
        XCTAssertEqual(CommandKeyword.parse("maximize"), .macro(.snapMaximize))
        XCTAssertEqual(BarMacro.snapLeft.snapPosition, .leftHalf)
        XCTAssertEqual(BarMacro.snapMaximize.snapPosition, .maximize)
        XCTAssertFalse(BarMacro.matching("snap").isEmpty)
        XCTAssertEqual(BarMacro.snapLeft.title, "Left Half")
        XCTAssertEqual(BarMacro.snapLeft.subtitle, "Snap Frontmost Window")
    }

    func testGuardedInlineMath() {
        XCTAssertEqual(LauncherAnswers.inlineMathAnswer(for: "24 * 7"), .math(expression: "24 * 7", value: "168"))
        XCTAssertEqual(LauncherAnswers.inlineMathAnswer(for: "100 / 4"), .math(expression: "100 / 4", value: "25"))
        XCTAssertNil(LauncherAnswers.inlineMathAnswer(for: "claude-3-5-sonnet"))
        XCTAssertNil(LauncherAnswers.inlineMathAnswer(for: "utf-8"))
        XCTAssertNil(LauncherAnswers.inlineMathAnswer(for: "gpt-4o-mini"))
        XCTAssertNil(LauncherAnswers.inlineMathAnswer(for: "safari"))
    }

    func testFallbackRowsOnNoMatch() {
        let rows = CommandBarResults.build(query: "xyznonexistent", apps: [], usage: [:], running: [])
        XCTAssertEqual(rows, [
            .answer(.web(query: "xyznonexistent")),
            .searchFilesFallback("xyznonexistent"),
            .askAI("xyznonexistent")
        ])
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

final class FileIndexTests: XCTestCase {
    func testSearchNarrowsByTerms() {
        var index = FileIndex()
        index.rebuild([
            .init(path: "/a/Report.pdf", name: "Report.pdf", isDirectory: false),
            .init(path: "/a/photo.png", name: "photo.png", isDirectory: false),
            .init(path: "/a/Project", name: "Project", isDirectory: true),
        ])
        XCTAssertEqual(index.search(["rep"]).map(\.name), ["Report.pdf"])
        XCTAssertEqual(index.search(["pro", "ject"]).map(\.name), ["Project"])
        XCTAssertTrue(index.search([]).isEmpty)
        XCTAssertEqual(index.count, 3)
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

final class CommandBarResultIdentityTests: XCTestCase {
    func testStableIDConsistency() {
        let app = LauncherApp(bundleID: "com.apple.Safari", name: "Safari", path: "/Applications/Safari.app", installedAt: .distantPast, category: "")
        let resApp = CommandBarResult.app(app)
        XCTAssertEqual(resApp.id, "app:com.apple.Safari:/Applications/Safari.app")

        let math = CommandBarResult.answer(.math(expression: "2+2", value: "4"))
        XCTAssertEqual(math.id, "answer:math:2+2=4")

        let web = CommandBarResult.answer(.web(query: "swift news"))
        XCTAssertEqual(web.id, "answer:web:swift news")

        let proc = CommandBarResult.process(ProcessEntry(pid: 1234, name: "zsh", path: "/bin/zsh"))
        XCTAssertEqual(proc.id, "process:1234:zsh")

        let file = CommandBarResult.file(FileEntry(path: "/tmp/doc.pdf", name: "doc.pdf"))
        XCTAssertEqual(file.id, "file:/tmp/doc.pdf")

        let quit = CommandBarResult.quit(RunningAppRef(bundleID: "com.apple.Safari", name: "Safari", pid: 999, path: "/Applications/Safari.app"))
        XCTAssertEqual(quit.id, "quit:com.apple.Safari:999")

        let forceQuit = CommandBarResult.forceQuit(RunningAppRef(bundleID: "com.apple.Safari", name: "Safari", pid: 999, path: "/Applications/Safari.app"))
        XCTAssertEqual(forceQuit.id, "forceQuit:com.apple.Safari:999")

        let action = CommandBarResult.action(.emptyTrash)
        XCTAssertEqual(action.id, "action:emptytrash")

        let bookmark = CommandBarResult.bookmark(Bookmark(title: "Apple", url: "https://apple.com"))
        XCTAssertEqual(bookmark.id, "bookmark:Apple:https://apple.com")

        let clip = CommandBarResult.clip(ClipEntry(id: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!, text: "hello"))
        XCTAssertEqual(clip.id, "clip:E621E1F8-C36C-495A-93FC-0C247A3E6E5F")

        let trash = CommandBarResult.trash(.empty)
        XCTAssertEqual(trash.id, "trash:empty")

        let emoji = CommandBarResult.emoji(EmojiEntry(char: "🎉", name: "party"))
        XCTAssertEqual(emoji.id, "emoji:🎉:party")

        let event = CommandBarResult.event(EventEntry(id: "cal-123", title: "Meeting", start: .distantPast, allDay: false))
        XCTAssertEqual(event.id, "event:cal-123")

        let gen = CommandBarResult.generator(.uuid, value: "1234")
        XCTAssertEqual(gen.id, "generator:uuid:1234")

        let custom = CommandBarResult.custom(CustomCommand(name: "GitHub", target: "https://github.com", kind: .link))
        XCTAssertEqual(custom.id, "custom:GitHub:https://github.com")

        let script = CommandBarResult.script("display dialog \"hi\"")
        XCTAssertEqual(script.id, "script:display dialog \"hi\"")

        let shortcut = CommandBarResult.shortcut("My Action")
        XCTAssertEqual(shortcut.id, "shortcut:My Action")

        let path = CommandBarResult.path("/tmp/folder")
        XCTAssertEqual(path.id, "path:/tmp/folder")

        let searchFallback = CommandBarResult.searchFilesFallback("term")
        XCTAssertEqual(searchFallback.id, "fallback:files:term")

        let askAI = CommandBarResult.askAI("term")
        XCTAssertEqual(askAI.id, "fallback:ai:term")
    }

    /// ⌘Space is Spotlight's and ⌃Space switches input sources. Registering them succeeds, but macOS
    /// consumes the key before the app sees it, so the action never fires; no default may use either.
    func testDefaultShortcutChordsAreNotOwnedByMacOS() {
        XCTAssertEqual(ShortcutAction.commandBar.defaultTrigger, .chord(.optionSpace))
        for action in ShortcutAction.allCases {
            guard case let .chord(chord) = action.defaultTrigger else { continue }
            XCTAssertFalse(chord.isReservedBySystem,
                           "\(action.rawValue) defaults to \(chord.glyphs), a shortcut macOS already owns")
        }
    }
}

// MARK: - Raycast ⌘K Action Tests (Slice 1.2)

final class CommandBarActionResolverTests: XCTestCase {
    func testAppActionsIncludeOpenRevealAndUninstall() {
        let app = LauncherApp(bundleID: "com.example.app", name: "Example", path: "/Applications/Example.app", installedAt: .distantPast)
        let actions = CommandBarActionResolver.actions(for: .app(app))
        XCTAssertEqual(actions.map(\.kind), [.open, .revealInFinder, .copyPath, .copyBundleID, .uninstallApp, .deleteAppData])
        XCTAssertTrue(actions.contains { $0.kind == .uninstallApp && $0.isDestructive })
    }

    func testFileActionsIncludeQuickLookAndTrash() {
        let file = FileEntry(path: "/Users/test/doc.pdf", name: "doc.pdf")
        let actions = CommandBarActionResolver.actions(for: .file(file))
        XCTAssertEqual(actions.map(\.kind), [.open, .quickLook, .revealInFinder, .copyPath, .moveToTrash])
        XCTAssertEqual(actions.first(where: { $0.kind == .quickLook })?.shortcutHint, "⌘Y")
    }

    func testClipActionsIncludePasteAndCopy() {
        let clip = ClipEntry(text: "Hello World")
        let actions = CommandBarActionResolver.actions(for: .clip(clip))
        XCTAssertEqual(actions.map(\.kind), [.copyValue, .pasteDirectly, .deleteEntry])
    }
}

// MARK: - SuperCmd Token & Section Store Tests (SLICE SC-1)

final class CommandBarSuperCmdTests: XCTestCase {
    func testQueryParserExtractsExplicitScopesAndArguments() {
        let g = CommandBarQueryParser.parse("g swift concurrency")
        XCTAssertEqual(g.token?.scope, .googleSearch)
        XCTAssertEqual(g.token?.title, "Search Google")
        XCTAssertEqual(g.token?.badgeLabel, "Query")
        XCTAssertEqual(g.remainingQuery, "swift concurrency")

        let calc = CommandBarQueryParser.parse("calc 24 * 7")
        XCTAssertEqual(calc.token?.scope, .calculator)
        XCTAssertEqual(calc.token?.badgeLabel, "Expression")
        XCTAssertEqual(calc.remainingQuery, "24 * 7")

        let app = CommandBarQueryParser.parse("app safari")
        XCTAssertEqual(app.token?.scope, .applications)
        XCTAssertEqual(app.remainingQuery, "safari")

        let file = CommandBarQueryParser.parse("file report.pdf")
        XCTAssertEqual(file.token?.scope, .files)
        XCTAssertEqual(file.remainingQuery, "report.pdf")
    }

    func testQueryParserHandlesQuicklinksEmptyArgsAndPlainQueries() {
        let gh = Quicklink(name: "gh", template: "https://github.com/search?q={query}")
        let quick = CommandBarQueryParser.parse("gh async", quicklinks: [gh])
        XCTAssertEqual(quick.token?.scope, .quicklink(gh))
        XCTAssertEqual(quick.remainingQuery, "async")

        let emptyScope = CommandBarQueryParser.parse("g ")
        XCTAssertEqual(emptyScope.token?.scope, .googleSearch)
        XCTAssertEqual(emptyScope.remainingQuery, "")

        let plain = CommandBarQueryParser.parse("safari")
        XCTAssertNil(plain.token)
        XCTAssertEqual(plain.remainingQuery, "safari")
    }

    func testBuildRoutesGoogleAndCalcScopes() {
        XCTAssertEqual(
            CommandBarResults.build(query: "g swift", apps: [], usage: [:], running: []),
            [.answer(.web(query: "swift"))]
        )
        XCTAssertEqual(
            CommandBarResults.build(query: "calc 6 * 7", apps: [], usage: [:], running: []),
            [.answer(.math(expression: "6 * 7", value: "42"))]
        )
        XCTAssertTrue(CommandBarResults.build(query: "g ", apps: [], usage: [:], running: []).isEmpty)
        XCTAssertTrue(CommandBarResults.build(query: "calc ", apps: [], usage: [:], running: []).isEmpty)
    }

    func testSectionStoreGroupsPriorityOrderAndAssignsMetadataBadges() {
        let safari = LauncherApp(bundleID: "com.apple.Safari", name: "Safari", path: "/Applications/Safari.app", installedAt: .distantPast)
        let runningSafari = RunningAppRef(bundleID: "com.apple.Safari", name: "Safari", pid: 10, path: "/Applications/Safari.app")
        let link = Quicklink(name: "Search Google", template: "https://google.com/search?q={query}")
        let doc = FileEntry(path: "/tmp/notes.md", name: "notes.md")

        let input: [CommandBarResult] = [
            .file(doc),
            .app(safari),
            .quit(runningSafari),
            .quicklink(link, argument: "swift"),
            .action(.darkMode)
        ]

        let sections = CommandBarSectionStore.group(input)
        XCTAssertEqual(sections.map(\.kind), [.suggestions, .commands, .applications, .files])
        XCTAssertEqual(sections[0].items.map(\.metadata.badge), [.quicklink])
        XCTAssertEqual(sections[1].items.map(\.metadata.badge), [.command, .command])
        XCTAssertEqual(sections[2].items.map(\.metadata.badge), [.application])
        XCTAssertEqual(sections[3].items.map(\.metadata.badge), [.file])

        let flatIndices = sections.flatMap { $0.items.map(\.flatIndex) }
        XCTAssertEqual(flatIndices, [0, 1, 2, 3, 4])
    }

    func testSectionStoreTreatsEmptyQueryAppsAsSuggestionsAndOmitsEmptySections() {
        let safari = LauncherApp(bundleID: "com.apple.Safari", name: "Safari", path: "/Applications/Safari.app", installedAt: .distantPast)
        let sections = CommandBarSectionStore.group([.app(safari)], isEmptyQuery: true)
        XCTAssertEqual(sections.map(\.kind), [.suggestions])
        XCTAssertEqual(sections.first?.items.first?.metadata.badge, .application)
    }
}


