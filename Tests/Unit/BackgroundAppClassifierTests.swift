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
