import XCTest
@testable import KatiKati

final class SystemMonitorMathTests: XCTestCase {
    func testCPUUsageIsBusyShareBetweenSamples() {
        let a = CPUTicks(user: 100, system: 100, idle: 800, nice: 0)
        let b = CPUTicks(user: 200, system: 150, idle: 850, nice: 0)   // 150 busy of 200
        XCTAssertEqual(CPUTicks.usage(from: a, to: b), 0.75, accuracy: 0.0001)
        XCTAssertEqual(CPUTicks.usage(from: a, to: a), 0, "nothing elapsed")
        XCTAssertEqual(CPUTicks.usage(from: b, to: a), 0, "counters went backwards")
        XCTAssertEqual(CPUTicks.usage(from: a, to: CPUTicks(user: 100, system: 100, idle: 900, nice: 0)), 0, accuracy: 0.0001)
    }

    func testNetworkRateAndCounterReset() {
        let a = NetCounters(received: 1_000, sent: 500)
        let b = NetCounters(received: 3_000, sent: 1_500)
        let r = NetCounters.rate(from: a, to: b, seconds: 2)
        XCTAssertEqual(r.down, 1_000); XCTAssertEqual(r.up, 500)
        let reset = NetCounters.rate(from: b, to: a, seconds: 1)
        XCTAssertEqual(reset.down, 0); XCTAssertEqual(reset.up, 0)
        XCTAssertEqual(NetCounters.rate(from: a, to: b, seconds: 0).down, 0)
    }

    func testFractionsAreClamped() {
        XCTAssertEqual(MemoryUsage(used: 50, total: 100).fraction, 0.5)
        XCTAssertEqual(MemoryUsage(used: 500, total: 100).fraction, 1)
        XCTAssertEqual(MemoryUsage(used: 1, total: 0).fraction, 0)
        XCTAssertEqual(DiskUsage(free: 25, total: 100).usedFraction, 0.75)
        XCTAssertEqual(DiskUsage(free: 200, total: 100).usedFraction, 0)
    }

    func testFormatting() {
        XCTAssertEqual(SystemMonitorFormat.percent(0.456), "46%")
        XCTAssertEqual(SystemMonitorFormat.percent(7), "100%")
        XCTAssertEqual(SystemMonitorFormat.bytes(999), "999 B")
        XCTAssertEqual(SystemMonitorFormat.bytes(12_300), "12 KB")
        XCTAssertEqual(SystemMonitorFormat.bytes(12_300_000), "12.3 MB")
        XCTAssertEqual(SystemMonitorFormat.bytes(1_500_000_000), "1.50 GB")
        XCTAssertEqual(SystemMonitorFormat.bytes(-5), "0 B")
    }

    func testSamplersReturnPlausibleNumbers() {
        XCTAssertNotNil(SystemMonitorSampler.cpuTicks())
        let m = SystemMonitorSampler.memory()
        XCTAssertGreaterThan(m.total, 0); XCTAssertGreaterThan(m.used, 0); XCTAssertLessThanOrEqual(m.used, m.total)
        let d = SystemMonitorSampler.disk()
        XCTAssertGreaterThan(d.total, 0); XCTAssertLessThanOrEqual(d.free, d.total)
        _ = SystemMonitorSampler.network()
    }
}
