import XCTest
@testable import KatiKati

final class TaskListTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testAddTrimsAppendsAndIgnoresBlank() {
        var l = TaskList()
        XCTAssertNil(l.add(text: "  \n "))
        let a = l.add(text: "  write  ")
        l.add(text: "ship")
        XCTAssertEqual(l.items.map(\.text), ["write", "ship"])
        XCTAssertEqual(l.items.first?.id, a)
    }

    func testToggleKeepsPositionStampsDoneAtAndClearsOnUntick() {
        var l = TaskList()
        let a = l.add(text: "a")!
        l.add(text: "b")
        l.toggle(a, now: t0)
        XCTAssertEqual(l.items.map(\.text), ["a", "b"], "completing never reorders")
        XCTAssertEqual(l.items[0].doneAt, t0)
        l.toggle(a, now: t0)
        XCTAssertNil(l.items[0].doneAt)
        XCTAssertEqual(l.openCount, 2)
    }

    func testTrackingAccumulatesAndOnlyOneRuns() {
        var l = TaskList()
        let a = l.add(text: "a")!, b = l.add(text: "b")!
        l.startTracking(a, now: t0)
        XCTAssertEqual(l.items[0].elapsed(at: t0.addingTimeInterval(30)), 30, accuracy: 0.001)
        l.startTracking(b, now: t0.addingTimeInterval(60))
        XCTAssertEqual(l.runningID, b)
        XCTAssertEqual(l.items[0].trackedSeconds, 60, accuracy: 0.001, "a was closed when b started")
        l.stopTracking(b, now: t0.addingTimeInterval(100))
        XCTAssertNil(l.runningID)
        XCTAssertEqual(l.totalTracked(at: t0.addingTimeInterval(500)), 100, accuracy: 0.001)
    }

    func testCompletingStopsTrackerAndDoneTasksCannotBeTracked() {
        var l = TaskList()
        let a = l.add(text: "a")!
        l.startTracking(a, now: t0)
        l.toggle(a, now: t0.addingTimeInterval(20))
        XCTAssertNil(l.runningID)
        XCTAssertEqual(l.items[0].trackedSeconds, 20, accuracy: 0.001)
        l.startTracking(a, now: t0.addingTimeInterval(30))
        XCTAssertNil(l.runningID)
    }

    func testClearCompletedAndDelete() {
        var l = TaskList()
        let a = l.add(text: "a")!
        let b = l.add(text: "b")!
        l.toggle(a, now: t0)
        l.clearCompleted(before: t0.addingTimeInterval(1))
        XCTAssertEqual(l.items.map(\.id), [b])
        l.delete(b)
        XCTAssertTrue(l.items.isEmpty)
    }

    func testLenientDecodeAndRoundTrip() throws {
        let id = UUID()
        let old = #"{"items":[{"id":"\#(id.uuidString)","text":"old"}]}"#.data(using: .utf8)!
        let l = try JSONDecoder().decode(TaskList.self, from: old)
        XCTAssertEqual(l.items.first?.text, "old")
        XCTAssertEqual(l.items.first?.trackedSeconds, 0)
        XCTAssertEqual(try JSONDecoder().decode(TaskList.self, from: "{}".data(using: .utf8)!).items.count, 0)
        var m = TaskList()
        m.add(text: "x")
        let data = try JSONEncoder().encode(m)
        XCTAssertEqual(try JSONDecoder().decode(TaskList.self, from: data), m)
    }

    func testDurationFormat() {
        XCTAssertEqual(TaskDisplay.duration(0), "0:00")
        XCTAssertEqual(TaskDisplay.duration(247), "4:07")
        XCTAssertEqual(TaskDisplay.duration(3847.9), "1:04:07")
        XCTAssertEqual(TaskDisplay.duration(-5), "0:00")
    }

    func testStoreRoundTripAndCorruptFileMovedAside() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tasks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TasksStore(url: dir.appendingPathComponent("tasks.json"))
        XCTAssertTrue(store.load().items.isEmpty)
        var l = TaskList()
        l.add(text: "keep")
        try store.save(l)
        XCTAssertEqual(store.load(), l)
        try Data("not json".utf8).write(to: store.url)
        XCTAssertTrue(store.load().items.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url.appendingPathExtension("bak").path))
    }

    func testSmartOrderRunningDatedImportantOpenDone() {
        let cal = Calendar(identifier: .gregorian), day = { (n: Int) in cal.date(from: DateComponents(year: 2026, month: 10, day: n))! }
        let a = TaskItem(text: "a"), b = TaskItem(text: "b", important: true), c = TaskItem(text: "c", done: true, important: true)
        let d = TaskItem(text: "d", runningSince: Date()), e = TaskItem(text: "e", due: day(25)), f = TaskItem(text: "f", due: day(22))
        let g = TaskItem(text: "g", important: true, due: day(25))
        XCTAssertEqual([a, b, c, d, e, f, g].smartOrdered.map(\.text), ["d", "f", "g", "e", "b", "a", "c"])
        XCTAssertTrue([TaskItem]().smartOrdered.isEmpty)
    }

    func testSetDueStoresStartOfDayAndClears() {
        var l = TaskList(); let id = l.add(text: "x")!
        let noon = Date(timeIntervalSince1970: 1_792_000_000)
        l.setDue(id, noon)
        XCTAssertEqual(l.items[0].due, Calendar.current.startOfDay(for: noon))
        let back = try! JSONDecoder().decode(TaskList.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(back, l)
        l.setDue(id, nil)
        XCTAssertNil(l.items[0].due)
    }

    func testTaskDueStates() {
        let now = Date(timeIntervalSince1970: 1_792_000_000), cal = Calendar.current
        let day = { (n: Int) in cal.date(byAdding: .day, value: n, to: now)! }
        XCTAssertEqual([-1, 0, 1, 2].map { TaskDue(day($0), now: now) }, [.overdue, .today, .tomorrow, .later])
    }
}
