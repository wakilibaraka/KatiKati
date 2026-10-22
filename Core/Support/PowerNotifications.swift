import Foundation

// Phase 59a — battery and peripheral notifications: what fires, when, and what the history keeps.
//
// Pure values and pure rules, no AppKit: the firing policy and the retention are unit-tested, and the
// app layer (`PowerNotificationCenter`) only feeds them snapshots and shows what they return.
//
// The rules are the ones BeteriApp (BatteryBoi fork) ships in its settings: a low-battery threshold,
// a charge milestone (its 80 % "optimize charging" and a full 100 %), plus peripheral alerts. Unlike
// BeteriApp they are *transitions*, not states: a notification fires when the reading crosses a line,
// never while it sits on one — which is what stops a 20 % battery from notifying every sample.

/// What happened. The pill and the history both read this to pick an icon.
enum PowerNotificationKind: String, Codable, Sendable {
    case lowBattery, charged, charging, pluggedIn, unplugged
    case peripheralConnected, peripheralDisconnected, peripheralLowBattery

    var symbol: String {
        switch self {
        case .lowBattery, .peripheralLowBattery: return "battery.25"
        case .charged: return "battery.100.bolt"
        case .charging: return "bolt.fill"
        // Power arrived but the battery is full, so nothing is flowing: macOS shows a plug here too.
        case .pluggedIn, .unplugged: return "powerplug"
        case .peripheralConnected, .peripheralDisconnected: return "dot.radiowaves.left.and.right"
        }
    }
}

/// One notification: a title already localized at the moment it fired (the history keeps the words the
/// user actually saw), a detail line, and when it happened.
struct PowerNotification: Codable, Equatable, Identifiable, Sendable {
    var kind: PowerNotificationKind
    var title: String
    var detail: String?
    var date: Date

    var id: String { "\(kind.rawValue)|\(title)|\(date.timeIntervalSince1970)" }
}

/// The thresholds and switches, persisted beside the app's other defaults.
struct PowerNotificationRules: Equatable {
    enum Storage {
        static let lowThreshold = "com.katikati.notifications.lowThreshold"
        static let milestones = "com.katikati.notifications.milestones"
        static let chargingChanges = "com.katikati.notifications.chargingChanges"
        static let peripheralAlerts = "com.katikati.notifications.peripheralAlerts"
        static let retentionHours = "com.katikati.notifications.retentionHours"
        static let history = "com.katikati.notifications.history"
    }

    /// nil = the low-battery alert is off. BeteriApp's picker, 10…50.
    var lowThreshold: Int? = 20
    /// Percentages that fire once per charge session. Empty = off.
    var chargeMilestones: Set<Int> = [80, 100]
    /// Plugged in / unplugged while the battery moves.
    var chargingChanges = true
    /// Peripherals arriving, leaving, and falling under 20 %.
    var peripheralAlerts = true
    /// Hours the history keeps. The two choices the settings page offers: 24 and 7 × 24.
    var retentionHours = 24

    static let lowThresholdChoices = [10, 15, 20, 25, 30, 40, 50]
    static let retentionChoices = [24, 24 * 7]

    static func load(_ defaults: UserDefaults = .standard) -> PowerNotificationRules {
        var rules = PowerNotificationRules()
        // A user who has never opened the page keeps the defaults; `object(forKey:)` is what tells
        // "unset" from "0" (0 = off).
        if let raw = defaults.object(forKey: Storage.lowThreshold) as? Int {
            rules.lowThreshold = raw == 0 ? nil : min(50, max(5, raw))
        }
        if let raw = defaults.string(forKey: Storage.milestones) {
            rules.chargeMilestones = Set(raw.split(separator: ",").compactMap { Int($0) }.filter { (1...100).contains($0) })
        }
        if defaults.object(forKey: Storage.chargingChanges) != nil {
            rules.chargingChanges = defaults.bool(forKey: Storage.chargingChanges)
        }
        if defaults.object(forKey: Storage.peripheralAlerts) != nil {
            rules.peripheralAlerts = defaults.bool(forKey: Storage.peripheralAlerts)
        }
        let hours = defaults.integer(forKey: Storage.retentionHours)
        if retentionChoices.contains(hours) { rules.retentionHours = hours }
        return rules
    }

    func save(_ defaults: UserDefaults = .standard) {
        defaults.set(lowThreshold ?? 0, forKey: Storage.lowThreshold)
        defaults.set(chargeMilestones.sorted().map(String.init).joined(separator: ","), forKey: Storage.milestones)
        defaults.set(chargingChanges, forKey: Storage.chargingChanges)
        defaults.set(peripheralAlerts, forKey: Storage.peripheralAlerts)
        defaults.set(retentionHours, forKey: Storage.retentionHours)
    }
}

/// The last reading the policy saw, and what it has already told the user this cycle.
enum PowerNotificationPolicy {
    struct Snapshot: Equatable {
        var level: Int?
        var isCharging: Bool
        var isPluggedIn: Bool
        var devices: [BluetoothDevice]

        init(level: Int?, isCharging: Bool, isPluggedIn: Bool, devices: [BluetoothDevice]) {
            self.level = level
            self.isCharging = isCharging
            self.isPluggedIn = isPluggedIn
            self.devices = devices
        }
    }

    /// Carried between evaluations: one charge session fires each milestone once, one dip fires the
    /// low-battery alert once, and a peripheral warns once per fall.
    struct Fired: Equatable {
        var low = false
        var milestones: Set<Int> = []
        var lowPeripherals: Set<String> = []
    }

    static let peripheralLowLevel = 20

    /// Events for the move from `old` to `new`. Ordered most-urgent first: low battery, then a
    /// milestone, then the plug state, then peripherals.
    static func events(from old: Snapshot, to new: Snapshot, rules: PowerNotificationRules,
                       fired: inout Fired, now: Date = Date()) -> [PowerNotification] {
        var events: [PowerNotification] = []
        let level = new.level

        if let oldLevel = old.level, let level {
            // A charge session starts when power arrives, or when a Mac already on power starts
            // charging; each milestone is announced once per session.
            if (!old.isPluggedIn && new.isPluggedIn) || (!old.isCharging && new.isCharging) {
                fired.milestones = []
            }

            if let threshold = rules.lowThreshold {
                if new.isCharging || level > threshold { fired.low = false }
                if !new.isCharging, oldLevel > threshold, level <= threshold, !fired.low {
                    fired.low = true
                    events.append(PowerNotification(kind: .lowBattery,
                                                    title: String(localized: "Battery Low"),
                                                    detail: "\(level)%", date: now))
                }
            }

            if new.isCharging {
                for milestone in rules.chargeMilestones.sorted()
                where oldLevel < milestone && level >= milestone && !fired.milestones.contains(milestone) {
                    fired.milestones.insert(milestone)
                    events.append(PowerNotification(kind: .charged,
                                                    title: level >= 100 ? String(localized: "Battery Charged")
                                                                        : String(localized: "Battery Charged"),
                                                    detail: "\(milestone)%", date: now))
                }
            }
        }

        // Keyed on the power source, not on charging: a Mac plugged in at 100 % is not charging, and
        // that plug-in is the most common one there is. "Charging" while current flows, "Plugged In"
        // when the battery is already full.
        if rules.chargingChanges, old.isPluggedIn != new.isPluggedIn {
            if new.isPluggedIn {
                events.append(PowerNotification(kind: new.isCharging ? .charging : .pluggedIn,
                                                title: new.isCharging ? String(localized: "Charging")
                                                                      : String(localized: "Plugged In"),
                                                detail: level.map { "\($0)%" }, date: now))
            } else {
                events.append(PowerNotification(kind: .unplugged, title: String(localized: "Unplugged"),
                                                detail: level.map { "\($0)%" }, date: now))
            }
        }

        if rules.peripheralAlerts {
            let oldByID = Dictionary(old.devices.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let newByID = Dictionary(new.devices.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for (id, device) in newByID.sorted(by: { $0.value.name < $1.value.name }) {
                if oldByID[id] == nil {
                    events.append(PowerNotification(kind: .peripheralConnected, title: device.name,
                                                    detail: String(localized: "Connected"),
                                                    date: now))
                }
                if let charge = device.lowestBattery, charge <= peripheralLowLevel, !fired.lowPeripherals.contains(id) {
                    fired.lowPeripherals.insert(id)
                    events.append(PowerNotification(kind: .peripheralLowBattery, title: device.name,
                                                    detail: "\(String(localized: "Low Battery")) · \(charge)%",
                                                    date: now))
                }
                if let charge = device.lowestBattery, charge > peripheralLowLevel { fired.lowPeripherals.remove(id) }
            }
            for (id, device) in oldByID where newByID[id] == nil {
                fired.lowPeripherals.remove(id)
                events.append(PowerNotification(kind: .peripheralDisconnected, title: device.name,
                                                detail: String(localized: "Disconnected"),
                                                date: now))
            }
        }

        return events
    }
}

/// The stored history: newest first, pruned to the chosen window and a hard cap.
enum PowerNotificationHistory {
    static let cap = 200

    static func prune(_ list: [PowerNotification], now: Date = Date(), retentionHours: Int) -> [PowerNotification] {
        let cutoff = now.addingTimeInterval(-Double(max(1, retentionHours)) * 3600)
        return Array(list.filter { $0.date > cutoff }.sorted { $0.date > $1.date }.prefix(cap))
    }

    static func load(_ defaults: UserDefaults = .standard) -> [PowerNotification] {
        guard let data = defaults.data(forKey: PowerNotificationRules.Storage.history) else { return [] }
        return (try? JSONDecoder().decode([PowerNotification].self, from: data)) ?? []
    }

    static func save(_ list: [PowerNotification], _ defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        defaults.set(data, forKey: PowerNotificationRules.Storage.history)
    }

    static func appending(_ notification: PowerNotification, to list: [PowerNotification],
                          now: Date = Date(), retentionHours: Int) -> [PowerNotification] {
        prune([notification] + list, now: now, retentionHours: retentionHours)
    }
}
