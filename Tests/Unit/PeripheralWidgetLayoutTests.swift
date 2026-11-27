import XCTest
@testable import KatiKati

final class PeripheralWidgetLayoutTests: XCTestCase {
    private func device(_ name: String, addr: String, battery: Int? = 80, charging: Bool = false) -> BluetoothDevice {
        BluetoothDevice(
            name: name,
            address: addr,
            isConnected: true,
            kind: "Headphones",
            batteryMain: battery,
            batteryLeft: nil,
            batteryRight: nil,
            batteryCase: nil,
            isCharging: charging
        )
    }

    func testArrangedPinsPreferredDeviceHidesHiddenAndKeepsOrder() {
        let d1 = device("AirPods", addr: "AA-1")
        let d2 = device("Mouse", addr: "AA-2")
        let d3 = device("Keyboard", addr: "AA-3")

        let out = PeripheralWidgetPrefs.arranged(
            devices: [d1, d2, d3],
            order: ["AA-3", "AA-1", "AA-2"],
            hiddenIDs: ["aa-1"],
            pinnedID: "AA-2"
        )
        XCTAssertEqual(out.map(\.id), ["AA-2", "AA-3"])
    }

    func testSliceComputesOverflowChipAcrossSizesAndStyles() {
        let list = [
            device("AirPods", addr: "1"),
            device("Mouse", addr: "2"),
            device("Keyboard", addr: "3"),
            device("Trackpad", addr: "4"),
            device("GamePad", addr: "5")
        ]

        let compactStatus = PeripheralWidgetPrefs.slice(devices: list, availableWidth: 112, style: .status)
        XCTAssertEqual(compactStatus.visible.count, 1)
        XCTAssertEqual(compactStatus.overflowCount, 4)

        let ringsMedium = PeripheralWidgetPrefs.slice(devices: list, availableWidth: 150, style: .ring)
        XCTAssertGreaterThan(ringsMedium.visible.count, 1)
        XCTAssertEqual(ringsMedium.visible.count + ringsMedium.overflowCount, 5)

        let iconLarge = PeripheralWidgetPrefs.slice(devices: list, availableWidth: 220, style: .iconOnly)
        XCTAssertEqual(iconLarge.visible.count, 5)
        XCTAssertEqual(iconLarge.overflowCount, 0)
    }

    func testMovingAndTogglingHiddenPersistOrder() {
        let list = [device("One", addr: "1"), device("Two", addr: "2"), device("Three", addr: "3")]
        let moved = PeripheralWidgetPrefs.moving(id: "3", by: -1, devices: list, orderRaw: "[]")
        XCTAssertEqual(PeripheralWidgetPrefs.decodeIDs(moved), ["1", "3", "2"])

        let hidden1 = PeripheralWidgetPrefs.togglingHidden(id: "2", in: "[]")
        XCTAssertEqual(PeripheralWidgetPrefs.decodeIDs(hidden1), ["2"])
        let unhidden = PeripheralWidgetPrefs.togglingHidden(id: "2", in: hidden1)
        XCTAssertEqual(PeripheralWidgetPrefs.decodeIDs(unhidden), [])
    }
}
