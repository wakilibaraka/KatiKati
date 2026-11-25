import XCTest
@testable import KatiKati

final class BackgroundAppClassifierTests: XCTestCase {
    private typealias P = BackgroundAppClassifier.Process
    private func proc(_ id: String, _ policy: BackgroundAppClassifier.Policy = .regular, windows: Bool = true, hidden: Bool = false) -> P {
        P(bundleID: id, policy: policy, hasWindows: windows, isHidden: hidden)
    }
    private let ctx = BackgroundAppClassifier.Context(selfBundleID: "me")

    func testMenuBarAppsAndWindowlessOrHiddenRegularAppsAreBackground() {
        XCTAssertTrue(BackgroundAppClassifier.isBackground(proc("com.x.menubar", .accessory, windows: false), ctx))
        XCTAssertTrue(BackgroundAppClassifier.isBackground(proc("com.x.closed", windows: false), ctx))
        XCTAssertTrue(BackgroundAppClassifier.isBackground(proc("com.x.hidden", hidden: true), ctx))
        XCTAssertFalse(BackgroundAppClassifier.isBackground(proc("com.x.normal"), ctx), "a real window means foreground")
        XCTAssertFalse(BackgroundAppClassifier.isBackground(proc("com.x.agent", .prohibited, windows: false), ctx))
    }

    func testExclusionsSelfFinderKeptMessagingStashedIgnored() {
        var c = ctx
        c.keptIDs = ["k"]; c.messagingIDs = ["m"]; c.stashedIDs = ["s"]; c.ignoredIDs = ["i"]
        for id in ["me", "com.apple.finder", "k", "m", "s", "i", ""] {
            XCTAssertFalse(BackgroundAppClassifier.isBackground(proc(id, .accessory, windows: false), c), id)
        }
    }

    func testAppleHelpersNeedTheSetting() {
        let helper = proc("com.apple.helper", .accessory, windows: false)
        XCTAssertFalse(BackgroundAppClassifier.isBackground(helper, ctx))
        var c = ctx; c.showSystemHelpers = true
        XCTAssertTrue(BackgroundAppClassifier.isBackground(helper, c))
        XCTAssertTrue(BackgroundAppClassifier.isBackground(proc("com.apple.Safari", windows: false), ctx), "regular Apple apps are not helpers")
    }

    func testListIsDedupedAndSortedCaseInsensitively() {
        let out = BackgroundAppClassifier.background([proc("b.app", windows: false), proc("A.app", windows: false), proc("b.app", windows: false)], ctx)
        XCTAssertEqual(out, ["A.app", "b.app"])
    }
}

extension BackgroundAppClassifierTests {
    func testHelperDetectionAndExclusion() {
        XCTAssertTrue(BackgroundAppClassifier.looksLikeHelper(bundlePath: "/Applications/Claude.app/Contents/Frameworks/Claude Helper.app", name: "Claude Helper"))
        XCTAssertTrue(BackgroundAppClassifier.looksLikeHelper(bundlePath: "/Applications/Foo.app", name: "Updater"))
        XCTAssertFalse(BackgroundAppClassifier.looksLikeHelper(bundlePath: "/Applications/RClick.app", name: "RClick"))
        var helper = BackgroundAppClassifier.Process(bundleID: "x.helper", policy: .accessory, hasWindows: false, isHidden: false)
        helper.isHelper = true
        XCTAssertFalse(BackgroundAppClassifier.isBackground(helper, BackgroundAppClassifier.Context()))
        var shown = BackgroundAppClassifier.Context(); shown.showSystemHelpers = true
        XCTAssertTrue(BackgroundAppClassifier.isBackground(helper, shown))
    }
}

// MARK: - Control Centre's Background Apps deck

extension BackgroundAppClassifierTests {
    private func item(_ id: String, _ name: String,
                      _ policy: BackgroundAppClassifier.Policy = .regular,
                      helper: Bool = false) -> BackgroundActivity.Item {
        BackgroundActivity.Item(bundleID: id, name: name, policy: policy, isHelper: helper)
    }

    /// OS machinery must never read as the user's own activity: prohibited processes and Apple's
    /// accessory agents are filtered; third-party menu-bar apps and regular apps survive.
    func testBackgroundActivityDropsOSMachineryButKeepsUserApps() {
        let machinery = [
            item("com.apple.loginwindow", "loginwindow", .prohibited),
            item("com.apple.WindowManager", "WindowManager", .accessory),
            item("com.apple.MenuBarAgent", "MenuBarAgent", .accessory),
            item("com.apple.Wallpaper", "Wallpaper", .accessory),
        ]
        for entry in machinery {
            XCTAssertFalse(BackgroundActivity.belongs(entry), "\(entry.name) is OS machinery")
        }
        let apps = [
            item("com.google.Chrome", "Google Chrome"),
            item("com.apple.Notes", "Notes"),
            item("com.raycast.macos", "Raycast", .accessory),
        ]
        for app in apps {
            XCTAssertTrue(BackgroundActivity.belongs(app), "\(app.name) is a person's app")
        }
        XCTAssertFalse(BackgroundActivity.belongs(item("com.apple.finder", "Finder")), "Finder is the desktop, not background activity")
        XCTAssertFalse(BackgroundActivity.belongs(item("com.x.worker", "Worker", .regular, helper: true)))
        XCTAssertFalse(BackgroundActivity.belongs(item("com.google.Chrome.helper", "Google Chrome Helper (Aperitif)")))
        XCTAssertFalse(BackgroundActivity.belongs(item("", "Nameless")))
    }

    /// The deck is a glance: filtered, alphabetical, capped, and never contains duplicates.
    func testVisibleListIsFilteredSortedAndCapped() {
        var input = (1...12).map { item("com.x.app\($0)", "App \(String(format: "%02d", $0))") }
        input.append(item("com.apple.WindowManager", "WindowManager", .accessory))
        input.append(item("com.x.helper", "Helper", .regular, helper: true))
        let visible = BackgroundActivity.visible(input)
        XCTAssertEqual(visible.count, 10)
        XCTAssertEqual(visible.first?.name, "App 01")
        XCTAssertEqual(visible.last?.name, "App 10")
        XCTAssertFalse(visible.contains { $0.name == "WindowManager" })
        XCTAssertEqual(Set(visible.map(\.bundleID)).count, visible.count)
    }

    /// Every row without a resolvable bundle still has a typographic mark to carry.
    func testMonogramFallbackIsAlwaysLegible() {
        XCTAssertEqual(BackgroundActivity.monogram(for: "Google Chrome", bundleID: "com.google.Chrome"), "GC")
        XCTAssertEqual(BackgroundActivity.monogram(for: "YouTube Music", bundleID: "com.google.YouTubeMusic"), "YM")
        XCTAssertEqual(BackgroundActivity.monogram(for: "Freebuff", bundleID: "com.freebuff.app"), "F")
        XCTAssertEqual(BackgroundActivity.monogram(for: "menu-bar-app", bundleID: "com.x.menubar"), "MB")
        XCTAssertEqual(BackgroundActivity.monogram(for: "", bundleID: "com.x.notes"), "N")
        XCTAssertEqual(BackgroundActivity.monogram(for: "", bundleID: ""), "?")
    }
}
