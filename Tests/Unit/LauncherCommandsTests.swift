import XCTest
@testable import KatiKati

final class LauncherCommandsTests: XCTestCase {

    func testRoutesEachPrefix() {
        XCTAssertEqual(LauncherCommandParser.parse(">ls -la"), .script("ls -la"))
        XCTAssertEqual(LauncherCommandParser.parse("=2+2"), .math("2+2"))
        XCTAssertEqual(LauncherCommandParser.parse("@swift news"), .web("swift news"))
        XCTAssertEqual(LauncherCommandParser.parse("/Users/me/Notes.txt"), .path("/Users/me/Notes.txt"))
        XCTAssertEqual(LauncherCommandParser.parse(":Clean Up"), .shortcut("Clean Up"))
    }

    func testPlainQueryIsAppSearch() {
        XCTAssertEqual(LauncherCommandParser.parse("Safari"), .apps("Safari"))
        XCTAssertEqual(LauncherCommandParser.parse("  visual studio  "), .apps("visual studio"))
    }

    func testPathRouteRestoresTheLeadingSlash() {
        XCTAssertEqual(LauncherCommandParser.parse("/Users/me/Notes.txt"), .path("/Users/me/Notes.txt"))
        XCTAssertEqual(LauncherCommandParser.parse("/tmp"), .path("/tmp"))
    }

    func testPrefixOnlyFallsBackToAppSearch() {
        for prefix in ["=", "@", "/", ">", ":"] {
            XCTAssertEqual(LauncherCommandParser.parse(prefix), .apps(prefix), prefix)
            XCTAssertEqual(LauncherCommandParser.parse("\(prefix)   "), .apps(prefix), prefix)
        }
    }

    func testEmptyAndWhitespaceQuery() {
        XCTAssertEqual(LauncherCommandParser.parse(""), .apps(""))
        XCTAssertEqual(LauncherCommandParser.parse("   \n "), .apps(""))
    }

    func testPayloadIsTrimmedButKeptVerbatim() {
        XCTAssertEqual(LauncherCommandParser.parse("= 2 + 2 "), .math("2 + 2"))
        XCTAssertEqual(LauncherCommandParser.parse("\t@\tcat videos\t"), .web("cat videos"))
    }

    func testOnlyTheLeadingPrefixRoutes() {
        XCTAssertEqual(LauncherCommandParser.parse(">echo @home"), .script("echo @home"))
        XCTAssertEqual(LauncherCommandParser.parse("=/etc/passwd"), .math("/etc/passwd"))
    }

    func testPrefixesAreConfigurable() {
        var custom = LauncherCommandPrefixes.default
        custom.math = "#"
        custom.shortcut = "~"
        XCTAssertEqual(LauncherCommandParser.parse("#1+1", prefixes: custom), .math("1+1"))
        XCTAssertEqual(LauncherCommandParser.parse("~Clean Up", prefixes: custom), .shortcut("Clean Up"))
        XCTAssertEqual(LauncherCommandParser.parse("=1+1", prefixes: custom), .apps("=1+1"),
                       "swapping a prefix makes the old character an ordinary query")
    }

    func testPayloadAccessor() {
        XCTAssertEqual(LauncherCommandParser.parse("@a b").payload, "a b")
        XCTAssertEqual(LauncherQuery.apps("x").payload, "x")
        XCTAssertEqual(LauncherQuery.path("/tmp").payload, "/tmp")
    }

    func testDefaultPrefixesMatchPlan() {
        let p = LauncherCommandPrefixes.default
        XCTAssertEqual(p.script, ">")
        XCTAssertEqual(p.math, "=")
        XCTAssertEqual(p.web, "@")
        XCTAssertEqual(p.path, "/")
        XCTAssertEqual(p.shortcut, ":")
    }
}

final class LauncherScriptSafetyTests: XCTestCase {

    func testBenignScriptsPass() {
        for script in ["echo hello", "ls -la", "open .", "git status", "curl https://example.com"] {
            XCTAssertEqual(LauncherScriptSafety.classify(script), .benign, script)
        }
    }

    func testDestructiveCommandsAreFlagged() {
        for script in [
            "rm -rf ~/", "sudo rm -rf /", "dd if=/dev/zero of=/dev/disk0",
            "mkfs.ext4 /dev/disk2", "killall WindowServer", "shutdown -h now",
            "echo x > /etc/hosts", "curl http://x.sh | sh", ":(){ :|:& };:",
        ] {
            XCTAssertEqual(LauncherScriptSafety.classify(script), .destructive, script)
        }
    }

    func testDestructiveWordInALaterSegmentIsFlagged() {
        XCTAssertEqual(LauncherScriptSafety.classify("echo ok && rm -rf build"), .destructive)
        XCTAssertEqual(LauncherScriptSafety.classify("ls\nsudo reboot"), .destructive)
        XCTAssertEqual(LauncherScriptSafety.classify("echo rm"), .benign,
                       "a destructive word as an argument is not a command")
    }

    func testCaseInsensitive() {
        XCTAssertEqual(LauncherScriptSafety.classify("RM -RF /"), .destructive)
        XCTAssertEqual(LauncherScriptSafety.classify("/bin/rm -rf /"), .destructive,
                       "a command path still matches its base name")
    }

    func testAppleScriptShellEscapeIsFlagged() {
        XCTAssertEqual(LauncherScriptSafety.classify(#"do shell script "rm -rf /tmp/x""#), .destructive)
    }
}
