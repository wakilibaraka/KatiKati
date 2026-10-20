import XCTest
@testable import KatiKati

final class BluetoothDevicesTests: XCTestCase {
    private let fixture = """
    {"SPBluetoothDataType":[{"controller_properties":{"controller_state":"attrib_on"},
     "device_connected":[
       {"BT5.4 Mouse":{"device_address":"AA:01","device_minorType":"Mouse","device_batteryLevelMain":"85%"}},
       {"AirPods Pro":{"device_address":"AA:02","device_minorType":"Headphones","device_batteryLevelLeft":"90%","device_batteryLevelRight":"40 %","device_batteryLevelCase":"100%"}}],
     "device_not_connected":[
       {"Old Keyboard":{"device_address":"AA:03","device_minorType":"Keyboard"}},
       {"alpha speaker":{"device_address":"AA:04"}}]}]}
    """.data(using: .utf8)!

    func testParsesConnectedFirstThenByNameCaseInsensitive() {
        let d = BluetoothDeviceParser.parse(fixture)
        XCTAssertEqual(d.map(\.name), ["AirPods Pro", "BT5.4 Mouse", "alpha speaker", "Old Keyboard"])
        XCTAssertEqual(d.map(\.isConnected), [true, true, false, false])
    }

    func testBatteryFieldsAndLowestLevel() {
        let d = BluetoothDeviceParser.parse(fixture)
        let pods = d.first { $0.name == "AirPods Pro" }!
        XCTAssertEqual(pods.batteryLeft, 90)
        XCTAssertEqual(pods.batteryRight, 40, "stray space before % tolerated")
        XCTAssertEqual(pods.batteryCase, 100)
        XCTAssertEqual(pods.lowestBattery, 40)
        XCTAssertEqual(d.first { $0.name == "BT5.4 Mouse" }?.lowestBattery, 85)
        XCTAssertNil(d.first { $0.name == "Old Keyboard" }?.lowestBattery)
    }

    func testSymbolsFollowTheMinorType() {
        let d = BluetoothDeviceParser.parse(fixture)
        XCTAssertEqual(d.first { $0.name == "AirPods Pro" }?.symbolName, "headphones")
        XCTAssertEqual(d.first { $0.name == "BT5.4 Mouse" }?.symbolName, "computermouse")
        XCTAssertEqual(d.first { $0.name == "Old Keyboard" }?.symbolName, "keyboard")
        XCTAssertEqual(d.first { $0.name == "alpha speaker" }?.symbolName, "dot.radiowaves.left.and.right")
    }

    func testMalformedAndEmptyInputGiveNoDevices() {
        XCTAssertTrue(BluetoothDeviceParser.parse(Data()).isEmpty)
        XCTAssertTrue(BluetoothDeviceParser.parse(Data("{}".utf8)).isEmpty)
        XCTAssertTrue(BluetoothDeviceParser.parse(Data("{\"SPBluetoothDataType\":[{\"device_connected\":[1,2]}]}".utf8)).isEmpty)
    }

    func testPercentParsingClampsAndRejectsJunk() {
        XCTAssertEqual(BluetoothDeviceParser.percent("85%"), 85)
        XCTAssertEqual(BluetoothDeviceParser.percent(150), 100)
        XCTAssertEqual(BluetoothDeviceParser.percent("-3"), 0)
        XCTAssertNil(BluetoothDeviceParser.percent("n/a"))
        XCTAssertNil(BluetoothDeviceParser.percent(nil))
    }

    func testDevicesWithoutAddressUseNameAsIdentity() {
        let d = BluetoothDevice(name: "X", address: "", isConnected: true)
        XCTAssertEqual(d.id, "X")
    }

    func testBatteryBuddyAlertsOncePerDip() {
        let low = BluetoothDevice(name: "Pods", address: "A", isConnected: true, batteryMain: 15)
        let ok = BluetoothDevice(name: "Mouse", address: "B", isConnected: true, batteryMain: 80)
        let off = BluetoothDevice(name: "Old", address: "C", isConnected: false, batteryMain: 5)
        let first = BatteryBuddyPolicy.update(alreadyLow: [], devices: [low, ok, off])
        XCTAssertEqual(first.alerts.map(\.name), ["Pods"])
        XCTAssertTrue(BatteryBuddyPolicy.update(alreadyLow: first.low, devices: [low]).alerts.isEmpty)
        var recovered = low; recovered.batteryMain = 60
        let after = BatteryBuddyPolicy.update(alreadyLow: first.low, devices: [recovered])
        XCTAssertTrue(after.low.isEmpty)
        XCTAssertEqual(BatteryBuddyPolicy.update(alreadyLow: after.low, devices: [low]).alerts.count, 1)
    }
}
