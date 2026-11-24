import XCTest
@testable import KatiKati

final class MenuBarStatModelTests: XCTestCase {
    /// A fresh UUID suite is empty by construction — no teardown needed.
    private func cleanDefaults() -> UserDefaults {
        UserDefaults(suiteName: "MenuBarStatModelTests.\(UUID().uuidString)")!
    }

    func testEveryMetricHasAStyleDomainThatFitsIt() {
        XCTAssertEqual(MenuBarStatModel.styles(for: .cpu), [.percentage, .barGraph, .pieChart])
        XCTAssertEqual(MenuBarStatModel.styles(for: .memory), [.percentage, .barGraph, .pieChart])
        XCTAssertEqual(MenuBarStatModel.styles(for: .gpu), [.percentage, .barGraph, .pieChart])
        XCTAssertEqual(MenuBarStatModel.styles(for: .storage), [.percentage, .available, .used])
        XCTAssertEqual(MenuBarStatModel.styles(for: .battery), [.percentage, .nestedPill, .remainingTime, .watts, .iconOnly])
        XCTAssertEqual(MenuBarStatModel.styles(for: .network), [], "the network readout is speed text, no style")
        for metric in MenuBarMetric.allCases {
            XCTAssertTrue(MenuBarStatModel.styles(for: metric).contains(MenuBarStatModel.defaultStyle(for: metric)) || MenuBarStatModel.styles(for: metric).isEmpty)
        }
    }

    func testUnknownStyleFallsBackToTheDefault() {
        XCTAssertEqual(MenuBarStatModel.style(nil, for: .cpu), .percentage)
        XCTAssertEqual(MenuBarStatModel.style("nonsense", for: .cpu), .percentage)
        XCTAssertEqual(MenuBarStatModel.style("pieChart", for: .battery), .percentage, "battery has no pie")
        XCTAssertEqual(MenuBarStatModel.style("iconOnly", for: .battery), .iconOnly)
        XCTAssertEqual(MenuBarStatModel.style("nestedPill", for: .battery), .nestedPill)
    }

    func testUnsetKeyReadsTheDefaultNotFalse() {
        let defaults = cleanDefaults()
        XCTAssertTrue(MenuBarStatModel.isEnabled(.cpu, defaults: defaults), "the old readout was CPU+MEM: keep it")
        XCTAssertTrue(MenuBarStatModel.isEnabled(.memory, defaults: defaults))
        XCTAssertFalse(MenuBarStatModel.isEnabled(.gpu, defaults: defaults))
        defaults.set(false, forKey: MenuBarStatModel.enabledKey(.cpu))
        XCTAssertFalse(MenuBarStatModel.isEnabled(.cpu, defaults: defaults))
    }

    func testStatusTextFollowsStyleAndMissingReaders() {
        var values = MenuBarStatValues()
        values.cpu = 0.124
        values.memory = 0.61
        values.storageUsed = 0.5
        values.storageFreeBytes = 320_000_000_000
        values.storageTotalBytes = 500_000_000_000
        values.battery = MenuBarBattery(fraction: 0.86, isCharging: true, secondsRemaining: 5040, watts: 18.2)
        values.down = 1_200_000
        values.up = 300_000

        XCTAssertEqual(MenuBarStatModel.statusText(metric: .cpu, style: .percentage, values: values), "12%")
        XCTAssertEqual(MenuBarStatModel.statusText(metric: .cpu, style: .barGraph, values: values), "", "drawing styles render an image, no text")
        XCTAssertEqual(MenuBarStatModel.statusText(metric: .memory, style: .percentage, values: values), "61%")
        XCTAssertEqual(MenuBarStatModel.statusText(metric: .storage, style: .available, values: values), "320.00 GB")
        XCTAssertEqual(MenuBarStatModel.statusText(metric: .storage, style: .used, values: values), "180.00 GB")
        XCTAssertEqual(MenuBarStatModel.statusText(metric: .battery, style: .iconOnly, values: values), "")
        XCTAssertEqual(MenuBarStatModel.statusText(metric: .gpu, style: .percentage, values: values), "–", "no GPU reader result must not read as 0%")
        XCTAssertEqual(MenuBarStatModel.statusText(metric: .battery, style: .percentage, values: values), "86%")
        XCTAssertEqual(MenuBarStatModel.statusText(metric: .battery, style: .remainingTime, values: values), "1h 24m")
        XCTAssertEqual(MenuBarStatModel.statusText(metric: .battery, style: .watts, values: values), "18.2 W")
        XCTAssertEqual(MenuBarStatModel.statusText(metric: .network, style: .percentage, values: values), "↓1.2 MB/s ↑300 KB/s")
        // A battery with no estimate reads as missing, never as 0.
        values.battery = MenuBarBattery(fraction: 0.86, isCharging: false)
        XCTAssertEqual(MenuBarStatModel.statusText(metric: .battery, style: .remainingTime, values: values), "–")
        XCTAssertEqual(MenuBarStatModel.statusText(metric: .battery, style: .watts, values: values), "–")
    }

    func testMenuRowsReadNaturally() {
        var values = MenuBarStatValues()
        values.cpu = 0.5
        values.down = 1_200_000
        values.up = 300_000
        XCTAssertEqual(MenuBarStatModel.menuRowText(metric: .cpu, values: values), "50%")
        XCTAssertEqual(MenuBarStatModel.menuRowText(metric: .network, values: values), "↓1.2 MB/s ↑300 KB/s")
        XCTAssertEqual(MenuBarStatModel.menuRowText(metric: .gpu, values: values), "–")
    }

    func testBatterySymbolTracksLevelAndCharger() {
        XCTAssertEqual(MenuBarStatModel.batterySymbol(nil), "battery.0")
        XCTAssertEqual(MenuBarStatModel.batterySymbol(MenuBarBattery(fraction: 0.1, isCharging: false)), "battery.0")
        XCTAssertEqual(MenuBarStatModel.batterySymbol(MenuBarBattery(fraction: 0.95, isCharging: false)), "battery.100")
        XCTAssertEqual(MenuBarStatModel.batterySymbol(MenuBarBattery(fraction: 0.95, isCharging: true)), "battery.100.bolt")
    }

    func testNestedBatteryPillModelAndDynamicSymbol() {
        var values = MenuBarStatValues()
        values.battery = MenuBarBattery(fraction: 0.87, isCharging: false)
        XCTAssertEqual(MenuBarStatModel.statusText(metric: .battery, style: .nestedPill, values: values), "")
        XCTAssertEqual(MenuBarStatModel.batteryPillLabel(values.battery), "87%")
        XCTAssertEqual(MenuBarStatModel.batteryPillLabel(nil), "–")
        XCTAssertEqual(MenuBarStatModel.symbolName(metric: .battery, values: values), "battery.75")

        values.battery = MenuBarBattery(fraction: 0.12, isCharging: true)
        XCTAssertEqual(MenuBarStatModel.symbolName(metric: .battery, values: values), "battery.0.bolt")
        XCTAssertEqual(MenuBarStatModel.symbolName(metric: .cpu, values: values), "cpu")

        XCTAssertEqual(MenuBarStatModel.batteryPillTone(nil), .critical)
        XCTAssertEqual(MenuBarStatModel.batteryPillTone(MenuBarBattery(fraction: 0.15, isCharging: false)), .critical)
        XCTAssertEqual(MenuBarStatModel.batteryPillTone(MenuBarBattery(fraction: 0.20, isCharging: false)), .warning)
        XCTAssertEqual(MenuBarStatModel.batteryPillTone(MenuBarBattery(fraction: 0.44, isCharging: false)), .warning)
        XCTAssertEqual(MenuBarStatModel.batteryPillTone(MenuBarBattery(fraction: 0.45, isCharging: false)), .healthy)
        XCTAssertEqual(MenuBarStatModel.batteryPillTone(MenuBarBattery(fraction: 0.10, isCharging: true)), .charging)
    }

    func testStatusTrioRenderKeyAndHubConfigs() {
        let defaults = cleanDefaults()
        XCTAssertEqual(MenuBarIconMode.current(defaults), .statusTrio)
        XCTAssertEqual(StatusTrioStrokeWeight.current(defaults), .regular)
        XCTAssertEqual(StatusTrioStrokeWeight.bold.lineWidth, 2.0, accuracy: 0.01)

        let s1 = SystemStatus(
            battery: BatteryStatus(level: 81, isCharging: false, isPluggedIn: false),
            wifi: WiFiStatus(isPoweredOn: true, ssid: "Office", rssi: -60),
            volume: VolumeStatus(level: 0.5, isMuted: false)
        )
        let s2 = SystemStatus(
            battery: BatteryStatus(level: 82, isCharging: false, isPluggedIn: false),
            wifi: WiFiStatus(isPoweredOn: true, ssid: "Office", rssi: -62),
            volume: VolumeStatus(level: 0.52, isMuted: false)
        )
        let k1 = StatusTrioRenderKey(status: s1, stroke: .regular, semanticColor: false, showCompactReadout: false, isDarkMenuBar: true, hasUpdateDot: false)
        let k2 = StatusTrioRenderKey(status: s2, stroke: .regular, semanticColor: false, showCompactReadout: false, isDarkMenuBar: true, hasUpdateDot: false)
        XCTAssertEqual(k1, k2, "5% battery buckets and 3-step volume dots avoid redundant menu bar redraws")
        XCTAssertEqual(k1.volumeDots, 2)

        XCTAssertEqual(HubActionSlotID.slots(defaults), [.keepAwake, .darkMode, .captureOCR, .notchToggle])
        defaults.set("emptyTrash,bogus,emptyTrash,lockScreen", forKey: HubActionSlotID.defaultsKey)
        XCTAssertEqual(HubActionSlotID.slots(defaults), [.emptyTrash, .lockScreen, .keepAwake, .darkMode])

        XCTAssertEqual(MenuBarHubTab.visibleTabs(defaults), MenuBarHubTab.allCases)
        defaults.set("schedules,switches", forKey: MenuBarHubTab.visibleTabsKey)
        XCTAssertEqual(MenuBarHubTab.visibleTabs(defaults), [.schedules, .switches])

        XCTAssertEqual(MenuBarRightClickConfig.toggleTokens(defaults), ["keepAwake", "darkMode", "hideDesktopIcons", "muteOutput"])
        defaults.set("darkMode,unknown,muteOutput", forKey: MenuBarRightClickConfig.defaultsKey)
        XCTAssertEqual(MenuBarRightClickConfig.toggleTokens(defaults), ["darkMode", "muteOutput"])
        defaults.set("", forKey: MenuBarRightClickConfig.defaultsKey)
        XCTAssertEqual(MenuBarRightClickConfig.toggleTokens(defaults), [])
    }
}

/// Tier B: an absent or stale module token must never start a module.
final class HubModuleTests: XCTestCase {
    func testNoKeyMeansEveryModuleIsOff() {
        XCTAssertTrue(HubModule.enabled(nil).isEmpty)
        XCTAssertTrue(HubModule.enabled("").isEmpty)
        XCTAssertFalse(HubModule.isEnabled(.audioMixer, raw: nil))
    }

    func testUnknownTokensAreDroppedAndKnownOnesKept() {
        XCTAssertEqual(HubModule.enabled("agents,notAModule,uninstaller"), [.agents, .uninstaller])
        XCTAssertEqual(HubModule.enabled(" , ,"), [])
    }

    func testSerializeIsCanonicalAndRoundTrips() {
        let raw = HubModule.serialize([.uninstaller, .agents])
        XCTAssertEqual(raw, "agents,uninstaller")
        XCTAssertEqual(HubModule.enabled(raw), [.agents, .uninstaller])
        XCTAssertEqual(HubModule.serialize([]), "")
    }
}
