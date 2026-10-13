import XCTest
@testable import KatiKati

final class StackRelevanceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private func pick(_ live: LiveActivityKind = .clock, _ wx: WeatherCondition? = .clear,
                      current: BarSection? = nil, override: StackOverride? = nil) -> BarSection {
        StackRelevance.resolve(members: StackRelevance.defaultMembers, signals: StackSignals(liveKind: live, weatherCondition: wx),
                               current: current, override: override, now: now)
    }

    func testIdleShowsClockLiveMusicShowsMediaRainShowsWeather() {
        XCTAssertEqual(pick(), .clock)
        XCTAssertEqual(pick(.music), .media)
        XCTAssertEqual(pick(.timer), .media)
        XCTAssertEqual(pick(.clock, .rain), .weather)
        XCTAssertEqual(pick(.music, .rain), .media, "a live activity outranks wet weather")
    }

    func testHysteresisKeepsCurrentWithinMarginAndSwitchesBeyondIt() {
        // idle: weather 10 vs clock 20 — weather is not even best, clock stays
        XCTAssertEqual(pick(current: .weather), .weather, "10 + 15 ≥ 20: keep weather")
        XCTAssertEqual(pick(.music, current: .clock), .media, "100 beats 20 + 15")
        XCTAssertEqual(pick(.clock, .rain, current: .clock), .weather, "80 beats 20 + 15")
    }

    func testOverrideWinsUntilExpiryAndOnlyForMembers() {
        let active = StackOverride(member: .weather, until: now.addingTimeInterval(60))
        XCTAssertEqual(pick(.music, override: active), .weather)
        let expired = StackOverride(member: .weather, until: now.addingTimeInterval(-1))
        XCTAssertEqual(pick(.music, override: expired), .media)
        let foreign = StackOverride(member: .launcher, until: now.addingTimeInterval(60))
        XCTAssertEqual(pick(override: foreign), .clock)
    }

    func testTieGoesToEarlierMemberAndNextWraps() {
        let r = StackRelevance.resolve(members: [.launcher, .apps], signals: StackSignals(liveKind: .clock, weatherCondition: nil),
                                       current: nil, override: nil, now: now)
        XCTAssertEqual(r, .launcher)
        XCTAssertEqual(StackRelevance.next(after: .clock, in: StackRelevance.defaultMembers), .weather)
        XCTAssertEqual(StackRelevance.next(after: .weather, in: StackRelevance.defaultMembers), .media)
        XCTAssertEqual(StackRelevance.resolve(members: [], signals: StackSignals(liveKind: .clock, weatherCondition: nil),
                                              current: nil, override: nil, now: now), .clock)
    }

    func testStackSurvivesLayoutJSONRoundTripAndOldBlobsDecode() throws {
        var layout = WidgetLayout.default
        layout = layout.updating(.weather) { $0.stack = StackRelevance.defaultMembers }
        XCTAssertEqual(WidgetLayout.decode(layout.encoded())?.instance(for: .weather).stack, StackRelevance.defaultMembers)
        let old = Data(#"{"instances":[{"section":"clock","size":"large","isVisible":true}]}"#.utf8)
        XCTAssertNil(WidgetLayout.decode(old)?.instance(for: .clock).stack)
        XCTAssertEqual(WidgetLayout.decode(old)?.instance(for: .clock).size, .large)
    }
}

final class ContextPresetRulesTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private func date(_ weekdayOffset: Int, _ h: Int, _ m: Int) -> Date {
        // 2026-10-12 is a Monday.
        cal.date(from: DateComponents(year: 2026, month: 10, day: 12 + weekdayOffset, hour: h, minute: m))!
    }
    private let rules = [ContextPresetRules.workRule(presetID: "builtin.minimal"), ContextPresetRules.eveningRule(presetID: "builtin.music")]

    func testWorkHoursWeekdaysOnlyAndHalfOpenEnd() {
        XCTAssertEqual(ContextPresetRules.matchingPresetID(rules: rules, at: date(0, 9, 0), calendar: cal), "builtin.minimal")
        XCTAssertNil(ContextPresetRules.matchingPresetID(rules: rules, at: date(0, 8, 59), calendar: cal))
        XCTAssertNil(ContextPresetRules.matchingPresetID(rules: rules, at: date(0, 17, 0), calendar: cal), "end is exclusive")
        XCTAssertNil(ContextPresetRules.matchingPresetID(rules: rules, at: date(5, 10, 0), calendar: cal), "Saturday")
    }

    func testEveningEveryDayAndMidnightWrap() {
        XCTAssertEqual(ContextPresetRules.matchingPresetID(rules: rules, at: date(6, 20, 0), calendar: cal), "builtin.music")
        let night = [ContextPresetRule(presetID: "p", startMinute: 22 * 60, endMinute: 6 * 60, weekdays: ContextPresetRules.allWeekdays)]
        XCTAssertEqual(ContextPresetRules.matchingPresetID(rules: night, at: date(0, 23, 30), calendar: cal), "p")
        XCTAssertEqual(ContextPresetRules.matchingPresetID(rules: night, at: date(0, 2, 0), calendar: cal), "p")
        XCTAssertNil(ContextPresetRules.matchingPresetID(rules: night, at: date(0, 12, 0), calendar: cal))
    }

    func testApplyOnlyWhenMatchChangesAndTimerIsMinuteAligned() {
        XCTAssertEqual(ContextPresetRules.presetToApply(matched: "a", lastApplied: nil), "a")
        XCTAssertNil(ContextPresetRules.presetToApply(matched: "a", lastApplied: "a"))
        XCTAssertNil(ContextPresetRules.presetToApply(matched: nil, lastApplied: "a"))
        let t = date(0, 10, 0).addingTimeInterval(45)
        XCTAssertEqual(ContextPresetRules.secondsToNextMinute(from: t, calendar: cal), 15, accuracy: 0.001)
    }
}
