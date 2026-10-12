import XCTest
@testable import KatiKati

// The system Dock is given back as the user had it when KatiKati quits (and by "Restore Dock").

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
