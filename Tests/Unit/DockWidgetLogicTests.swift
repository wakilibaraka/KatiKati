import XCTest
@testable import KatiKati

final class DockWidgetLogicTests: XCTestCase {
    // MARK: Meeting links

    func testDetectsZoomMeetAndTeams() {
        XCTAssertEqual(MeetingLink.detect(in: ["https://acme.zoom.us/j/123?pwd=x"])?.provider, .zoom)
        XCTAssertEqual(MeetingLink.detect(in: ["Join: https://meet.google.com/abc-defg-hij."])?.provider, .googleMeet)
        XCTAssertEqual(MeetingLink.detect(in: ["https://teams.microsoft.com/l/meetup-join/19%3a"])?.provider, .teams)
        XCTAssertEqual(MeetingLink.detect(in: ["zoommtg://zoom.us/join?confno=1"])?.provider, .zoom)
    }

    func testIgnoresOrdinaryLinksAndEmptyFields() {
        XCTAssertNil(MeetingLink.detect(in: [nil, "", "https://example.com/zoom.us"]))
        XCTAssertNil(MeetingLink.detect(in: ["https://meet.google.com/landing"]))
    }

    func testFieldOrderAndEscapedNotes() {
        let link = MeetingLink.detect(in: ["Room 4", "https://meet.google.com/aaa-bbbb-ccc", "https://zoom.us/j/9"])
        XCTAssertEqual(link?.provider, .googleMeet)
        let safe = "https://safelinks.example/?url=https%3A%2F%2Fteams.microsoft.com%2Fl%2Fmeetup-join%2Fabc&amp;data=1"
        XCTAssertEqual(MeetingLink.detect(in: [safe])?.provider, .teams)
    }

    // MARK: Countdown

    func testTimeUntilRoundsUp() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func until(_ s: TimeInterval) -> EventTimeUntil { .resolve(start: now.addingTimeInterval(s), now: now) }
        XCTAssertEqual(until(1), .minutes(1))
        XCTAssertEqual(until(180), .minutes(3))
        XCTAssertEqual(until(181), .minutes(4))
        XCTAssertEqual(until(3600), .hours(1, minutes: 0))
        XCTAssertEqual(until(5400), .hours(1, minutes: 30))
        XCTAssertEqual(until(2 * 86_400), .days(2))
    }

    func testTimeUntilNowAndEnded() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(EventTimeUntil.resolve(start: now, end: now.addingTimeInterval(60), now: now), .now)
        XCTAssertEqual(EventTimeUntil.resolve(start: now.addingTimeInterval(-120), end: now, now: now), .ended)
    }

    func testJoinWindow() {
        let start = Date(timeIntervalSince1970: 1_000_000), end = start.addingTimeInterval(1800)
        XCTAssertFalse(EventTimeUntil.isJoinable(start: start, end: end, now: start.addingTimeInterval(-601)))
        XCTAssertTrue(EventTimeUntil.isJoinable(start: start, end: end, now: start.addingTimeInterval(-600)))
        XCTAssertTrue(EventTimeUntil.isJoinable(start: start, end: end, now: start.addingTimeInterval(900)))
        XCTAssertFalse(EventTimeUntil.isJoinable(start: start, end: end, now: end))
    }

    // MARK: Upcoming selection

    private func event(_ id: String, start: TimeInterval, length: TimeInterval = 1800, allDay: Bool = false, now: Date) -> DockEvent {
        DockEvent(id: id, title: id, start: now.addingTimeInterval(start), end: now.addingTimeInterval(start + length),
                  isAllDay: allDay, link: nil, location: nil, colorRGB: [0, 0, 0])
    }

    func testSelectDropsAllDayAndEndedSortsAndLimits() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let events = [
            event("late", start: 7200, now: now),
            event("past", start: -3600, now: now),
            event("allday", start: 0, length: 86_400, allDay: true, now: now),
            event("running", start: -600, now: now),
            event("soon", start: 300, now: now),
        ]
        XCTAssertEqual(UpcomingEvents.select(events, now: now, limit: 10).map(\.id), ["running", "soon", "late"])
        XCTAssertEqual(UpcomingEvents.select(events, now: now, limit: 2).map(\.id), ["running", "soon"])
    }

    // MARK: Sparkline history

    func testHistoryCapsAndPads() {
        var history = SampleHistory(capacity: 3)
        [0.1, 0.2, 0.3, 0.4].forEach { history.append($0) }
        XCTAssertEqual(history.values, [0.2, 0.3, 0.4])
        XCTAssertEqual(history.latest, 0.4)
        var young = SampleHistory(capacity: 4)
        young.append(0.5)
        XCTAssertEqual(young.normalized(ceiling: 1), [0, 0, 0, 0.5])
    }

    func testHistoryScalesToPeakAndRejectsBadValues() {
        var history = SampleHistory(capacity: 3)
        history.append(.nan)
        history.append(-4)
        history.append(50)
        XCTAssertEqual(history.values, [0, 0, 50])
        XCTAssertEqual(history.normalized(), [0, 0, 1])
        XCTAssertEqual(SampleHistory(capacity: 2).normalized(), [0, 0])
    }

    // MARK: Disk throughput

    func testDiskRate() {
        let a = DiskCounters(read: 1000, written: 5000), b = DiskCounters(read: 3000, written: 5000)
        let rate = DiskCounters.rate(from: a, to: b, seconds: 2)
        XCTAssertEqual(rate.read, 1000)
        XCTAssertEqual(rate.write, 0)
        XCTAssertEqual(DiskCounters.rate(from: b, to: a, seconds: 1).read, 0, "a counter reset reads as zero")
        XCTAssertEqual(DiskCounters.rate(from: a, to: b, seconds: 0).read, 0)
    }

    // MARK: New widgets stay opt-in

    func testNewWidgetsStartHiddenInDefaultLayout() {
        let layout = WidgetLayout.default
        for section in [BarSection.calendar, .system, .devices] {
            XCTAssertFalse(layout.instance(for: section).isVisible)
            XCTAssertTrue(section.supportsWidgetSizes)
        }
        XCTAssertEqual(layout.visibleOrder, [.launcher, .weather, .apps, .media, .clock, .widgets])
    }

    func testOldStoredLayoutGainsHiddenNewWidgets() {
        let old = WidgetLayout(instances: [.launcher, .weather, .apps, .media, .clock, .widgets].map { WidgetInstance(section: $0) })
        XCTAssertEqual(old.visibleOrder, [.launcher, .weather, .apps, .media, .clock, .widgets])
        XCTAssertEqual(Set(old.order), Set(BarSection.allCases))
    }

    func testNewPresetsAreRegistered() {
        let ids = WidgetPresets.builtIns.map(\.id)
        XCTAssertTrue(ids.contains("builtin.agenda"))
        XCTAssertTrue(ids.contains("builtin.monitor"))
    }
}

extension DockWidgetLogicTests {
    func testWidgetLookDefaultsToClassicAndRoundTrips() {
        XCTAssertEqual(WidgetLook.default, .classic)
        XCTAssertEqual(WidgetLook.allCases.map(\.rawValue), ["classic", "tiles"])
        XCTAssertEqual(WidgetLook.classic.cornerRadius, 10)
        XCTAssertEqual(WidgetLook.tiles.cornerRadius, 14)
        XCTAssertNil(WidgetLook(rawValue: "junk"))
    }

    func testSatelliteWidgetsNeverAddIslands() {
        for mode in [BarLayoutMode.split3, .split4, .split5] {
            let withAll = BarSection.islands(for: mode).count
            let without = BarSection.islands(for: mode, order: [.launcher, .weather, .apps, .media, .clock, .widgets]).count
            XCTAssertEqual(withAll, without, "\(mode)")
        }
    }
}

final class GlanceStackTests: XCTestCase {
    private let base = StackSignals(liveKind: .clock, weatherCondition: nil)
    private let members: [BarSection] = [.clock, .calendar, .system, .devices]

    private func pick(_ signals: StackSignals) -> BarSection {
        StackRelevance.resolve(members: members, signals: signals, current: nil, override: nil, now: Date())
    }

    func testQuietDayShowsTheClock() {
        XCTAssertEqual(pick(base), .clock)
    }

    func testMeetingSoonBeatsEverything() {
        var s = base; s.meetingSoon = true; s.systemBusy = true
        XCTAssertEqual(pick(s), .calendar)
    }

    func testBusySystemAndLowBatteryTakeTheSlot() {
        var busy = base; busy.systemBusy = true
        XCTAssertEqual(pick(busy), .system)
        var low = base; low.deviceLow = true
        XCTAssertEqual(pick(low), .devices)
    }

    func testPresetsRotateThroughTheClockSlotWithoutNewSlots() {
        for id in ["builtin.agenda", "builtin.monitor"] {
            let layout = WidgetPresets.builtIns.first { $0.id == id }!.layout
            XCTAssertEqual(layout.instance(for: .clock).stack?.first, .clock)
            XCTAssertTrue(layout.hiddenSections.isSuperset(of: StackRelevance.glanceMembers))
        }
    }
}
