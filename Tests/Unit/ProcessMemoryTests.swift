import XCTest
@testable import KatiKati

final class ProcessMemoryTests: XCTestCase {
    private let mb: UInt64 = 1_048_576

    func testAggregatesRootAndDescendantsPerApp() {
        let procs = [
            ProcessMemory.Proc(pid: 10, ppid: 1, bytes: 100 * mb),
            ProcessMemory.Proc(pid: 11, ppid: 10, bytes: 200 * mb),
            ProcessMemory.Proc(pid: 12, ppid: 11, bytes: 50 * mb),
            ProcessMemory.Proc(pid: 20, ppid: 1, bytes: 30 * mb),
            ProcessMemory.Proc(pid: 99, ppid: 1, bytes: 999 * mb),
        ]
        let r = ProcessMemory.aggregate(procs: procs, roots: ["a": 10, "b": 20, "gone": 777])
        XCTAssertEqual(r["a"], 350 * mb)
        XCTAssertEqual(r["b"], 30 * mb)
        XCTAssertNil(r["gone"])
    }

    func testCyclesAndSharedRootsDoNotDoubleCount() {
        let procs = [ProcessMemory.Proc(pid: 5, ppid: 6, bytes: 10), ProcessMemory.Proc(pid: 6, ppid: 5, bytes: 20)]
        XCTAssertEqual(ProcessMemory.aggregate(procs: procs, roots: ["x": 5])["x"], 30)
        let both = ProcessMemory.aggregate(procs: procs, roots: ["x": 5, "y": 6])
        XCTAssertEqual((both["x"] ?? 0) + (both["y"] ?? 0), 30, "a process belongs to one app only")
    }

    func testTiersAndFormatting() {
        XCTAssertEqual(ProcessMemory.tier(bytes: 499 * mb), .low)
        XCTAssertEqual(ProcessMemory.tier(bytes: 500 * mb), .medium)
        XCTAssertEqual(ProcessMemory.tier(bytes: 2 * 1_073_741_824 - 1), .medium)
        XCTAssertEqual(ProcessMemory.tier(bytes: 2 * 1_073_741_824), .high)
        XCTAssertTrue(ProcessMemory.format(bytes: 812 * mb).contains("MB"))
        XCTAssertTrue(ProcessMemory.format(bytes: 1_500_000_000).contains("GB"))
    }
}
