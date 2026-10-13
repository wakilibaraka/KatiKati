import XCTest
@testable import KatiKati

/// Phase 16m: the Control Center switch catalog (moved from the deleted Pinboard tests) plus the
/// reinstated VPN parser test (the 16i-2 debt: Core keeps the single parser implementation).
final class QuickTogglesTests: XCTestCase {
    func testToggleParseAndFlags() {
        XCTAssertEqual(QuickToggleID.parse(nil).count, 18, "screen saver + lock + relaunch + mirroring joined the catalog")
        XCTAssertEqual(QuickToggleID.parse("wifi,nope,darkMode"), [.wifi, .darkMode])
        XCTAssertEqual(QuickToggleID.parse("screenSaver,screenMirroring"), [.screenSaver, .screenMirroring])
        XCTAssertTrue(QuickToggleID.emptyTrash.needsConfirm)
        XCTAssertTrue(QuickToggleID.lockScreen.needsConfirm)
        XCTAssertTrue(QuickToggleID.relaunchFinder.needsConfirm)
        XCTAssertFalse(QuickToggleID.screenSaver.needsConfirm)
        XCTAssertTrue(QuickToggleID.screenSaver.isAction)
        XCTAssertTrue(QuickToggleID.screenMirroring.isAction)
        XCTAssertFalse(QuickToggleID.darkMode.isAction)
        XCTAssertTrue(QuickToggleID.ejectDisks.isAction)
    }

    func testVPNParserSkipsGarbageAndReadsConnected() {
        let out = """
             * (Connected)  01234567-89AB-CDEF-0123-456789ABCDEF  "My VPN"  [VPN:...]
             * (Disconnected)  FEDCBA98-7654-3210-FEDC-BA9876543210  "Office"  [VPN:...]
            bogus line without an id
            """
        let list = VPNServiceParser.parse(out)
        XCTAssertEqual(list.map(\.name), ["My VPN", "Office"])
        XCTAssertEqual(list.map(\.connected), [true, false])
        XCTAssertTrue(VPNServiceParser.parse("").isEmpty)
    }
}
