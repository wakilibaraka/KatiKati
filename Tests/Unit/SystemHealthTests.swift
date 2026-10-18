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

    // Phase 48d: the read keeps the pid, so same-named processes stay separate rows —
    // summing them would destroy the pid the kill flow needs. This replaces the old
    // sum-and-sort contract on purpose (the slice deletes the name-summing).
    func testTopProcessesKeepPidsAndSort() {
        let out = """
          101 12.5 /Applications/Safari.app/Contents/MacOS/Safari
          202  3.0 /usr/libexec/helper
          303  8.0 /Applications/Safari.app/Contents/MacOS/Safari
          bogus line
          404  0.0 /sbin/launchd
        """
        let top = TopProcessParser.parse(out, limit: 3)
        XCTAssertEqual(top, [TopProcess(pid: 101, name: "Safari", cpu: 12.5),
                             TopProcess(pid: 303, name: "Safari", cpu: 8.0),
                             TopProcess(pid: 202, name: "helper", cpu: 3.0)])
        XCTAssertTrue(top.allSatisfy(\.canAct))
    }

    // Phase 48d: the exact `ps` args the reader runs, through the real parser — every live row
    // keeps its pid, so every live row is actionable.
    func testParserReadsLivePsOutput() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-Ao", "pid=,pcpu=,comm=", "-r"]
        let pipe = Pipe()
        p.standardOutput = pipe
        guard (try? p.run()) != nil else { XCTFail("ps failed to launch"); return }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let rows = TopProcessParser.parse(String(data: data, encoding: .utf8) ?? "", limit: 8)
        XCTAssertFalse(rows.isEmpty)
        XCTAssertTrue(rows.allSatisfy(\.canAct))
        XCTAssertEqual(rows, rows.sorted { $0.cpu > $1.cpu })
    }

    // Phase 48d: a row without a pid offers no action — it can only print.
    func testTopProcessWithoutPidOffersNoAction() {
        let out = """
         12.5 /Applications/Safari.app/Contents/MacOS/Safari
        """
        let top = TopProcessParser.parse(out, limit: 4)
        XCTAssertEqual(top, [TopProcess(pid: nil, name: "Safari", cpu: 12.5)])
        XCTAssertFalse(top[0].canAct)
    }
}
