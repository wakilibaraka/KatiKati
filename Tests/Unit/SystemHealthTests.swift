import XCTest
@testable import KatiKati

final class SystemHealthTests: XCTestCase {
    func testBatteryHealthIntel() {
        let h = BatteryHealth(registry: ["CycleCount": 312, "DesignCapacity": 6000, "MaxCapacity": 5100, "Temperature": 3050])
        XCTAssertEqual(h?.cycleCount, 312)
        XCTAssertEqual(h?.healthPercent, 85)
        XCTAssertEqual(h?.temperatureCelsius ?? 0, 30.5, accuracy: 0.01)
    }

    func testBatteryHealthAppleSilicon() {
        let h = BatteryHealth(registry: ["CycleCount": 40, "DesignCapacity": 5000, "MaxCapacity": 94, "AppleRawMaxCapacity": 4700])
        XCTAssertEqual(h?.healthPercent, 94)
        XCTAssertEqual(BatteryHealth(registry: ["CycleCount": 1, "MaxCapacity": 97])?.healthPercent, 97)
    }

    func testBatteryHealthMissingCycles() {
        XCTAssertNil(BatteryHealth(registry: ["MaxCapacity": 90]))
    }

    func testTopProcessesSumAndSort() {
        let out = """
         12.5 /Applications/Safari.app/Contents/MacOS/Safari
          3.0 /usr/libexec/helper
          8.0 /Applications/Safari.app/Contents/MacOS/Safari
          bogus line
          0.0 /sbin/launchd
        """
        let top = TopProcessParser.parse(out, limit: 2)
        XCTAssertEqual(top, [TopProcess(name: "Safari", cpu: 20.5), TopProcess(name: "helper", cpu: 3.0)])
    }
}
