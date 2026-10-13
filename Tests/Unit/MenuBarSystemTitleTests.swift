import XCTest
@testable import KatiKati

final class MenuBarSystemTitleTests: XCTestCase {
    func testTitleShowsCPUAndMemoryPercent() {
        var snapshot = SystemSnapshot()
        snapshot.cpu = 0.124
        snapshot.memory = MemoryUsage(used: 61, total: 100)
        XCTAssertEqual(SystemMonitorFormat.menuBarTitle(snapshot), "CPU 12% · MEM 61%")
    }

    func testEmptySnapshotReadsZero() {
        XCTAssertEqual(SystemMonitorFormat.menuBarTitle(SystemSnapshot()), "CPU 0% · MEM 0%")
    }
}
