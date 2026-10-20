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
        XCTAssertEqual(MenuBarStatModel.styles(for: .battery), [.percentage, .iconOnly])
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
        values.battery = MenuBarBattery(fraction: 0.86, isCharging: true)
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
}
