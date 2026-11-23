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

    func testRankedUsageAggregatesDescendantsAndSortsDescending() {
        let procs = [
            ProcessMemory.Proc(pid: 10, ppid: 1, bytes: 120 * mb),
            ProcessMemory.Proc(pid: 11, ppid: 10, bytes: 280 * mb),
            ProcessMemory.Proc(pid: 20, ppid: 1, bytes: 250 * mb),
            ProcessMemory.Proc(pid: 30, ppid: 1, bytes: 250 * mb),
            ProcessMemory.Proc(pid: 40, ppid: 1, bytes: 0),
        ]
        let apps = [
            ProcessMemory.AppIdentity(pid: 20, bundleID: "com.beta.app", name: "Beta", isBackgroundApp: true, isRegularApp: false),
            ProcessMemory.AppIdentity(pid: 30, bundleID: "com.alpha.app", name: "Alpha", isBackgroundApp: false, isRegularApp: true),
            ProcessMemory.AppIdentity(pid: 10, bundleID: "com.heavy.app", name: "Heavy", isBackgroundApp: true, isRegularApp: false),
            ProcessMemory.AppIdentity(pid: 40, bundleID: "com.zero.app", name: "Zero", isBackgroundApp: false, isRegularApp: true),
        ]

        let ranked = ProcessMemory.rankedUsage(procs: procs, apps: apps)
        XCTAssertEqual(ranked.map(\.id), ["com.heavy.app", "com.alpha.app", "com.beta.app"])
        XCTAssertEqual(ranked.map(\.bytes), [400 * mb, 250 * mb, 250 * mb])
        XCTAssertEqual(ranked.map(\.isBackgroundApp), [true, false, true])
        XCTAssertEqual(ranked.map(\.isHelper), [true, false, true])
        XCTAssertEqual(ProcessMemory.totalBytes(entries: ranked), 900 * mb)
    }

    func testRankedUsageGroupsMultipleRootsForSameBundleWithoutDoubleCounting() {
        let procs = [
            ProcessMemory.Proc(pid: 100, ppid: 1, bytes: 100 * mb),
            ProcessMemory.Proc(pid: 101, ppid: 100, bytes: 50 * mb),
            ProcessMemory.Proc(pid: 102, ppid: 1, bytes: 80 * mb),
            ProcessMemory.Proc(pid: 103, ppid: 104, bytes: 10 * mb),
            ProcessMemory.Proc(pid: 104, ppid: 103, bytes: 20 * mb),
        ]
        let apps = [
            ProcessMemory.AppIdentity(pid: 100, bundleID: "com.shared.agent", name: "Agent Helper", isBackgroundApp: true, isRegularApp: false),
            ProcessMemory.AppIdentity(pid: 102, bundleID: "com.shared.agent", name: "Shared App", isBackgroundApp: false, isRegularApp: true),
            ProcessMemory.AppIdentity(pid: 103, bundleID: "com.cycle.app", name: "CycleA", isBackgroundApp: false, isRegularApp: true),
            ProcessMemory.AppIdentity(pid: 104, bundleID: "com.cycle2.app", name: "CycleB", isBackgroundApp: false, isRegularApp: true),
        ]

        let ranked = ProcessMemory.rankedUsage(procs: procs, apps: apps)
        let shared = ranked.first { $0.id == "com.shared.agent" }
        XCTAssertEqual(shared?.bytes, 230 * mb)
        XCTAssertEqual(shared?.name, "Shared App")
        XCTAssertEqual(shared?.isBackgroundApp, false)
        XCTAssertEqual(shared?.isHelper, false)

        let cycleSum = ranked
            .filter { $0.id == "com.cycle.app" || $0.id == "com.cycle2.app" }
            .reduce(UInt64(0)) { $0 + $1.bytes }
        XCTAssertEqual(cycleSum, 30 * mb)
    }

    func testRankedUsageIncludesHighRAMFallbackHelpersAndRespectsLimit() {
        let procs = [
            ProcessMemory.Proc(pid: 10, ppid: 1, bytes: 500 * mb),
            ProcessMemory.Proc(pid: 20, ppid: 1, bytes: 120 * mb),
            ProcessMemory.Proc(pid: 21, ppid: 20, bytes: 80 * mb),
            ProcessMemory.Proc(pid: 30, ppid: 1, bytes: 20 * mb),
            ProcessMemory.Proc(pid: 40, ppid: 1, bytes: 90 * mb),
            ProcessMemory.Proc(pid: 50, ppid: 1, bytes: 60 * mb),
        ]
        let apps = [
            ProcessMemory.AppIdentity(pid: 10, bundleID: "com.main.app", name: "Main", isBackgroundApp: false, isRegularApp: true),
        ]
        let fallbackNames: [Int32: String] = [
            20: "mds_stores",
            30: "small_helper",
            40: "   ",
            50: "WindowServer",
        ]

        let ranked = ProcessMemory.rankedUsage(
            procs: procs,
            apps: apps,
            fallbackNames: fallbackNames,
            minFallbackBytes: 30 * mb,
            limit: 2
        )
        XCTAssertEqual(ranked.map(\.id), ["com.main.app", "pid-20"])
        XCTAssertEqual(ranked[1].name, "mds_stores")
        XCTAssertEqual(ranked[1].bytes, 200 * mb)
        XCTAssertTrue(ranked[1].isHelper)
        XCTAssertFalse(ranked[1].isBackgroundApp)
    }
}
