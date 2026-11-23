import XCTest
@testable import KatiKati

// The notch opens on a dwell, closes after a grace period, and never flickers on jitter.

final class NotchHoverMachineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func testFastPassDoesNotOpen() {
        var m = NotchHoverMachine()
        XCTAssertFalse(m.update(inTrigger: true, inKeepOpen: false, pinned: false, now: at(0)))
        XCTAssertFalse(m.update(inTrigger: true, inKeepOpen: false, pinned: false, now: at(0.02)))
        XCTAssertFalse(m.update(inTrigger: false, inKeepOpen: false, pinned: false, now: at(0.03)))
        XCTAssertNil(m.nextDeadline, "leaving cancels the pending open")
        XCTAssertFalse(m.update(inTrigger: true, inKeepOpen: false, pinned: false, now: at(0.5)), "the dwell timer restarts")
    }

    func testDwellOpens() {
        var m = NotchHoverMachine()
        _ = m.update(inTrigger: true, inKeepOpen: false, pinned: false, now: at(0))
        XCTAssertEqual(m.nextDeadline, at(0.05))
        XCTAssertTrue(m.update(inTrigger: true, inKeepOpen: false, pinned: false, now: at(0.06)))
    }

    func testCloseWaitsForGracePeriodAndReentryCancelsIt() {
        var m = NotchHoverMachine()
        m.forceOpen()
        XCTAssertTrue(m.update(inTrigger: false, inKeepOpen: false, pinned: false, now: at(0)))
        XCTAssertTrue(m.update(inTrigger: false, inKeepOpen: false, pinned: false, now: at(0.2)))
        XCTAssertTrue(m.update(inTrigger: false, inKeepOpen: true, pinned: false, now: at(0.22)), "re-entering holds it open")
        XCTAssertNil(m.nextDeadline)
        _ = m.update(inTrigger: false, inKeepOpen: false, pinned: false, now: at(1))
        XCTAssertFalse(m.update(inTrigger: false, inKeepOpen: false, pinned: false, now: at(1.25)))
    }

    func testPinnedHoldsOpenWhileCursorIsOutside() {
        var m = NotchHoverMachine()
        m.forceOpen()
        for i in 0..<10 {
            XCTAssertTrue(m.update(inTrigger: false, inKeepOpen: false, pinned: true, now: at(Double(i))))
        }
        XCTAssertTrue(m.update(inTrigger: false, inKeepOpen: false, pinned: false, now: at(10)), "grace period starts only after the pin ends")
        XCTAssertFalse(m.update(inTrigger: false, inKeepOpen: false, pinned: false, now: at(10.3)))
    }

    func testNoFlickerOnJitterAroundTheEdge() {
        var m = NotchHoverMachine()
        _ = m.update(inTrigger: true, inKeepOpen: false, pinned: false, now: at(0))
        _ = m.update(inTrigger: true, inKeepOpen: false, pinned: false, now: at(0.2))
        XCTAssertTrue(m.isOpen)
        var states: [Bool] = []
        for i in 0..<20 { // cursor wobbling in/out of the open zone every 40 ms
            let inside = i % 2 == 0
            states.append(m.update(inTrigger: false, inKeepOpen: inside, pinned: false, now: at(0.3 + Double(i) * 0.04)))
        }
        XCTAssertTrue(states.allSatisfy { $0 })
    }

    func testForceCloseAndZones() {
        var m = NotchHoverMachine()
        m.forceOpen(); m.forceClose()
        XCTAssertFalse(m.isOpen)
        let closed = CGRect(x: 800, y: 1080, width: 180, height: 32)
        XCTAssertTrue(NotchHoverZones.trigger(closedFrame: closed).contains(CGPoint(x: 890, y: 1112)), "cursor pinned to the very top edge counts")
        XCTAssertFalse(NotchHoverZones.trigger(closedFrame: closed).contains(CGPoint(x: 700, y: 1100)))
        let open = CGRect(x: 600, y: 922, width: 640, height: 190)
        XCTAssertTrue(NotchHoverZones.keepOpen(openFrame: open).contains(CGPoint(x: 595, y: 930)))
        XCTAssertFalse(NotchHoverZones.keepOpen(openFrame: open).contains(CGPoint(x: 560, y: 930)))
    }

    func testBehaviorDefaultsAndClamping() {
        let d = UserDefaults(suiteName: "NotchBehaviorTests")!
        d.removePersistentDomain(forName: "NotchBehaviorTests")
        XCTAssertEqual(NotchOpenMode.current(d), .hover)
        XCTAssertEqual(NotchBehavior.hoverDelay(d), 0.05)
        d.set(99.0, forKey: NotchBehavior.hoverDelayKey)
        d.set(0.0, forKey: NotchBehavior.closeDelayKey)
        d.set("bogus", forKey: NotchOpenMode.defaultsKey)
        XCTAssertEqual(NotchBehavior.hoverDelay(d), 1.0)
        XCTAssertEqual(NotchBehavior.closeDelay(d), 0.10)
        XCTAssertEqual(NotchOpenMode.current(d), .hover)
        XCTAssertTrue(NotchBehavior.showBatteryDuringMusic(d))
        d.set(false, forKey: NotchBehavior.musicBatteryKey)
        XCTAssertFalse(NotchBehavior.showBatteryDuringMusic(d))
    }

    func testNotchPagesNeverIncludeTheNotificationInbox() {
        let pages = NotchPage.visible()
        XCTAssertEqual(pages.count, 7, "music, calendar, and the remaining core pages are active")
        XCTAssertEqual(pages.first, .audioDeck)
        XCTAssertEqual(pages.last, .keepAwake)
        XCTAssertTrue(pages.contains(.peripherals))
        XCTAssertEqual(NotchPage.peripherals.symbol, "airpodspro")
        XCTAssertFalse(pages.map(\.symbol).contains("bell.fill"), "the inbox moved to the Side Deck (SD-1)")
        XCTAssertEqual(NotchPage.visible(teleprompter: false, mirror: false).count, 6)

        let d = UserDefaults(suiteName: "NotchPinnedPageTests")!
        d.removePersistentDomain(forName: "NotchPinnedPageTests")
        XCTAssertNil(NotchPagingPolicy.storedPinnedPage(d))
        XCTAssertFalse(NotchPage.isEnabled(TeleprompterModel.enabledKey, in: d))
        d.set(NotchPage.calendar.rawValue, forKey: NotchPagingPolicy.pinnedDefaultPageKey)
        XCTAssertEqual(NotchPagingPolicy.storedPinnedPage(d), .calendar)
        XCTAssertEqual(NotchPagingPolicy.defaultPage(nowPlayingActive: true, aiTurnActive: false, userPinnedPage: NotchPagingPolicy.storedPinnedPage(d)), .calendar)
    }

    func testRestContentSingleItemsSplitSymmetrically() {
        for preset in NotchRestContent.allCases {
            if preset == .nothing {
                XCTAssertNil(preset.left)
                XCTAssertNil(preset.right)
            } else {
                XCTAssertNotNil(preset.left, "\(preset) must populate left wing")
                XCTAssertNotNil(preset.right, "\(preset) must populate right wing")
            }
        }
        XCTAssertEqual(NotchRestContent.battery.left, .batteryIcon)
        XCTAssertEqual(NotchRestContent.battery.right, .batteryPercent)
        XCTAssertEqual(NotchRestContent.storage.left, .storageLabel)
        XCTAssertEqual(NotchRestContent.storage.right, .storage)
        XCTAssertEqual(NotchRestContent.time.left, .date)
        XCTAssertEqual(NotchRestContent.time.right, .time)
    }

    func testTimeTravelBufferRingCapAndScrubbing() {
        var buffer = NotchTimeTravelBuffer()
        XCTAssertNil(buffer.step(delta: -1))

        for index in 1...30 {
            buffer.record(NotchTimeTravelEntry(icon: "bell", title: "Event \(index)"))
        }
        XCTAssertEqual(buffer.entries.count, NotchTimeTravelBuffer.maxCapacity)
        XCTAssertEqual(buffer.entries.first?.title, "Event 6")
        XCTAssertEqual(buffer.entries.last?.title, "Event 30")
        XCTAssertNil(buffer.currentPosition)

        // First scrub enters at newest entry (Event 30).
        XCTAssertEqual(buffer.step(delta: -1)?.title, "Event 30")
        XCTAssertEqual(buffer.currentPosition?.index, 25)
        XCTAssertEqual(buffer.currentPosition?.total, 25)

        // Step backward to oldest entry and verify lower clamp.
        XCTAssertEqual(buffer.step(delta: -1)?.title, "Event 29")
        XCTAssertEqual(buffer.step(delta: -50)?.title, "Event 6")
        XCTAssertEqual(buffer.step(delta: -1)?.title, "Event 6")

        // Step forward and clamp at newest.
        XCTAssertEqual(buffer.step(delta: 2)?.title, "Event 8")
        XCTAssertEqual(buffer.step(delta: 100)?.title, "Event 30")

        buffer.resetCursor()
        XCTAssertNil(buffer.currentPosition)
    }

    func testDeferredFocusQueueHoldsNonCriticalAndFlushesSummary() {
        var queue = DeferredFocusQueue()
        let regular1 = NotchTimeTravelEntry(icon: "doc", title: "Build Finished")
        let regular2 = NotchTimeTravelEntry(icon: "tray", title: "Download Complete")
        let critical = NotchTimeTravelEntry(icon: "exclamationmark.triangle", title: "Approval Required")

        XCTAssertFalse(queue.shouldPresentImmediately(regular1, isCritical: false, isFocusActive: true))
        XCTAssertTrue(queue.shouldPresentImmediately(critical, isCritical: true, isFocusActive: true))
        XCTAssertFalse(queue.shouldPresentImmediately(regular2, isCritical: false, isFocusActive: true))
        XCTAssertEqual(queue.held.count, 2)

        let flushed = queue.flush()
        XCTAssertEqual(flushed.items.map(\.title), ["Build Finished", "Download Complete"])
        XCTAssertEqual(flushed.summary, "2 updates held while in Focus")
        XCTAssertTrue(queue.held.isEmpty)
        XCTAssertNil(queue.flush().summary)

        XCTAssertTrue(queue.shouldPresentImmediately(regular1, isCritical: false, isFocusActive: false))
    }

    func testSuggestionBackoffMutesAfterFiveDismissals() {
        var tracker = SuggestionBackoffTracker()
        let rule = "sixthSense.mcpBloat"
        XCTAssertTrue(tracker.shouldSuggest(ruleKey: rule))

        for _ in 0..<4 {
            tracker.recordDismissal(ruleKey: rule)
            XCTAssertTrue(tracker.shouldSuggest(ruleKey: rule))
        }
        tracker.recordDismissal(ruleKey: rule)
        XCTAssertFalse(tracker.shouldSuggest(ruleKey: rule))
        XCTAssertTrue(tracker.shouldSuggest(ruleKey: "sixthSense.other"))

        tracker.recordAccepted(ruleKey: rule)
        XCTAssertTrue(tracker.shouldSuggest(ruleKey: rule))

        for _ in 0..<5 { tracker.recordDismissal(ruleKey: rule) }
        XCTAssertFalse(tracker.shouldSuggest(ruleKey: rule))
        tracker.reset(ruleKey: rule)
        XCTAssertTrue(tracker.shouldSuggest(ruleKey: rule))
    }

    func testNotchDesignResolvesDisplayUUIDBeforeDisplayID() {
        let stored: [String: NotchDesign] = [
            "UUID-MONITOR-A": .wideBar,
            "42": .off,
        ]
        // UUID match takes precedence over transient display ID "42".
        XCTAssertEqual(
            NotchDesign.resolve(
                display: "42",
                displayUUID: "UUID-MONITOR-A",
                hasHardwareNotch: true,
                stored: stored
            ),
            .wideBar
        )
        // Falls back to legacy display ID when UUID isn't stored yet.
        XCTAssertEqual(
            NotchDesign.resolve(
                display: "42",
                displayUUID: "UUID-UNKNOWN",
                hasHardwareNotch: true,
                stored: stored
            ),
            .off
        )
        // Falls back to hardware notch default when neither key matches.
        XCTAssertEqual(
            NotchDesign.resolve(
                display: "99",
                displayUUID: nil,
                hasHardwareNotch: false,
                stored: stored
            ),
            .wideBar
        )
    }
}
