import XCTest
@testable import KatiKati

/// Phase 16m: the Control Center switch catalog (moved from the deleted Pinboard tests) plus the
/// reinstated VPN parser test (the 16i-2 debt: Core keeps the single parser implementation).
final class QuickTogglesTests: XCTestCase {
    func testToggleParseAndFlags() {
        XCTAssertEqual(QuickToggleID.parse(nil).count, 20, "muteOutput + cleanKeyboard joined the catalog")
        XCTAssertEqual(QuickToggleID.parse("wifi,nope,darkMode"), [.wifi, .darkMode])
        XCTAssertEqual(QuickToggleID.parse("screenSaver,screenMirroring"), [.screenSaver, .screenMirroring])
        XCTAssertTrue(QuickToggleID.emptyTrash.needsConfirm)
        XCTAssertTrue(QuickToggleID.lockScreen.needsConfirm)
        XCTAssertTrue(QuickToggleID.relaunchFinder.needsConfirm)
        XCTAssertFalse(QuickToggleID.screenSaver.needsConfirm)
        XCTAssertTrue(QuickToggleID.screenSaver.isAction)
        XCTAssertTrue(QuickToggleID.cleanKeyboard.isAction)
        XCTAssertFalse(QuickToggleID.muteOutput.isAction)
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

    func testHubSwitchCatalogOrderFilterAndTokens() {
        let suite = UserDefaults(suiteName: "QuickTogglesTests.\(UUID().uuidString)")!
        let evoID = UUID()
        let extra: [HubSwitchID] = [.shortcut("Morning Focus"), .evolution(evoID)]
        let initial = HubSwitchCatalog.orderedSwitches(extra: extra, defaults: suite)
        XCTAssertTrue(initial.contains(.surface(.notch)))
        XCTAssertTrue(initial.contains(.shortcut("Morning Focus")))
        XCTAssertTrue(initial.contains(.evolution(evoID)))

        suite.set("sc:Morning Focus,sys:darkMode,bogus:nope", forKey: HubSwitchCatalog.orderKey)
        suite.set("sys:emptyTrash", forKey: HubSwitchCatalog.hiddenKey)
        let custom = HubSwitchCatalog.orderedSwitches(extra: extra, defaults: suite)
        XCTAssertEqual(custom.prefix(2), [.shortcut("Morning Focus"), .system(.darkMode)])
        XCTAssertFalse(custom.contains(.system(.emptyTrash)))

        let filtered = HubSwitchCatalog.filter(custom, query: "morn") { $0.token }
        XCTAssertEqual(filtered, [.shortcut("Morning Focus")])
        XCTAssertEqual(HubSwitchID(token: "evo:\(evoID.uuidString)"), .evolution(evoID))
        XCTAssertNil(HubSwitchID(token: "sc:"))
    }

    func testEvolutionCodecAndScheduleNextFireDate() {
        let evo = EvolutionItem(title: "Flush DNS", symbolName: "  ", kind: .action, shell: .sh, runScript: "dscacheutil -flushcache")
        XCTAssertEqual(evo.symbolName, "terminal")
        let decoded = EvolutionItem.parse(EvolutionItem.encode([evo]))
        XCTAssertEqual(decoded, [evo])
        XCTAssertTrue(EvolutionItem.parse(Data("bad".utf8)).isEmpty)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let base = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 22:13:20 UTC
        let futureTimer = HubScheduleRule(targetToken: "sys:keepAwake", desiredState: true, kind: .afterMinutes(15), createdAt: base)
        let expiredTimer = HubScheduleRule(targetToken: "sys:darkMode", desiredState: false, kind: .afterMinutes(1), createdAt: base.addingTimeInterval(-120))
        let disabledDaily = HubScheduleRule(targetToken: "sys:nightShift", desiredState: true, kind: .daily(hour: 22, minute: 15), isEnabled: false, createdAt: base)
        let dailyLater = HubScheduleRule(targetToken: "sys:darkMode", desiredState: true, kind: .daily(hour: 22, minute: 30), createdAt: base)

        XCTAssertNil(expiredTimer.nextFireDate(after: base, calendar: cal))
        XCTAssertNil(disabledDaily.nextFireDate(after: base, calendar: cal))
        let next = HubScheduleRule.nextPendingRule(in: [expiredTimer, disabledDaily, dailyLater, futureTimer], after: base, calendar: cal)
        XCTAssertEqual(next?.rule.id, futureTimer.id)
        XCTAssertEqual(next?.fireDate, base.addingTimeInterval(900))
    }
}
