import XCTest
@testable import KatiKati

final class PeripheralDiffTests: XCTestCase {
    private func device(
        _ name: String,
        address: String = "",
        connected: Bool = true,
        kind: String? = "Headphones",
        main: Int? = nil,
        left: Int? = nil,
        right: Int? = nil,
        caseLevel: Int? = nil
    ) -> BluetoothDevice {
        BluetoothDevice(
            name: name,
            address: address.isEmpty ? name : address,
            isConnected: connected,
            kind: kind,
            batteryMain: main,
            batteryLeft: left,
            batteryRight: right,
            batteryCase: caseLevel
        )
    }

    func testConnectAndDisconnectEmitOncePerTransition() {
        let pods = device("AirPods Pro", address: "AA:BB:CC", left: 80, right: 78, caseLevel: 100)
        let mouse = device("MX Master", address: "11:22:33", kind: "Mouse", main: 65)

        let first = PeripheralDiff.diff(old: [mouse], new: [mouse, pods], alreadyLow: [])
        XCTAssertEqual(first.events, [.connected(pods)])
        XCTAssertTrue(first.low.isEmpty)

        // Same address in lowercase is treated as the same device (no spurious reconnect).
        let podsLower = device("AirPods Pro", address: "aa:bb:cc", left: 80, right: 78, caseLevel: 100)
        let steady = PeripheralDiff.diff(old: [mouse, pods], new: [mouse, podsLower], alreadyLow: first.low)
        XCTAssertTrue(steady.events.isEmpty)

        let disconnected = PeripheralDiff.diff(old: [mouse, podsLower], new: [mouse], alreadyLow: steady.low)
        XCTAssertEqual(disconnected.events, [.disconnected(podsLower)])
    }

    func testLowBatteryAlertsOnceUntilRecoveryOrDisconnect() {
        let healthy = device("AirPods Pro", address: "AA:01", left: 50, right: 50, caseLevel: 90)
        let dipping = device("AirPods Pro", address: "AA:01", left: 50, right: 15, caseLevel: 90)

        let dipped = PeripheralDiff.diff(old: [healthy], new: [dipping], alreadyLow: [])
        XCTAssertEqual(dipped.events, [.low(dipping)])
        XCTAssertEqual(dipped.low, ["aa:01"])

        // Stays low → no repeat alert.
        let stillLow = PeripheralDiff.diff(old: [dipping], new: [dipping], alreadyLow: dipped.low)
        XCTAssertTrue(stillLow.events.isEmpty)
        XCTAssertEqual(stillLow.low, ["aa:01"])

        // Recovers above threshold → clears low state.
        let recovered = PeripheralDiff.diff(old: [dipping], new: [healthy], alreadyLow: stillLow.low)
        XCTAssertTrue(recovered.events.isEmpty)
        XCTAssertTrue(recovered.low.isEmpty)

        // Dips again → alerts again.
        let reDipped = PeripheralDiff.diff(old: [healthy], new: [dipping], alreadyLow: recovered.low)
        XCTAssertEqual(reDipped.events, [.low(dipping)])
    }

    func testConnectingAlreadyLowEmitsConnectWithoutDuplicateLow() {
        let lowPods = device("AirPods", address: "AA:02", left: 10, right: 15, caseLevel: 40)
        let res = PeripheralDiff.diff(old: [], new: [lowPods], alreadyLow: [])
        XCTAssertEqual(res.events, [.connected(lowPods)])
        XCTAssertEqual(res.low, ["aa:02"])
    }

    func testFollowUpNeededOnlyForAudioPeripheralMissingBattery() {
        let podsNoBattery = device("AirPods 4", address: "AA:03")
        let podsWithBattery = device("AirPods 4", address: "AA:03", left: 90)
        let mouseNoBattery = device("BT Mouse", address: "BB:01", kind: "Mouse")

        XCTAssertTrue(PeripheralDiff.needsBatteryFollowUp(in: [.connected(podsNoBattery)]))
        XCTAssertFalse(PeripheralDiff.needsBatteryFollowUp(in: [.connected(podsWithBattery)]))
        XCTAssertFalse(PeripheralDiff.needsBatteryFollowUp(in: [.connected(mouseNoBattery)]))
        XCTAssertFalse(PeripheralDiff.needsBatteryFollowUp(in: [.disconnected(podsNoBattery)]))
    }
}
