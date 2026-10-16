import XCTest
@testable import KatiKati

// The system Dock is given back as the user had it when KatiKati quits (and by "Restore Dock").
//
// Phase 42 reads one more thing out of the same domain: the apps the user pinned there
// (`persistent-apps`), which the bar shows as launcher chips.

final class NativeDockPinnedAppsTests: XCTestCase {
    private func tile(_ url: String, type: String = "file-tile") -> [String: Any] {
        ["tile-type": type, "tile-data": ["file-data": ["_CFURLString": url, "_CFURLStringType": 15]]]
    }

    func testDecodesDockOrderAndPercentEscapedPaths() {
        var paths: [String] = []
        let value: [[String: Any]] = [tile("file:///System/Applications/Mail.app/"),
                                     tile("file:///Applications/Google%20Chrome.app/")]
        let ids = NativeDockPinnedApps.decode(value) { url in
            paths.append(url.path)
            return url.lastPathComponent
        }
        XCTAssertEqual(paths, ["/System/Applications/Mail.app", "/Applications/Google Chrome.app"],
                       "`%20` reaches Bundle(url:) decoded")
        XCTAssertEqual(ids, ["Mail.app", "Google Chrome.app"], "Dock order kept")
    }

    func testDropsDuplicatesAndNonAppTiles() {
        let value: [[String: Any]] = [tile("file:///System/Applications/Mail.app/"),
                                     tile("file:///System/Applications/Mail.app/"),
                                     tile("file:///Users/someone/Downloads/", type: "directory-tile"),
                                     ["tile-type": "file-tile"]]     // no tile-data at all
        let ids = NativeDockPinnedApps.decode(value) { url in
            url.path.hasSuffix("Mail.app") ? "com.apple.mail" : nil
        }
        XCTAssertEqual(ids, ["com.apple.mail"])
    }

    func testUnreadablePrefsYieldNoPins() {
        XCTAssertTrue(NativeDockPinnedApps.decode(nil).isEmpty)
        XCTAssertTrue(NativeDockPinnedApps.decode("not an array").isEmpty)
        XCTAssertTrue(NativeDockPinnedApps.read(synchronize: { false }, value: { [] }).isEmpty,
                      "a failed synchronize means the cached value is not trustworthy")
        XCTAssertEqual(NativeDockPinnedApps.read(synchronize: { true },
                                                 value: { [self.tile("file:///Applications/OpenCode.app/")] },
                                                 bundleIDForURL: { _ in "dev.opencode.app" }),
                       ["dev.opencode.app"])
    }
}


@MainActor
final class NativeDockRestoreTests: XCTestCase {
    private var ran: [[String]] = []

    private func make(initial: NativeDockAutohideState?, sandboxed: Bool = false) -> NativeDockPreferencesService {
        let defaults = TestDefaults.make("com.katikati.tests.dockrestore", for: self)
        return NativeDockPreferencesService(
            sandbox: SandboxEnvironment(isSandboxed: sandboxed),
            runner: { [unowned self] exe, args in self.ran.append([exe] + args) },
            autohideReader: { initial },
            defaults: defaults)
    }

    func testRestoreCommandsForPresentAndAbsentDelay() {
        let present = NativeDockOriginal(NativeDockAutohideState(enabled: true, delay: 0.5)).restoreCommands().map { $0.arguments }
        XCTAssertEqual(present, [["write", "com.apple.dock", "autohide", "-bool", "true"],
                                 ["write", "com.apple.dock", "autohide-delay", "-float", "0.5"],
                                 ["Dock"]])
        let absent = NativeDockOriginal(NativeDockAutohideState(enabled: false, delay: nil)).restoreCommands().map { $0.arguments }
        XCTAssertEqual(absent[0], ["write", "com.apple.dock", "autohide", "-bool", "false"])
        XCTAssertEqual(absent[1], ["delete", "com.apple.dock", "autohide-delay"])
    }

    func testQuitRestoresTheStateBeforeFirstHide() throws {
        let service = make(initial: NativeDockAutohideState(enabled: false, delay: nil))
        try service.apply(delay: 999)
        XCTAssertTrue(service.hasCapturedOriginal)
        ran = []
        XCTAssertTrue(service.restoreOriginal())
        XCTAssertTrue(ran.contains(["/usr/bin/defaults", "write", "com.apple.dock", "autohide", "-bool", "false"]))
        XCTAssertTrue(ran.contains(["/usr/bin/defaults", "delete", "com.apple.dock", "autohide-delay"]))
        XCTAssertEqual(ran.last, ["/usr/bin/killall", "Dock"])
        XCTAssertFalse(service.hasCapturedOriginal)
    }

    func testSecondWriteDoesNotOverwriteTheCapturedOriginal() throws {
        let service = make(initial: NativeDockAutohideState(enabled: true, delay: 0.3))
        try service.apply(delay: 1.0)
        try service.apply(delay: 2.0)
        ran = []
        service.restoreOriginal()
        XCTAssertTrue(ran.contains(["/usr/bin/defaults", "write", "com.apple.dock", "autohide-delay", "-float", "0.3"]))
    }

    func testRestoreWithNothingCapturedDoesNothing() {
        let service = make(initial: NativeDockAutohideState(enabled: false, delay: nil))
        XCTAssertFalse(service.restoreOriginal())
        XCTAssertTrue(ran.isEmpty)
    }

    func testChoosingAlwaysVisibleClearsWhatToRestore() throws {
        let service = make(initial: NativeDockAutohideState(enabled: true, delay: 0.3))
        try service.apply(delay: 1.0)
        try service.apply(delay: AppSettingsStore.neverHideDelay)
        XCTAssertFalse(service.hasCapturedOriginal)
        ran = []
        service.reapplyDesiredIfNeeded()
        XCTAssertTrue(ran.isEmpty, "explicit always-visible must not be re-hidden on launch")
    }

    func testLaunchReHidesAfterACleanQuitButNotAfterACrash() throws {
        let service = make(initial: NativeDockAutohideState(enabled: false, delay: nil))
        try service.apply(delay: 1.0)
        service.restoreOriginal()            // clean quit
        ran = []
        service.reapplyDesiredIfNeeded()     // next launch
        XCTAssertTrue(ran.contains(["/usr/bin/defaults", "write", "com.apple.dock", "autohide", "-bool", "true"]))
        ran = []
        service.reapplyDesiredIfNeeded()     // original captured again (crash-like): leave the hidden Dock
        XCTAssertTrue(ran.isEmpty)
    }

    func testRestoreButtonForgetsTheReapply() throws {
        let service = make(initial: NativeDockAutohideState(enabled: false, delay: nil))
        try service.apply(delay: 1.0)
        service.restoreOriginal(forget: true)
        ran = []
        service.reapplyDesiredIfNeeded()
        XCTAssertTrue(ran.isEmpty)
    }

    func testSandboxedNeverRuns() {
        let service = make(initial: nil, sandboxed: true)
        XCTAssertFalse(service.restoreOriginal())
        XCTAssertTrue(ran.isEmpty)
    }
}
