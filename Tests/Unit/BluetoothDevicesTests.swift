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

    /// BeteriApp's registry pass fills the level the profiler omitted, without duplicating the device.
    func testRegistryLevelFillsAProfilerGap() {
        let profiled = [BluetoothDevice(name: "BT5.4 Mouse", address: "aa:01", isConnected: true, kind: "Mouse", batteryMain: nil)]
        let registry = [BluetoothDevice(name: "BT5.4 Mouse", address: "AA:01", isConnected: true, kind: "Mouse", batteryMain: 64)]
        let merged = BluetoothDeviceRegistry.merge(profiled, registry)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.batteryMain, 64)
    }

    func testRegistryAddsDevicesTheProfilerMissedButNotTwinsByName() {
        let profiled = [BluetoothDevice(name: "Magic Keyboard", address: "aa:02", isConnected: true, batteryMain: 80)]
        let registry = [
            BluetoothDevice(name: "Magic Keyboard", address: "bb:09", isConnected: true, batteryMain: 20),
            BluetoothDevice(name: "Studio Buds", address: "cc:03", isConnected: true, kind: "Headphones", batteryMain: 55),
        ]
        let merged = BluetoothDeviceRegistry.merge(profiled, registry)
        XCTAssertEqual(merged.map(\.name), ["Magic Keyboard", "Studio Buds"])
        XCTAssertEqual(merged.first?.batteryMain, 80, "a level already read is never overwritten")
    }

    func testRegistryProductNamesMapToDeviceKinds() {
        XCTAssertEqual(BluetoothDeviceRegistry.kind(of: "BT5.4 Mouse"), "Mouse")
        XCTAssertEqual(BluetoothDeviceRegistry.kind(of: "Magic Keyboard with Touch ID"), "Keyboard")
        XCTAssertEqual(BluetoothDeviceRegistry.kind(of: "AirPods Pro"), "Headphones")
        XCTAssertNil(BluetoothDeviceRegistry.kind(of: "Wakili's S22+"))
    }

    func testBreakdownAndLowFlag() {
        let pods = BluetoothDevice(name: "Pods", address: "a", isConnected: true, kind: nil, batteryMain: nil, batteryLeft: 80, batteryRight: 15, batteryCase: 60)
        XCTAssertEqual(pods.batteryBreakdown, "L 80 · R 15 · C 60")
        XCTAssertTrue(pods.isLowBattery)
        let mouse = BluetoothDevice(name: "M", address: "b", isConnected: true, kind: nil, batteryMain: 50, batteryLeft: nil, batteryRight: nil, batteryCase: nil)
        XCTAssertNil(mouse.batteryBreakdown)
        XCTAssertFalse(mouse.isLowBattery)
    }

    func testRichSymbolNameAndAudioPeripheralClassification() {
        let pro = BluetoothDevice(name: "Baraka's AirPods Pro", address: "1", isConnected: true, kind: "Headphones")
        let maxPods = BluetoothDevice(name: "AirPods Max", address: "2", isConnected: true, kind: "Headphones")
        let plainPods = BluetoothDevice(name: "AirPods 4", address: "3", isConnected: true, kind: nil)
        let buds = BluetoothDevice(name: "Beats Fit Buds", address: "4", isConnected: true, kind: nil)
        let mouse = BluetoothDevice(name: "MX Master 3S Mouse", address: "5", isConnected: true, kind: "Mouse")
        let phone = BluetoothDevice(name: "iPhone 16 Pro", address: "6", isConnected: true, kind: nil)

        XCTAssertEqual(pro.richSymbolName, "airpodspro")
        XCTAssertEqual(maxPods.richSymbolName, "airpodsmax")
        XCTAssertEqual(plainPods.richSymbolName, "airpods")
        XCTAssertEqual(buds.richSymbolName, "earbuds")
        XCTAssertEqual(mouse.richSymbolName, "computermouse")
        XCTAssertEqual(phone.richSymbolName, "iphone")

        XCTAssertTrue(pro.isAudioPeripheral)
        XCTAssertTrue(plainPods.isAudioPeripheral)
        XCTAssertTrue(buds.isAudioPeripheral)
        XCTAssertFalse(mouse.isAudioPeripheral)
        XCTAssertFalse(phone.isAudioPeripheral)
    }

    func testDockPeripheralBatteryOverviewOrdersLowFirstAndHandlesDesktopMac() {
        let podsLow = BluetoothDevice(name: "AirPods Pro", address: "a", isConnected: true, kind: "Headphones", batteryLeft: 90, batteryRight: 15, batteryCase: 60)
        let keyboard = BluetoothDevice(name: "Magic Keyboard", address: "b", isConnected: true, kind: "Keyboard", batteryMain: 78)
        let trackpad = BluetoothDevice(name: "Magic Trackpad", address: "c", isConnected: true, kind: "Trackpad", batteryMain: 42)
        let speakerNoBattery = BluetoothDevice(name: "Living Room Speaker", address: "d", isConnected: true, kind: "Speaker", batteryMain: nil)
        let offlineMouse = BluetoothDevice(name: "Spare Mouse", address: "e", isConnected: false, kind: "Mouse", batteryMain: 5)

        let laptop = DockPeripheralBatteryOverview.build(
            macPercent: 88,
            macCharging: false,
            macOnAC: false,
            devices: [speakerNoBattery, keyboard, offlineMouse, trackpad, podsLow]
        )
        XCTAssertEqual(laptop.connectedPeripherals.map(\.name), [
            "AirPods Pro", "Magic Trackpad", "Magic Keyboard", "Living Room Speaker"
        ])
        XCTAssertEqual(laptop.topBatteryPeripherals(limit: 2).map(\.name), ["AirPods Pro", "Magic Trackpad"])
        XCTAssertEqual(laptop.lowestOverallPercent, 15)
        XCTAssertTrue(laptop.hasAnyLowDevice)

        let desktopSafe = DockPeripheralBatteryOverview.build(
            macPercent: nil,
            macCharging: false,
            macOnAC: true,
            devices: [keyboard, speakerNoBattery]
        )
        XCTAssertNil(desktopSafe.macPercent)
        XCTAssertEqual(desktopSafe.lowestOverallPercent, 78)
        XCTAssertFalse(desktopSafe.hasAnyLowDevice)

        let macChargingLow = DockPeripheralBatteryOverview.build(
            macPercent: 12,
            macCharging: true,
            macOnAC: true,
            devices: [keyboard]
        )
        XCTAssertFalse(macChargingLow.hasAnyLowDevice)
    }
}
