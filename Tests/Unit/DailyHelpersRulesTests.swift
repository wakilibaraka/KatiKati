import XCTest
@testable import KatiKati

// Phase 36 — pure rules for the small daily helpers.
final class DailyHelpersRulesTests: XCTestCase {
    func testCapsLockFirstReadingIsBaselineThenTransitionsFire() {
        var t = CapsLockTracker()
        XCTAssertNil(t.update(isOn: true))
        XCTAssertNil(t.update(isOn: true))
        XCTAssertEqual(t.update(isOn: false), .capsLockOff)
        XCTAssertEqual(t.update(isOn: true), .capsLockOn)
    }

    func testBatteryNudgesOnceAtEightyThenFullAndRearmOnUnplug() {
        func b(_ level: Int, plugged: Bool = true, charging: Bool = true) -> BatteryStatus {
            BatteryStatus(level: level, isCharging: charging, isPluggedIn: plugged)
        }
        var rule = BatteryNoticeRule()
        XCTAssertNil(rule.update(b(60)))                    // seed
        XCTAssertNil(rule.update(b(79)))
        XCTAssertEqual(rule.update(b(80)), .batteryHigh)
        XCTAssertNil(rule.update(b(81)))                    // once only
        XCTAssertEqual(rule.update(b(100, charging: false)), .batteryFull)
        XCTAssertNil(rule.update(b(100, charging: false)))
        XCTAssertNil(rule.update(b(90, plugged: false, charging: false)))   // unplug re-arms
        XCTAssertEqual(rule.update(b(85)), .batteryHigh)
    }

    func testBatteryLaunchAboveThresholdStaysQuiet() {
        var rule = BatteryNoticeRule()
        XCTAssertNil(rule.update(BatteryStatus(level: 90, isCharging: true, isPluggedIn: true)))
        XCTAssertNil(rule.update(BatteryStatus(level: 92, isCharging: true, isPluggedIn: true)))
    }

    func testCleaningLockDurationIsClamped() {
        XCTAssertEqual(CleaningLock.clamped(1), 10)
        XCTAssertEqual(CleaningLock.clamped(60), 60)
        XCTAssertEqual(CleaningLock.clamped(9999), 300)
    }

    /// Phase 12 safety fix: a lock whose window passed while the app was not running (crash,
    /// force-quit) must release the keyboard instead of holding it.
    func testCleaningLockResumesOnlyInsideItsWindowAndOtherwiseFailsOpen() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(CleaningLock.launchDecision(deadline: nil, now: now), .release)
        XCTAssertEqual(CleaningLock.launchDecision(deadline: now.addingTimeInterval(-0.5), now: now), .release)
        XCTAssertEqual(CleaningLock.launchDecision(deadline: now, now: now), .release)
        XCTAssertEqual(CleaningLock.launchDecision(deadline: now.addingTimeInterval(42.4), now: now), .resume(seconds: 43))
        XCTAssertEqual(CleaningLock.launchDecision(deadline: now.addingTimeInterval(300), now: now), .resume(seconds: 300))
    }

    func testEjectPolicyOffersOnlyExternalLocalEjectables() {
        XCTAssertTrue(EjectPolicy.isOffered(isEjectable: true, isInternal: false, isLocal: true, isRoot: false))
        XCTAssertFalse(EjectPolicy.isOffered(isEjectable: true, isInternal: true, isLocal: true, isRoot: false))
        XCTAssertFalse(EjectPolicy.isOffered(isEjectable: true, isInternal: false, isLocal: false, isRoot: false))
        XCTAssertFalse(EjectPolicy.isOffered(isEjectable: true, isInternal: false, isLocal: true, isRoot: true))
        XCTAssertFalse(EjectPolicy.isOffered(isEjectable: false, isInternal: false, isLocal: true, isRoot: false))
    }

    func testPrivacyDotsEmptyOnlyWhenNothingInUse() {
        XCTAssertTrue(PrivacyDots().isEmpty)
        XCTAssertFalse(PrivacyDots(camera: true).isEmpty)
        XCTAssertFalse(PrivacyDots(microphone: true).isEmpty)
    }

    func testSnippetsParseAsSnippetKindWithNewlineEscape() {
        let list = CustomCommand.parseSnippets(";sig = Best,\\nSam\n;addr = 1 Main St")
        XCTAssertEqual(list.map(\.name), [";sig", ";addr"])
        XCTAssertEqual(list[0].target, "Best,\nSam")
        XCTAssertTrue(list.allSatisfy { $0.kind == .snippet })
        XCTAssertEqual(CustomCommand.matching(";s", in: list).count, 1)
    }

    func testReminderIntervalsOnlyForWellnessKinds() {
        XCTAssertEqual(LiveNoticeKind.hydrate.reminderInterval, 3600)
        XCTAssertEqual(LiveNoticeKind.pause.reminderInterval, 3000)
        XCTAssertNil(LiveNoticeKind.capsLockOn.reminderInterval)
    }

    // MARK: - Slice 4.2: SmartDockAutomationPolicy Tests

    func testSmartDockAutomationPauseMedia() {
        let policy = SmartDockAutomationPolicy()

        // 45s until meeting with link and playing media -> pause
        XCTAssertEqual(
            policy.evaluateMeetingMediaPause(secondsUntilMeeting: 45, hasMeetingLink: true, isMediaPlaying: true),
            .pauseMedia
        )

        // 120s until meeting -> nil
        XCTAssertNil(
            policy.evaluateMeetingMediaPause(secondsUntilMeeting: 120, hasMeetingLink: true, isMediaPlaying: true)
        )

        // Media not playing -> nil
        XCTAssertNil(
            policy.evaluateMeetingMediaPause(secondsUntilMeeting: 30, hasMeetingLink: true, isMediaPlaying: false)
        )

        // No meeting link -> nil
        XCTAssertNil(
            policy.evaluateMeetingMediaPause(secondsUntilMeeting: 30, hasMeetingLink: false, isMediaPlaying: true)
        )
    }

    func testSmartDockAutomationAILimits() {
        let policy = SmartDockAutomationPolicy()

        // Below threshold -> nil
        XCTAssertNil(
            policy.evaluateAILimitThreshold(provider: "Claude", sessionPercent: 70, weeklyPercent: 50)
        )

        // Crosses 85% session -> warning
        let sessionAction = policy.evaluateAILimitThreshold(provider: "Claude", sessionPercent: 88, weeklyPercent: 50)
        XCTAssertEqual(sessionAction, .warnAILimit(provider: "Claude", percent: 88, isWeekly: false))

        // Crosses 85% weekly -> weekly warning
        let weeklyAction = policy.evaluateAILimitThreshold(provider: "Cursor", sessionPercent: 40, weeklyPercent: 92)
        XCTAssertEqual(weeklyAction, .warnAILimit(provider: "Cursor", percent: 92, isWeekly: true))

        // Reset: went from 92% to 0% -> reset notice
        let resetAction = policy.evaluateAILimitThreshold(provider: "Cursor", sessionPercent: 0, weeklyPercent: 0, previousMaxPercent: 92)
        XCTAssertEqual(resetAction, .notifyAILimitReset(provider: "Cursor"))
    }

    func testSmartDockAutomationFullscreenStepAside() {
        let policy = SmartDockAutomationPolicy()

        // Enters fullscreen while dock is showing -> hide dock
        XCTAssertEqual(
            policy.evaluateFullscreenStepAside(isFullscreen: true, isDockCurrentlyHidden: false),
            .setDockHidden(true)
        )

        // Already hidden in fullscreen -> nil
        XCTAssertNil(
            policy.evaluateFullscreenStepAside(isFullscreen: true, isDockCurrentlyHidden: true)
        )

        // Exits fullscreen while dock is hidden -> unhide dock
        XCTAssertEqual(
            policy.evaluateFullscreenStepAside(isFullscreen: false, isDockCurrentlyHidden: true),
            .setDockHidden(false)
        )
    }

    // MARK: - Slice 4.3: OpenTaskbar Inline Micro-Tiles Tests

    func testInlineTodoPillModel() {
        let emptyModel = InlineTodoPillModel(items: [])
        XCTAssertTrue(emptyModel.isEmpty)
        XCTAssertEqual(emptyModel.remainingCountBadge, "(0)")
        XCTAssertEqual(emptyModel.emptyStateText, "0 No todos — Click to add one")

        let items = [
            InlineTodoItem(id: "1", title: "Review PR", isDone: false),
            InlineTodoItem(id: "2", title: "Fix bug", isDone: true),
            InlineTodoItem(id: "3", title: "Deploy app", isDone: false),
            InlineTodoItem(id: "4", title: "Write docs", isDone: false)
        ]
        let model = InlineTodoPillModel(items: items)
        XCTAssertFalse(model.isEmpty)
        XCTAssertEqual(model.remainingCountBadge, "(3)")
        XCTAssertEqual(model.topTwoItems.count, 2)
        XCTAssertEqual(model.topTwoItems[0].title, "Review PR")
        XCTAssertEqual(model.topTwoItems[1].title, "Deploy app")
        XCTAssertEqual(model.lineText(at: 0), "☐ Review PR")
    }

    func testInlineBarSliderMath() {
        // Scrubbing right by 50pt on 100pt width from 0.5 -> 1.0
        let s1 = InlineBarSliderMath.scrubFraction(startFraction: 0.5, dragDeltaX: 50, totalWidth: 100)
        XCTAssertEqual(s1, 1.0)

        // Scrubbing left by 20pt on 100pt width from 0.7 -> 0.5
        let s2 = InlineBarSliderMath.scrubFraction(startFraction: 0.7, dragDeltaX: -20, totalWidth: 100)
        XCTAssertEqual(s2, 0.5, accuracy: 0.001)

        // Clamping bounds
        let s3 = InlineBarSliderMath.scrubFraction(startFraction: 0.2, dragDeltaX: -50, totalWidth: 100)
        XCTAssertEqual(s3, 0.0)

        XCTAssertEqual(InlineBarSliderMath.formattedPercent(0.67), "67%")
        XCTAssertEqual(InlineBarSliderMath.formattedPercent(1.0), "100%")
    }

    func testAudioDeviceCycling() {
        // 3 devices: 0, 1, 2
        XCTAssertEqual(InlineBarSliderMath.cycleAudioDeviceIndex(currentIndex: 0, totalDevices: 3, forward: true), 1)
        XCTAssertEqual(InlineBarSliderMath.cycleAudioDeviceIndex(currentIndex: 1, totalDevices: 3, forward: true), 2)
        XCTAssertEqual(InlineBarSliderMath.cycleAudioDeviceIndex(currentIndex: 2, totalDevices: 3, forward: true), 0)

        // Backward
        XCTAssertEqual(InlineBarSliderMath.cycleAudioDeviceIndex(currentIndex: 0, totalDevices: 3, forward: false), 2)
        XCTAssertEqual(InlineBarSliderMath.cycleAudioDeviceIndex(currentIndex: 2, totalDevices: 3, forward: false), 1)
    }
}

final class BreatherScheduleEngineTests: XCTestCase {

    func testSuppressionDuringCameraMicOrCall() {
        XCTAssertTrue(BreatherScheduleEngine.shouldSuppress(cameraInUse: true, microphoneInUse: false, callActive: false))
        XCTAssertTrue(BreatherScheduleEngine.shouldSuppress(cameraInUse: false, microphoneInUse: true, callActive: false))
        XCTAssertTrue(BreatherScheduleEngine.shouldSuppress(cameraInUse: false, microphoneInUse: false, callActive: true))
        XCTAssertFalse(BreatherScheduleEngine.shouldSuppress(cameraInUse: false, microphoneInUse: false, callActive: false))
    }

    func testRingsProgressionAndAllCompleted() {
        var engine = BreatherScheduleEngine(
            rings: BreatherRings(
                eyes: BreatherRingProgress(completed: 0, target: 2),
                stretch: BreatherRingProgress(completed: 0, target: 1),
                hydrate: BreatherRingProgress(completed: 0, target: 1)
            )
        )
        XCTAssertFalse(engine.rings.allCompleted)

        engine.completeActivity(.eyes)
        XCTAssertEqual(engine.rings.eyes.progress, 0.5)
        XCTAssertFalse(engine.rings.allCompleted)

        engine.completeActivity(.eyes)
        XCTAssertEqual(engine.rings.eyes.progress, 1.0)
        engine.completeActivity(.stretch)
        engine.completeActivity(.hydrate)
        XCTAssertTrue(engine.rings.allCompleted)
        XCTAssertEqual(engine.streak.count, 1)
    }

    func testStreakIncrementsAcrossConsecutiveDays() {
        var streak = BreatherStreak(count: 0, lastCompletedDate: nil)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        let day1 = cal.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 12))!
        let day2 = cal.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 14))!
        let day4 = cal.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 10))!

        streak.recordCompletion(on: day1, calendar: cal)
        XCTAssertEqual(streak.count, 1)

        // Multiple completions on the same day do not increase streak count
        streak.recordCompletion(on: day1.addingTimeInterval(3600), calendar: cal)
        XCTAssertEqual(streak.count, 1)

        // Consecutive day increments streak
        streak.recordCompletion(on: day2, calendar: cal)
        XCTAssertEqual(streak.count, 2)

        // Broken streak resets to 1
        streak.recordCompletion(on: day4, calendar: cal)
        XCTAssertEqual(streak.count, 1)
    }

    // MARK: Scratchpad (slice OW-3)

    private func scratchDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("scratchpad-\(UUID().uuidString)")
    }

    @MainActor
    func testScratchpadCountsWordsAndCharacters() {
        let doc = ScratchpadDocument(text: "two words\nand a third")
        XCTAssertEqual(doc.wordCount, 5)
        XCTAssertEqual(doc.characterCount, 21, "every character counts, the newline included")
        XCTAssertFalse(doc.isEmpty)
        XCTAssertTrue(ScratchpadDocument(text: "  \n ").isEmpty)
        XCTAssertEqual(ScratchpadStore.wordCount(in: ""), 0)
    }

    @MainActor
    func testScratchpadSavesAtomicallyAndReloads() {
        let dir = scratchDirectory()
        let store = ScratchpadStore(directory: dir)
        store.update("remember the milk")
        store.flush()
        let reloaded = ScratchpadStore(directory: dir)
        XCTAssertEqual(reloaded.document.text, "remember the milk")
        XCTAssertEqual(reloaded.document.wordCount, 3)
        XCTAssertEqual(reloaded.copyAll(), "remember the milk")
        try? FileManager.default.removeItem(at: dir)
    }

    @MainActor
    func testScratchpadClearCreatesAnEmptyFile() {
        let dir = scratchDirectory()
        let store = ScratchpadStore(directory: dir)
        store.update("draft")
        store.clear()
        XCTAssertTrue(store.document.isEmpty)
        XCTAssertEqual((try? String(contentsOf: store.fileURL, encoding: .utf8)) ?? "nil", "")
        try? FileManager.default.removeItem(at: dir)
    }

    @MainActor
    func testScratchpadDebounceWritesWithoutAnExplicitFlush() {
        let dir = scratchDirectory()
        let store = ScratchpadStore(directory: dir, delay: 0.01)
        store.update("debounced text")
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if (try? String(contentsOf: store.fileURL, encoding: .utf8)) == "debounced text" { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertEqual(try? String(contentsOf: store.fileURL, encoding: .utf8), "debounced text")
        try? FileManager.default.removeItem(at: dir)
    }
}

// MARK: - PHN-1: hydration plan, water units, pause session, wellness defaults

final class HydrationPlanTests: XCTestCase {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()

    private func day(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    func testProgressClampsAndGlassesDerive() {
        var plan = HydrationPlan(goalMillilitres: 2000, dayKey: "2026-11-22")
        XCTAssertEqual(plan.progress, 0)
        XCTAssertEqual(plan.glasses, 0)

        plan.log(750)
        XCTAssertEqual(plan.glasses, 3)
        XCTAssertEqual(plan.progress, 0.375, accuracy: 0.0001)
        XCTAssertEqual(plan.history["2026-11-22"], 750)

        plan.log(5000)
        XCTAssertEqual(plan.progress, 1, "a 5 l day draws exactly a full ring, never past it")
        XCTAssertTrue(plan.reachedGoal)
    }

    func testGoalIsClampedToAtLeastOneMillilitre() {
        XCTAssertEqual(HydrationPlan(goalMillilitres: 0).goalMillilitres, 1)
        XCTAssertEqual(HydrationPlan(goalMillilitres: -400).goalMillilitres, 1)
    }

    func testRollOverKeepsYesterdayAndRestoresTheNewDay() {
        var plan = HydrationPlan(dayKey: "2026-11-22")
        plan.log(750)
        plan.rollOver(to: "2026-11-23")
        XCTAssertEqual(plan.todayMillilitres, 0)
        XCTAssertEqual(plan.history["2026-11-22"], 750)

        // A relaunch mid-day must not lose what that day already holds.
        plan.log(250)
        var relaunched = plan
        relaunched.rollOver(to: "2026-11-23")
        XCTAssertEqual(relaunched.todayMillilitres, 250)
    }

    func testStreakCountsConsecutiveDaysAndGivesTodayGrace() {
        var plan = HydrationPlan(goalMillilitres: 1000)
        plan.history = ["2026-11-19": 1000, "2026-11-20": 1200, "2026-11-21": 1000, "2026-11-22": 100]
        XCTAssertEqual(plan.streak(today: day(22), calendar: calendar), 3, "today not met yet: count to yesterday")

        plan.history["2026-11-22"] = 1000
        XCTAssertEqual(plan.streak(today: day(22), calendar: calendar), 4)

        plan.history["2026-11-20"] = 400
        XCTAssertEqual(plan.streak(today: day(22), calendar: calendar), 2, "the run stops at the first day that missed")
    }

    func testDayKeyIsStableAndZeroPadded() {
        XCTAssertEqual(HydrationPlan.dayKey(for: day(3, hour: 1), calendar: calendar), "2026-11-03")
        XCTAssertEqual(HydrationPlan.dayKey(for: day(22), calendar: calendar), "2026-11-22")
    }

    func testSmartPauseSurfacesOnlyWhenNothingIsHappening() {
        XCTAssertEqual(HydrationPlan.surfacing(focusActive: false, cameraInUse: false, microphoneInUse: false, callActive: false), .running)
        let blockers: [(Bool, Bool, Bool, Bool)] = [(true, false, false, false), (false, true, false, false),
                                                    (false, false, true, false), (false, false, false, true)]
        for blocker in blockers {
            XCTAssertEqual(
                HydrationPlan.surfacing(focusActive: blocker.0, cameraInUse: blocker.1,
                                        microphoneInUse: blocker.2, callActive: blocker.3), .quiet)
        }
    }

    func testLast14DaysEndsTodayAndReadsTheLiveDay() {
        var plan = HydrationPlan(dayKey: "2026-11-22")
        plan.log(250)
        let rows = plan.last14Days(today: day(22), calendar: calendar)
        XCTAssertEqual(rows.count, 14)
        XCTAssertTrue(rows.last?.isToday ?? false)
        XCTAssertEqual(rows.last?.millilitres, 250)
        XCTAssertEqual(rows.first?.millilitres, 0)
    }

    func testWaterUnitsConvertAndDefaultFromTheTemperatureUnit() {
        XCTAssertEqual(WaterUnit.millilitres.amount(millilitres: 250), 250)
        XCTAssertEqual(WaterUnit.ounces.amount(millilitres: 250), 8, "250 ml is 8.45 oz, shown whole")
        XCTAssertEqual(WaterUnit.ounces.amount(millilitres: 1000), 34)
        XCTAssertEqual(WaterUnit.millilitres.label(millilitres: 500), "500 ml")
        XCTAssertEqual(WaterUnit.ounces.label(millilitres: 500), "17 oz")

        XCTAssertEqual(WaterUnit.following(.celsius), .millilitres)
        XCTAssertEqual(WaterUnit.following(.fahrenheit), .ounces)
        XCTAssertEqual(WaterUnit.resolved(raw: nil, temperature: .fahrenheit), .ounces)
        XCTAssertEqual(WaterUnit.resolved(raw: "millilitres", temperature: .fahrenheit), .millilitres)
        XCTAssertEqual(WaterUnit.resolved(raw: "nonsense", temperature: .celsius), .millilitres)
    }
}

final class PauseSessionTests: XCTestCase {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()

    func testAllThreeCategoriesShipOnWithPrompts() {
        XCTAssertEqual(PauseCategory.defaultEnabled, Set(PauseCategory.allCases))
        XCTAssertEqual(PauseSession().enabledCount, PausePrompts.all.count)
        for category in PauseCategory.allCases {
            XCTAssertFalse(PausePrompts.all.filter { $0.category == category }.isEmpty, "\(category) has no prompt")
        }
    }

    func testRotationIsDeterministicAndWraps() {
        var session = PauseSession(categories: [.eyes])
        let eyes = PausePrompts.all.filter { $0.category == .eyes }
        let first = session.nextPrompt()
        let second = session.nextPrompt()
        let third = session.nextPrompt()
        let fourth = session.nextPrompt()
        XCTAssertEqual(first?.category, .eyes)
        XCTAssertEqual(first?.id, eyes[0].id)
        XCTAssertEqual(second?.id, eyes[1].id)
        XCTAssertEqual(third?.id, eyes[2].id)
        XCTAssertEqual(fourth?.id, eyes[0].id, "a three-prompt category wraps on the fourth")
    }

    func testSkippingNeverTouchesTheStreak() {
        var session = PauseSession()
        session.complete(on: Date(timeIntervalSinceReferenceDate: 800_000_000), calendar: calendar)
        XCTAssertEqual(session.streak.count, 1)
        XCTAssertEqual(session.completedCount, 1)

        session.skip()
        session.skip()
        XCTAssertEqual(session.skippedCount, 2)
        XCTAssertEqual(session.streak.count, 1, "a skip is not a penalty")
        XCTAssertEqual(session.completedCount, 1)
    }

    func testSnoozeHoldsForItsWindowAndSurvivesARotation() {
        var session = PauseSession()
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        session.snooze(until: now.addingTimeInterval(900))
        XCTAssertTrue(session.isSnoozed(at: now))
        XCTAssertFalse(session.isSnoozed(at: now.addingTimeInterval(901)))

        _ = session.nextPrompt()
        XCTAssertTrue(session.isSnoozed(at: now), "reading the next prompt must not clear a snooze")
    }

    func testCompletingClearsTheSnoozeAndDisablingEveryCategoryLeavesNoPrompt() {
        var session = PauseSession()
        session.snooze(until: Date().addingTimeInterval(900))
        session.complete(on: Date(), calendar: calendar)
        XCTAssertFalse(session.isSnoozed(at: Date()))

        for category in PauseCategory.allCases { session.setCategory(category, enabled: false) }
        XCTAssertEqual(session.enabledCount, 0)
        XCTAssertNil(session.nextPrompt())
    }
}

final class WellnessDefaultsTests: XCTestCase {
    private func scratchDefaults() -> UserDefaults {
        UserDefaults(suiteName: "wellness-\(UUID().uuidString)")!
    }

    func testUnsetKeysReadAsOn() {
        let defaults = scratchDefaults()
        for item in WellnessDefaults.Item.allCases {
            XCTAssertTrue(WellnessDefaults.isEnabled(item, defaults: defaults), "\(item) must ship on")
        }
    }

    func testAnExplicitOffIsRespectedAndDoesNotAffectItsNeighbours() {
        let defaults = scratchDefaults()
        WellnessDefaults.set(false, for: .smartPause, defaults: defaults)
        XCTAssertFalse(WellnessDefaults.isEnabled(.smartPause, defaults: defaults))
        XCTAssertTrue(WellnessDefaults.isEnabled(.waterReminder, defaults: defaults))
        XCTAssertTrue(WellnessDefaults.isEnabled(.moveBanners, defaults: defaults))
    }

    func testKeysAreTheOnesTheServicesAlreadyWrite() {
        XCTAssertEqual(WellnessDefaults.Item.waterReminder.defaultsKey, "com.katikati.helpers.hydrate")
        XCTAssertEqual(WellnessDefaults.Item.pauseReminder.defaultsKey, "com.katikati.helpers.pause")
        XCTAssertEqual(WellnessDefaults.Item.moveBanners.defaultsKey, "com.katikati.notifications.move")
    }
}
