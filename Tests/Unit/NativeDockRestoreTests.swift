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

    private func make(initial: NativeDockAutohideState?, sandboxed: Bool = false,
                      mruSpaces: @escaping @Sendable () -> Bool? = { true }) -> NativeDockPreferencesService {
        let defaults = TestDefaults.make("com.katikati.tests.dockrestore", for: self)
        return NativeDockPreferencesService(
            sandbox: SandboxEnvironment(isSandboxed: sandboxed),
            runner: { [unowned self] exe, args in self.ran.append([exe] + args) },
            autohideReader: { initial },
            spaceOrderReader: mruSpaces,
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

    // 54d — fixed Space order: one key write plus exactly one Dock restart, and “off” never guesses.
    func testSpaceOrderCommandsWriteOnceAndRestartTheDockOnce() {
        let on = NativeDockPreferencesService.spaceOrderCommands(fixed: true, original: true)
        XCTAssertEqual(on.map(\.arguments), [["write", "com.apple.dock", "mru-spaces", "-bool", "false"], ["Dock"]])
        XCTAssertEqual(on.filter { $0.executable == "/usr/bin/killall" }.count, 1)

        let backToAutomatic = NativeDockPreferencesService.spaceOrderCommands(fixed: false, original: true)
        XCTAssertEqual(backToAutomatic.first?.arguments, ["write", "com.apple.dock", "mru-spaces", "-bool", "true"])
        XCTAssertEqual(NativeDockPreferencesService.spaceOrderCommands(fixed: false, original: false).first?.arguments,
                       ["write", "com.apple.dock", "mru-spaces", "-bool", "false"])
        XCTAssertTrue(NativeDockPreferencesService.spaceOrderCommands(fixed: false, original: nil).isEmpty,
                      "nothing was remembered, so there is nothing to put back")
    }

    func testFixedSpaceOrderRemembersTheDockValueOnceAndPutsItBack() throws {
        var current: Bool? = true
        let service = make(initial: nil, mruSpaces: { current })
        try service.setFixedSpaceOrder(true)
        XCTAssertEqual(ran.map { Array($0.dropFirst()) },
                       [["write", "com.apple.dock", "mru-spaces", "-bool", "false"], ["Dock"]])

        // A later enable must not overwrite what the user had before the first one.
        current = false
        try service.setFixedSpaceOrder(true)
        ran = []
        try service.setFixedSpaceOrder(false)
        XCTAssertEqual(ran.map { Array($0.dropFirst()) },
                       [["write", "com.apple.dock", "mru-spaces", "-bool", "true"], ["Dock"]])
    }

    func testTurningFixedOrderOffWithNothingRememberedWritesNothing() throws {
        let service = make(initial: nil)
        try service.setFixedSpaceOrder(false)
        XCTAssertTrue(ran.isEmpty)
    }

    func testSpaceOrderReadNeedsABooleanAndAMissingKeyMeansAutomatic() async {
        XCTAssertEqual(NativeDockPreferencesService.readMruSpaces(synchronize: { true }, valueForKey: { _ in nil }), true)
        XCTAssertEqual(NativeDockPreferencesService.readMruSpaces(synchronize: { true }, valueForKey: { _ in false }), false)
        XCTAssertNil(NativeDockPreferencesService.readMruSpaces(synchronize: { true }, valueForKey: { _ in "false" }),
                     "a string is not a boolean")
        XCTAssertNil(NativeDockPreferencesService.readMruSpaces(synchronize: { false }, valueForKey: { _ in true }),
                     "an unsynchronised cache is not trustworthy")

        let fixed = make(initial: nil, mruSpaces: { false })
        let automatic = make(initial: nil, mruSpaces: { true })
        let unreadable = make(initial: nil, mruSpaces: { nil })
        let isFixed = await fixed.fixedSpaceOrderState()
        let isAutomatic = await automatic.fixedSpaceOrderState()
        let unknown = await unreadable.fixedSpaceOrderState()
        XCTAssertEqual(isFixed, true)
        XCTAssertEqual(isAutomatic, false)
        XCTAssertNil(unknown)
    }
}
