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
}
