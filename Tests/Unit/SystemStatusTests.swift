import XCTest
@testable import KatiKati

final class SystemStatusTests: XCTestCase {
    func testBatteryParsesInternalBattery() {
        let b = BatteryStatus(powerSource: [
            "Type": "InternalBattery", "Current Capacity": 42, "Max Capacity": 100,
            "Is Charging": true, "Power Source State": "AC Power",
        ])
        XCTAssertEqual(b?.level, 42)
        XCTAssertEqual(b?.isCharging, true)
        XCTAssertEqual(b?.isPluggedIn, true)
        XCTAssertEqual(b?.symbolName, "battery.100.bolt")
    }

    func testBatteryNormalizesNonPercentCapacities() {
        let b = BatteryStatus(powerSource: ["Current Capacity": 3000, "Max Capacity": 6000])
        XCTAssertEqual(b?.level, 50)
        XCTAssertEqual(b?.isPluggedIn, false)
    }

    func testBatteryRejectsUPSAndMalformed() {
        XCTAssertNil(BatteryStatus(powerSource: ["Type": "UPS", "Current Capacity": 1, "Max Capacity": 2]))
        XCTAssertNil(BatteryStatus(powerSource: ["Current Capacity": 1]))
        XCTAssertNil(BatteryStatus(powerSource: ["Current Capacity": 1, "Max Capacity": 0]))
    }

    func testBatterySymbolSteps() {
        func sym(_ l: Int) -> String { BatteryStatus(level: l, isCharging: false, isPluggedIn: false).symbolName }
        XCTAssertEqual(sym(5), "battery.0")
        XCTAssertEqual(sym(20), "battery.25")
        XCTAssertEqual(sym(50), "battery.50")
        XCTAssertEqual(sym(80), "battery.75")
        XCTAssertEqual(sym(100), "battery.100")
        XCTAssertEqual(BatteryStatus.noBattery.symbolName, "powerplug")
        XCTAssertFalse(BatteryStatus.noBattery.hasBattery)
        XCTAssertEqual(BatteryStatus(level: 250, isCharging: false, isPluggedIn: false).level, 100)
    }

    func testWiFiSignalSteps() {
        func steps(_ r: Int?) -> Int { WiFiStatus(isPoweredOn: true, ssid: nil, rssi: r).signalSteps }
        XCTAssertEqual(steps(-40), 3)
        XCTAssertEqual(steps(-60), 2)
        XCTAssertEqual(steps(-75), 1)
        XCTAssertEqual(steps(-90), 0)
        XCTAssertEqual(steps(nil), 0)
    }

    func testWiFiSymbolStates() {
        XCTAssertEqual(WiFiStatus.off.symbolName, "wifi.slash")
        XCTAssertEqual(WiFiStatus(isPoweredOn: true, ssid: nil, rssi: nil).symbolName, "wifi.exclamationmark")
        let on = WiFiStatus(isPoweredOn: true, ssid: "Home", rssi: -50)
        XCTAssertEqual(on.symbolName, "wifi")
        XCTAssertEqual(on.symbolVariableValue, 1)
    }

    func testVolumeClampsAndPicksSymbols() {
        XCTAssertEqual(VolumeStatus(level: 2, isMuted: false).level, 1)
        XCTAssertEqual(VolumeStatus(level: -1, isMuted: false).level, 0)
        XCTAssertEqual(VolumeStatus(level: .nan, isMuted: false).level, 0)
        XCTAssertEqual(VolumeStatus(level: 0.2, isMuted: false).symbolName, "speaker.wave.1.fill")
        XCTAssertEqual(VolumeStatus(level: 0.5, isMuted: false).symbolName, "speaker.wave.2.fill")
        XCTAssertEqual(VolumeStatus(level: 0.9, isMuted: false).symbolName, "speaker.wave.3.fill")
        XCTAssertEqual(VolumeStatus(level: 0.9, isMuted: true).symbolName, "speaker.slash.fill")
        XCTAssertEqual(VolumeStatus(level: 0.9, isMuted: true).percent, 0)
        XCTAssertEqual(VolumeStatus(level: 0.504, isMuted: false).percent, 50)
    }
}
