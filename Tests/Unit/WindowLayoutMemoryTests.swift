import XCTest
@testable import KatiKati

final class WindowLayoutMemoryTests: XCTestCase {
    private func win(_ id: UInt32, _ x: CGFloat, _ y: CGFloat, w: CGFloat = 800, h: CGFloat = 600) -> WindowLayoutMemory.Window {
        .init(pid: 10, cgWindowID: id, frame: CGRect(x: x, y: y, width: w, height: h))
    }

    func testTopologyKeyIsOrderIndependent() {
        XCTAssertEqual(WindowLayoutMemory.topologyKey(displayUUIDs: ["b", "a"]), WindowLayoutMemory.topologyKey(displayUUIDs: ["a", "b"]))
        XCTAssertNotEqual(WindowLayoutMemory.topologyKey(displayUUIDs: ["a"]), WindowLayoutMemory.topologyKey(displayUUIDs: ["a", "b"]))
    }

    func testPlanRestoresWindowsThatMoved() {
        var memory = WindowLayoutMemory()
        memory.record(topology: "AB", windows: [win(1, 2000, 100), win(2, 100, 100)])
        let moves = memory.plan(topology: "AB", current: [win(1, 40, 40), win(2, 100, 100)])
        XCTAssertEqual(moves, [.init(pid: 10, cgWindowID: 1, frame: CGRect(x: 2000, y: 100, width: 800, height: 600))])
    }

    func testSmallDriftIsIgnored() {
        var memory = WindowLayoutMemory()
        memory.record(topology: "A", windows: [win(1, 100, 100)])
        XCTAssertTrue(memory.plan(topology: "A", current: [win(1, 104, 96)]).isEmpty)
    }

    func testUnknownTopologyAndUnknownWindowsAreLeftAlone() {
        var memory = WindowLayoutMemory()
        memory.record(topology: "AB", windows: [win(1, 2000, 100)])
        XCTAssertTrue(memory.plan(topology: "A", current: [win(1, 0, 0)]).isEmpty)
        XCTAssertTrue(memory.plan(topology: "AB", current: [win(9, 0, 0)]).isEmpty)
    }

    func testRecordForgetsClosedWindows() {
        var memory = WindowLayoutMemory()
        memory.record(topology: "AB", windows: [win(1, 2000, 100), win(2, 100, 100)])
        memory.record(topology: "AB", windows: [win(2, 100, 100)])
        XCTAssertTrue(memory.plan(topology: "AB", current: [win(1, 0, 0)]).isEmpty)
    }

    func testOldestTopologyIsDropped() {
        var memory = WindowLayoutMemory()
        for i in 0...WindowLayoutMemory.topologyLimit { memory.record(topology: "T\(i)", windows: [win(1, CGFloat(i), 0)]) }
        XCTAssertNil(memory.layouts["T0"])
        XCTAssertNotNil(memory.layouts["T\(WindowLayoutMemory.topologyLimit)"])
    }

    func testEmptyRecordDoesNotWipeMemory() {
        var memory = WindowLayoutMemory()
        memory.record(topology: "AB", windows: [win(1, 2000, 100)])
        memory.record(topology: "AB", windows: [])
        XCTAssertEqual(memory.plan(topology: "AB", current: [win(1, 0, 0)]).count, 1)
    }
}
