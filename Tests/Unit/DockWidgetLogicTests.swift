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
        XCTAssertEqual(layout.visibleOrder, [.launcher, .weather, .apps, .media, .clock, .dictionary, .terminal, .widgets])
    }

    func testOldStoredLayoutGainsHiddenNewWidgets() {
        let old = WidgetLayout(instances: [.launcher, .weather, .apps, .media, .clock, .widgets].map { WidgetInstance(section: $0) })
        XCTAssertEqual(old.visibleOrder, [.launcher, .weather, .apps, .media, .clock, .widgets, .dictionary, .terminal], "Dictionary and Terminal are on by default, appended after an old layout")
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

    // MARK: - Notch Call HUD & Meeting Controls (Slice A-CallHUD)

    func testPlatformDisplayNamesAndSymbols() {
        XCTAssertEqual(MeetingCallPlatform.zoom.displayName, "Zoom")
        XCTAssertEqual(MeetingCallPlatform.googleMeet.displayName, "Google Meet")
        XCTAssertEqual(MeetingCallPlatform.teams.displayName, "Microsoft Teams")
        XCTAssertEqual(MeetingCallPlatform.faceTime.displayName, "FaceTime")
        XCTAssertEqual(MeetingCallPlatform.webex.displayName, "Webex")

        for platform in MeetingCallPlatform.allCases {
            XCTAssertFalse(platform.sfSymbol.isEmpty)
        }
    }

    func testMeetingShortcutRouting() {
        // Zoom shortcuts
        let zoomMute = NotchMeetingControlRouter.shortcut(for: .toggleMute, on: .zoom)
        XCTAssertEqual(zoomMute.label, "⌘⇧A")
        let zoomCamera = NotchMeetingControlRouter.shortcut(for: .toggleCamera, on: .zoom)
        XCTAssertEqual(zoomCamera.label, "⌘⇧V")
        let zoomEnd = NotchMeetingControlRouter.shortcut(for: .endCall, on: .zoom)
        XCTAssertEqual(zoomEnd.label, "⌘W")

        // Google Meet shortcuts
        let meetMute = NotchMeetingControlRouter.shortcut(for: .toggleMute, on: .googleMeet)
        XCTAssertEqual(meetMute.label, "⌘D")
        let meetCamera = NotchMeetingControlRouter.shortcut(for: .toggleCamera, on: .googleMeet)
        XCTAssertEqual(meetCamera.label, "⌘E")

        // Teams shortcuts
        let teamsMute = NotchMeetingControlRouter.shortcut(for: .toggleMute, on: .teams)
        XCTAssertEqual(teamsMute.label, "⌘⇧M")
        let teamsCamera = NotchMeetingControlRouter.shortcut(for: .toggleCamera, on: .teams)
        XCTAssertEqual(teamsCamera.label, "⌘⇧O")

        // FaceTime shortcuts
        let ftMute = NotchMeetingControlRouter.shortcut(for: .toggleMute, on: .faceTime)
        XCTAssertEqual(ftMute.label, "⌘⇧M")
        let ftCamera = NotchMeetingControlRouter.shortcut(for: .toggleCamera, on: .faceTime)
        XCTAssertEqual(ftCamera.label, "⌘⇧V")
    }

    func testMeetingCallStateDurationFormatting() {
        let start = Date(timeIntervalSince1970: 1000)
        let state = MeetingCallState(platform: .zoom, startTime: start)

        // 45 seconds later
        let t1 = Date(timeIntervalSince1970: 1045)
        XCTAssertEqual(state.formattedDuration(at: t1), "00:45")

        // 12 mins 34 secs later
        let t2 = Date(timeIntervalSince1970: 1000 + 12 * 60 + 34)
        XCTAssertEqual(state.formattedDuration(at: t2), "12:34")

        // 1 hour 5 mins 2 secs later
        let t3 = Date(timeIntervalSince1970: 1000 + 3600 + 5 * 60 + 2)
        XCTAssertEqual(state.formattedDuration(at: t3), "1:05:02")
    }

    func testMeetingCallStateToggles() {
        let state = MeetingCallState(platform: .faceTime, isMicMuted: false, isCameraOff: false)
        let muted = state.toggledMute()
        XCTAssertTrue(muted.isMicMuted)
        XCTAssertFalse(muted.isCameraOff)

        let camOff = muted.toggledCamera()
        XCTAssertTrue(camOff.isMicMuted)
        XCTAssertTrue(camOff.isCameraOff)

        let unmuted = camOff.toggledMute()
        XCTAssertFalse(unmuted.isMicMuted)
        XCTAssertTrue(unmuted.isCameraOff)
    }

    func testPlatformDetectionFromBundleIDs() {
        XCTAssertEqual(
            MeetingDetectionPolicy.detectPlatform(fromRunningBundleIDs: ["com.apple.finder", "us.zoom.xos"]),
            .zoom
        )
        XCTAssertEqual(
            MeetingDetectionPolicy.detectPlatform(fromRunningBundleIDs: ["com.apple.FaceTime", "com.google.Chrome"]),
            .faceTime
        )
        XCTAssertEqual(
            MeetingDetectionPolicy.detectPlatform(fromRunningBundleIDs: ["com.microsoft.teams2"]),
            .teams
        )
        XCTAssertNil(
            MeetingDetectionPolicy.detectPlatform(fromRunningBundleIDs: ["com.apple.Safari", "com.apple.calculator"])
        )
    }

    // MARK: - Slice 4.1: DockBarLayoutStyle, LumabarSurfaceThemes & Height Presets

    func testDockBarLayoutStyleAndGaps() {
        XCTAssertEqual(DockBarLayoutStyle.unifiedBar.rawValue, "unifiedBar")
        XCTAssertEqual(DockBarLayoutStyle.segmentedIslands.rawValue, "segmentedIslands")

        let style = DockBarLayoutStyle.segmentedIslands
        XCTAssertEqual(style.islandGap(), 8.0)
        XCTAssertEqual(style.islandGap(custom: 4.0), 6.0) // clamped min
        XCTAssertEqual(style.islandGap(custom: 15.0), 10.0) // clamped max
        XCTAssertEqual(style.islandGap(custom: 7.5), 7.5)
    }

    func testLumabarSurfaceThemes() {
        let themes: [LumabarSurfaceTheme] = [.obsidianBlack, .crispWhite, .liquidGlass, .iosGlass, .midnightBlue]
        XCTAssertEqual(themes.count, 5)

        for theme in themes {
            let darkTokens = theme.tokens(isDark: true)
            let lightTokens = theme.tokens(isDark: false)
            XCTAssertGreaterThanOrEqual(darkTokens.baseTint.a, 0.0)
            XCTAssertGreaterThanOrEqual(lightTokens.baseTint.a, 0.0)
        }

        XCTAssertTrue(LumabarSurfaceTheme.liquidGlass.supportsIdleFrameRestOptimization)
        XCTAssertFalse(LumabarSurfaceTheme.obsidianBlack.supportsIdleFrameRestOptimization)
        XCTAssertFalse(LumabarSurfaceTheme.crispWhite.supportsIdleFrameRestOptimization)
    }

    func testDockBarHeightPresetsAndScreenEdge() {
        XCTAssertEqual(DockBarHeightPreset.compact.points, 44.0)
        XCTAssertEqual(DockBarHeightPreset.regular.points, 54.0)
        XCTAssertEqual(DockBarHeightPreset.relaxed.points, 64.0)

        XCTAssertEqual(DockScreenEdge.bottom.rawValue, "bottom")
        XCTAssertEqual(DockScreenEdge.top.rawValue, "top")

        let bottomOffset = NotchFallbackPlan.topDockOffset(menuBarHeight: 24, screenEdge: .bottom)
        XCTAssertEqual(bottomOffset, 0)
        let topOffset = NotchFallbackPlan.topDockOffset(menuBarHeight: 24, screenEdge: .top)
        XCTAssertEqual(topOffset, 32)
    }

    // MARK: - Slice 4.4: Lumabar Signature Time, Progress & Timeline Tests

    func testDotMatrixProgressModel() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.locale = Locale(identifier: "en_US_POSIX")
        let midMonth = cal.date(from: DateComponents(year: 2026, month: 10, day: 20))!

        let monthModel = DotMatrixProgressModel(scope: .month, date: midMonth, calendar: cal, locale: Locale(identifier: "en_US_POSIX"), dotCount: 20)
        XCTAssertEqual(monthModel.totalDots, 20)
        XCTAssertGreaterThan(monthModel.percent, 0)
        XCTAssertLessThanOrEqual(monthModel.percent, 100)
        XCTAssertGreaterThan(monthModel.litDots, 0)
        XCTAssertLessThanOrEqual(monthModel.litDots, 20)
        XCTAssertTrue(monthModel.label.contains("Oct 2026"))

        let yearModel = DotMatrixProgressModel(scope: .year, date: midMonth, calendar: cal, dotCount: 20)
        XCTAssertEqual(yearModel.totalDots, 20)
        XCTAssertGreaterThan(yearModel.percent, 50)
        XCTAssertTrue(yearModel.label.contains("2026"))
    }

    func testFlipClockDigitsAndDayTimeline() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let sampleDate = cal.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 15, minute: 49, second: 0))!

        // 12-hour: 03 | 49 PM
        let d12 = FlipClockDigits(date: sampleDate, calendar: cal, is24Hour: false)
        XCTAssertEqual(d12.hourString, "03")
        XCTAssertEqual(d12.minuteString, "49")
        XCTAssertEqual(d12.amPm, "PM")
        XCTAssertEqual(d12.formattedDisplay, "03 | 49 PM")

        // 24-hour: 15 : 49
        let d24 = FlipClockDigits(date: sampleDate, calendar: cal, is24Hour: true)
        XCTAssertEqual(d24.hourString, "15")
        XCTAssertEqual(d24.minuteString, "49")
        XCTAssertEqual(d24.amPm, "")

        // Timeline Needle
        let fraction = DayTimelineBarMath.currentNeedleFraction(date: sampleDate, calendar: cal)
        XCTAssertEqual(fraction, (15.0 * 3600 + 49.0 * 60) / 86400.0, accuracy: 0.001)

        // 7-day week strip
        let week = DayTimelineBarMath.weekStripDays(around: sampleDate, calendar: cal)
        XCTAssertEqual(week.count, 7)
        XCTAssertTrue(week.contains(where: { $0.isToday }))
    }
}

/// Slice SD-1/SD-2 — the Side Deck's rail tabs, badges and keyboard selection, all pure.
final class SideDeckLogicTests: XCTestCase {
    func testNotificationsTabSitsRightAfterWindows() {
        XCTAssertEqual(SideDeckTab.allCases.map(\.rawValue),
                       ["windows", "notifications", "layouts", "emoji", "clipboard", "tendedero"])
        XCTAssertEqual(SideDeckTab.notifications.symbol, "bell.fill")
        XCTAssertEqual(SideDeckTab.notifications.title, "Notifications")
    }

    func testPlaceholdersNameWhatEachTabFilters() {
        XCTAssertEqual(SideDeckSearch.placeholder(for: .windows), "Search windows")
        XCTAssertEqual(SideDeckSearch.placeholder(for: .notifications), "Search notifications")
        XCTAssertEqual(SideDeckSearch.placeholder(for: .clipboard), "Search clipboard")
        XCTAssertEqual(SideDeckSearch.placeholder(for: .tendedero), "Search shelf")
        XCTAssertEqual(SideDeckTab.allCases.map(\.searchPlaceholder).count, SideDeckTab.allCases.count)
    }

    func testUnreadBadgeCountsOnlyUnreadRows() {
        let now = Date(timeIntervalSince1970: 1_000)
        let entries = [
            NotificationHistoryEntry(id: "1", timestamp: now, title: "A"),
            NotificationHistoryEntry(id: "2", timestamp: now, title: "B", isRead: true),
            NotificationHistoryEntry(id: "3", timestamp: now, title: "C"),
        ]
        XCTAssertEqual(SideDeckBadges.unreadNotificationCount(entries), 2)
        XCTAssertEqual(SideDeckBadges.unreadNotificationCount([]), 0)
    }

    func testDismissRemovesOneRowAndKeepsTheRest() {
        var store = NotificationHistoryStore(maxCapacity: 10)
        let now = Date(timeIntervalSince1970: 1_000)
        for i in 1...3 {
            store.append(NotificationHistoryEntry(id: "n\(i)", timestamp: now.addingTimeInterval(Double(i)), title: "N\(i)"))
        }
        store.remove(id: "n2")
        XCTAssertEqual(store.entries.map(\.id), ["n3", "n1"])
        XCTAssertEqual(store.unreadCount, 2)
    }

    func testSelectionWrapsAndClampsWhenTheListShrinks() {
        var selection = SideDeckSelection()
        selection.move(by: 1, count: 3)
        XCTAssertEqual(selection.index, 1)
        selection.move(by: 2, count: 3)
        XCTAssertEqual(selection.index, 0, "↓ past the last row wraps to the first")
        selection.move(by: -1, count: 3)
        XCTAssertEqual(selection.index, 2)
        selection.clamp(count: 1)
        XCTAssertEqual(selection.index, 0)
        selection.move(by: 1, count: 0)
        XCTAssertEqual(selection.index, 0)
    }

    // MARK: HUD density and text scale (slice OW-1)

    func testHUDDensityDefaultsToExpandedAndToggles() {
        XCTAssertEqual(WidgetHUDDensityMode.parse(nil), .expanded)
        XCTAssertEqual(WidgetHUDDensityMode.parse(""), .expanded)
        XCTAssertEqual(WidgetHUDDensityMode.parse("sideways"), .expanded)
        XCTAssertEqual(WidgetHUDDensityMode.parse("compactSingleLine"), .compactSingleLine)
        XCTAssertTrue(WidgetHUDDensityMode.compactSingleLine.isCompact)
        XCTAssertFalse(WidgetHUDDensityMode.expanded.isCompact)
        XCTAssertEqual(WidgetHUDDensityMode.expanded.toggled, .compactSingleLine)
        XCTAssertEqual(WidgetHUDDensityMode.compactSingleLine.toggled, .expanded)
    }

    func testTextScaleParsesToTheNearestStepAndRoundsSizes() {
        XCTAssertEqual(WidgetTextScale.parse(nil), .regular)
        XCTAssertEqual(WidgetTextScale.parse(0.92), .small)
        XCTAssertEqual(WidgetTextScale.parse(1.3), .large)
        XCTAssertEqual(WidgetTextScale.regular.factor, 1.0)
        XCTAssertEqual(WidgetTextScale.small.scaled(11), 10)
        XCTAssertEqual(WidgetTextScale.regular.scaled(11), 11)
        XCTAssertEqual(WidgetTextScale.large.scaled(11), 13)
    }

    // MARK: Dictionary / Terminal are modules (slice DI-1)

    func testDictionaryAndTerminalAreOneSectionEach() {
        let toolSections = BarSection.allCases.filter { DockToolDeduplication.bundleIDBySection[$0] != nil }
        XCTAssertEqual(Set(toolSections), [.dictionary, .terminal], "exactly one module per tool")
        XCTAssertEqual(BarSection.allCases.count, Set(BarSection.allCases).count)
        XCTAssertEqual(BarSection.defaultOrder.count, Set(BarSection.defaultOrder).count)
        XCTAssertEqual(WidgetLayout.default.order.count, Set(WidgetLayout.default.order).count,
                       "the settings list is a permutation: no row appears twice")
        XCTAssertEqual(Set(DockToolDeduplication.bundleIDBySection.values).count, 2,
                       "Dictionary and Terminal never name the same app")
    }

    func testVisibleModuleSuppressesItsAppIcon() {
        let both: [BarSection] = [.apps, .dictionary, .terminal]
        XCTAssertEqual(DockToolDeduplication.suppressedAppBundleIDs(enabledSections: both),
                       ["com.apple.Dictionary", "com.apple.Terminal"])
        XCTAssertEqual(DockToolDeduplication.visibleAppBundleIDs(
            ["com.apple.Terminal", "com.apple.Safari", "com.apple.Dictionary"], enabledSections: both),
            ["com.apple.Safari"], "the apps strip keeps only what has no module of its own")
        XCTAssertTrue(DockToolDeduplication.isModuleOwned("com.apple.Terminal", by: ["com.apple.Terminal"]))
        XCTAssertFalse(DockToolDeduplication.isModuleOwned(nil, by: ["com.apple.Terminal"]))
    }

    func testHiddenModuleKeepsItsAppIcon() {
        let appsOnly: [BarSection] = [.apps, .weather, .clock]
        XCTAssertTrue(DockToolDeduplication.suppressedAppBundleIDs(enabledSections: appsOnly).isEmpty)
        XCTAssertEqual(DockToolDeduplication.visibleAppBundleIDs(
            ["com.apple.Terminal", "com.apple.Dictionary"], enabledSections: appsOnly),
            ["com.apple.Terminal", "com.apple.Dictionary"])
        // .dictionary off, .terminal on: one icon returns, the other stays suppressed.
        XCTAssertEqual(DockToolDeduplication.visibleAppBundleIDs(
            ["com.apple.Terminal", "com.apple.Dictionary"], enabledSections: [.apps, .terminal]),
            ["com.apple.Dictionary"])
    }

    @MainActor
    func testModuleEyeIsTheOnlySwitchTheOldKeysStillReach() {
        let suite = "DockToolDeduplication.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = AppSettingsStore(defaults: defaults)
        XCTAssertTrue(store.showTerminalChip)
        store.setShowTerminalChip(false)
        XCTAssertFalse(store.widgetLayout.instance(for: .terminal).isVisible,
                       "the old setter writes the module, not a second flag")
        XCTAssertTrue(store.showDictionaryChip, "the other tool is untouched")
        // A pre-module hide still hides the module when no layout was ever saved.
        let legacySuite = "DockToolDeduplication.legacy.\(UUID().uuidString)"
        let legacy = UserDefaults(suiteName: legacySuite)!
        legacy.removePersistentDomain(forName: legacySuite)
        legacy.set(false, forKey: "com.katikati.showDictionaryChip")
        let migrated = AppSettingsStore(defaults: legacy)
        XCTAssertFalse(migrated.showDictionaryChip)
        XCTAssertTrue(migrated.showTerminalChip)
    }
}
