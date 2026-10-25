import XCTest

// Phase 59a — the battery and peripheral notification policy. The rule that matters is that these are
// *transitions*: a Mac sitting at 18 % on battery must notify once, not on every sample, and each
// milestone fires once per charge session rather than on every read above it.

final class PowerNotificationsTests: XCTestCase {
    private func snapshot(_ level: Int?, charging: Bool = false, plugged: Bool = false,
                          devices: [BluetoothDevice] = []) -> PowerNotificationPolicy.Snapshot {
        PowerNotificationPolicy.Snapshot(level: level, isCharging: charging, isPluggedIn: plugged, devices: devices)
    }

    private func events(_ old: PowerNotificationPolicy.Snapshot, _ new: PowerNotificationPolicy.Snapshot,
                        rules: PowerNotificationRules = PowerNotificationRules(),
                        fired: inout PowerNotificationPolicy.Fired) -> [PowerNotification] {
        PowerNotificationPolicy.events(from: old, to: new, rules: rules, fired: &fired)
    }

    func testLowBatteryFiresOncePerDip() {
        var fired = PowerNotificationPolicy.Fired()
        let rules = PowerNotificationRules()
        XCTAssertEqual(events(snapshot(30), snapshot(20), rules: rules, fired: &fired).map(\.kind), [.lowBattery])
        XCTAssertEqual(events(snapshot(20), snapshot(19), rules: rules, fired: &fired), [])
        XCTAssertEqual(events(snapshot(19), snapshot(18), rules: rules, fired: &fired), [])
        // Recovering above the line re-arms it.
        _ = events(snapshot(18), snapshot(30), rules: rules, fired: &fired)
        XCTAssertEqual(events(snapshot(30), snapshot(20), rules: rules, fired: &fired).map(\.kind), [.lowBattery])
    }

    func testNoLowBatteryAlertWhileChargingOrWhenTurnedOff() {
        var fired = PowerNotificationPolicy.Fired()
        // Plugging in at 19 %: the plug change is news, the low-battery alert is not.
        XCTAssertEqual(events(snapshot(30), snapshot(19, charging: true, plugged: true), fired: &fired).map(\.kind),
                       [.charging])
        // Below the threshold and still charging: neither a low alert nor a second plug event.
        XCTAssertTrue(events(snapshot(19, charging: true, plugged: true), snapshot(15, charging: true, plugged: true),
                             fired: &fired).isEmpty)
        var off = PowerNotificationRules()
        off.lowThreshold = nil
        var offFired = PowerNotificationPolicy.Fired()
        XCTAssertEqual(events(snapshot(40), snapshot(10), rules: off, fired: &offFired)
                        .filter { $0.kind == .lowBattery }, [])
    }

    func testChargeMilestonesFireOncePerSession() {
        var fired = PowerNotificationPolicy.Fired()
        let rules = PowerNotificationRules()
        _ = events(snapshot(60, charging: true, plugged: true), snapshot(61, charging: true, plugged: true),
                   rules: rules, fired: &fired)
        let midMilestone = events(snapshot(79, charging: true, plugged: true),
                                  snapshot(80, charging: true, plugged: true), rules: rules, fired: &fired)
        XCTAssertEqual(midMilestone.map(\.detail), ["80%"])
        XCTAssertEqual(midMilestone.map(\.title), ["Charge Milestone"], "80 % is not a finished charge")
        XCTAssertEqual(events(snapshot(80, charging: true, plugged: true), snapshot(85, charging: true, plugged: true),
                               rules: rules, fired: &fired), [])
        let full = events(snapshot(99, charging: true, plugged: true), snapshot(100, charging: true, plugged: true),
                          rules: rules, fired: &fired)
        XCTAssertEqual(full.map(\.detail), ["100%"])
        XCTAssertEqual(full.map(\.title), ["Battery Charged"])
        // A fresh session at 50 % may announce 80 % again.
        _ = events(snapshot(100, charging: true, plugged: true), snapshot(99, charging: false, plugged: false),
                   rules: rules, fired: &fired)
        _ = events(snapshot(50, charging: false, plugged: false), snapshot(50, charging: true, plugged: true),
                   rules: rules, fired: &fired)
        XCTAssertEqual(events(snapshot(79, charging: true, plugged: true), snapshot(80, charging: true, plugged: true),
                               rules: rules, fired: &fired).map(\.detail), ["80%"])
    }

    func testPlugChangesReportOnce() {
        var fired = PowerNotificationPolicy.Fired()
        let rules = PowerNotificationRules()
        XCTAssertEqual(events(snapshot(50), snapshot(50, charging: true, plugged: true), rules: rules, fired: &fired)
                        .map(\.kind), [.charging])
        XCTAssertEqual(events(snapshot(50, charging: true, plugged: true), snapshot(50), rules: rules, fired: &fired)
                        .map(\.kind), [.unplugged])
        var quiet = PowerNotificationRules()
        quiet.chargingChanges = false
        XCTAssertEqual(events(snapshot(50), snapshot(50, charging: true, plugged: true), rules: quiet, fired: &fired), [])
    }

    /// The plug-in everybody does: a full battery, so the Mac is not charging. Keying the alert on
    /// `isCharging` left this one — and the unplug from it — silent.
    func testPlugAndUnplugAlertAtFullCharge() {
        var fired = PowerNotificationPolicy.Fired()
        let rules = PowerNotificationRules()
        let plugged = events(snapshot(100), snapshot(100, plugged: true), rules: rules, fired: &fired)
        XCTAssertEqual(plugged.map(\.kind), [.pluggedIn], "a full battery is plugged in, not charging")
        XCTAssertEqual(plugged.first?.title, "Plugged In")
        XCTAssertEqual(plugged.first?.detail, "100%")
        XCTAssertTrue(events(snapshot(100, plugged: true), snapshot(100, plugged: true), rules: rules, fired: &fired).isEmpty,
                      "staying on power is not an event")
        let unplugged = events(snapshot(100, plugged: true), snapshot(100), rules: rules, fired: &fired)
        XCTAssertEqual(unplugged.map(\.kind), [.unplugged])
        XCTAssertEqual(unplugged.first?.detail, "100%")
    }

    func testFullChargePlugAlertsFollowTheSwitch() {
        var rules = PowerNotificationRules()
        rules.chargingChanges = false
        var fired = PowerNotificationPolicy.Fired()
        XCTAssertTrue(events(snapshot(100), snapshot(100, plugged: true), rules: rules, fired: &fired).isEmpty)
        XCTAssertTrue(events(snapshot(100, plugged: true), snapshot(100), rules: rules, fired: &fired).isEmpty)
    }

    /// Charging starting on a Mac that is already on power is not a second plug-in.
    func testChargingStartOnPowerIsNotASecondPlugAlert() {
        var fired = PowerNotificationPolicy.Fired()
        let rules = PowerNotificationRules()
        XCTAssertTrue(events(snapshot(90, plugged: true), snapshot(90, charging: true, plugged: true),
                             rules: rules, fired: &fired).isEmpty)
        XCTAssertTrue(events(snapshot(90, charging: true, plugged: true), snapshot(95, charging: true, plugged: true),
                             rules: rules, fired: &fired).isEmpty)
    }

    /// Plugging in starts a new charge session, so a milestone the last session announced can fire again.
    func testPluggingInStartsANewMilestoneSession() {
        var fired = PowerNotificationPolicy.Fired()
        fired.milestones = [80, 100]
        let rules = PowerNotificationRules()
        _ = events(snapshot(79, charging: true, plugged: true), snapshot(79), rules: rules, fired: &fired)
        _ = events(snapshot(79), snapshot(79, charging: true, plugged: true), rules: rules, fired: &fired)
        XCTAssertEqual(events(snapshot(79, charging: true, plugged: true), snapshot(80, charging: true, plugged: true),
                               rules: rules, fired: &fired).map(\.detail), ["80%"])
    }

    /// 59f: BeteriApp's fixed 25 / 10 / 5 / 1 crossings, each once per dip, one jump can cross several.
    func testExtraLowStepsFireOncePerDip() {
        var fired = PowerNotificationPolicy.Fired()
        var rules = PowerNotificationRules()
        rules.lowThreshold = nil
        rules.lowSteps = [25, 10, 5, 1]
        XCTAssertEqual(events(snapshot(30), snapshot(25), rules: rules, fired: &fired).map(\.detail), ["25%"])
        XCTAssertEqual(events(snapshot(25), snapshot(24), rules: rules, fired: &fired), [])
        XCTAssertEqual(events(snapshot(24), snapshot(10), rules: rules, fired: &fired).map(\.detail), ["10%"])
        XCTAssertEqual(events(snapshot(10), snapshot(0), rules: rules, fired: &fired).map(\.detail), ["5%", "1%"])
        XCTAssertEqual(events(snapshot(0), snapshot(0), rules: rules, fired: &fired), [])
        // Back above every step re-arms them; a step that is switched off never fires.
        _ = events(snapshot(0), snapshot(30), rules: rules, fired: &fired)
        XCTAssertEqual(events(snapshot(30), snapshot(25), rules: rules, fired: &fired).map(\.detail), ["25%"])
        rules.lowSteps = [10]
        XCTAssertEqual(events(snapshot(30), snapshot(20), rules: rules, fired: &fired), [])
    }

    func testPeripheralsConnectDisconnectAndWarnOncePerFall() {
        var fired = PowerNotificationPolicy.Fired()
        let rules = PowerNotificationRules()
        let mouse = BluetoothDevice(name: "Mouse", address: "AA:01", isConnected: true, batteryMain: 15)
        let keyboard = BluetoothDevice(name: "Keyboard", address: "AA:02", isConnected: true, batteryMain: 90)

        let arrival = events(snapshot(80), snapshot(80, devices: [mouse, keyboard]), rules: rules, fired: &fired)
        XCTAssertEqual(arrival.filter { $0.kind == .peripheralConnected }.map(\.title), ["Keyboard", "Mouse"])
        XCTAssertEqual(arrival.filter { $0.kind == .peripheralLowBattery }.map(\.title), ["Mouse"])

        XCTAssertEqual(events(snapshot(80, devices: [mouse, keyboard]), snapshot(80, devices: [mouse, keyboard]),
                               rules: rules, fired: &fired), [])

        let departure = events(snapshot(80, devices: [mouse, keyboard]), snapshot(80, devices: [keyboard]),
                               rules: rules, fired: &fired)
        XCTAssertEqual(departure.map(\.kind), [.peripheralDisconnected])
        XCTAssertEqual(departure.first?.title, "Mouse")

        // Back above the line and down again: the warning is re-armed.
        var charged = mouse; charged.batteryMain = 60
        _ = events(snapshot(80, devices: [keyboard]), snapshot(80, devices: [charged]), rules: rules, fired: &fired)
        var low = charged; low.batteryMain = 10
        XCTAssertEqual(events(snapshot(80, devices: [charged]), snapshot(80, devices: [low]), rules: rules, fired: &fired)
                        .map(\.kind), [.peripheralLowBattery])
    }

    func testPeripheralAlertsCanBeTurnedOff() {
        var fired = PowerNotificationPolicy.Fired()
        var rules = PowerNotificationRules()
        rules.peripheralAlerts = false
        let mouse = BluetoothDevice(name: "Mouse", address: "AA:01", isConnected: true, batteryMain: 10)
        XCTAssertEqual(events(snapshot(80), snapshot(80, devices: [mouse]), rules: rules, fired: &fired), [])
    }

    func testHistoryPrunesToTheWindowAndKeepsNewestFirst() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let old = PowerNotification(kind: .lowBattery, title: "Old", date: now.addingTimeInterval(-25 * 3600))
        let fresh = PowerNotification(kind: .charging, title: "Fresh", date: now.addingTimeInterval(-3600))
        let kept = PowerNotificationHistory.prune([old, fresh], now: now, retentionHours: 24)
        XCTAssertEqual(kept.map(\.title), ["Fresh"])
        XCTAssertEqual(PowerNotificationHistory.prune([old, fresh], now: now, retentionHours: 24 * 7).map(\.title),
                       ["Fresh", "Old"])
        let appended = PowerNotificationHistory.appending(
            PowerNotification(kind: .charged, title: "New", date: now), to: [fresh], now: now, retentionHours: 24)
        XCTAssertEqual(appended.map(\.title), ["New", "Fresh"])
    }

    /// The history is bounded as well as aged: a long session on a charger must not grow the stored
    /// list without end (59b's cap).
    func testHistoryKeepsAtMostItsCap() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let many = (0..<(PowerNotificationHistory.cap + 25)).map { offset in
            PowerNotification(kind: .charging, title: "N\(offset)",
                              date: now.addingTimeInterval(-Double(offset)))
        }
        let kept = PowerNotificationHistory.prune(many, now: now, retentionHours: 24 * 7)
        XCTAssertEqual(kept.count, PowerNotificationHistory.cap)
        XCTAssertEqual(kept.first?.title, "N0", "newest first")
        XCTAssertEqual(kept.last?.title, "N\(PowerNotificationHistory.cap - 1)", "the oldest are dropped")
    }

    func testRulesSurviveARoundTrip() {
        let defaults = UserDefaults(suiteName: "PowerNotificationsTests")!
        defaults.removePersistentDomain(forName: "PowerNotificationsTests")
        var rules = PowerNotificationRules()
        rules.lowThreshold = nil
        rules.chargeMilestones = [100]
        rules.peripheralAlerts = false
        rules.lowSteps = [25, 1]
        rules.soundEnabled = true
        rules.style = .banner
        rules.retentionHours = 24 * 7
        rules.save(defaults)
        let loaded = PowerNotificationRules.load(defaults)
        XCTAssertEqual(loaded, rules)
        defaults.removePersistentDomain(forName: "PowerNotificationsTests")
    }
}
