import AppKit
import EventKit
import SwiftUI
import UserNotifications

// Phase 5e-D/E/F — the live state behind the floating calendar panel: EventKit agenda +
// reminders, user-picked world clocks, the focus timer and alarms (with local notifications).
// Pure rules live in `Core/Support/CalendarPanelModels.swift`.

struct AgendaEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
    static func == (a: AgendaEvent, b: AgendaEvent) -> Bool { a.id == b.id && a.start == b.start && a.title == b.title }
}

struct ReminderEntry: Identifiable, Equatable {
    let id: String
    let title: String
    let due: Date?
}

enum CalendarAccess: Equatable { case unknown, granted, denied }

@MainActor
final class CalendarService: ObservableObject {
    @Published private(set) var eventsAccess: CalendarAccess = .unknown
    @Published private(set) var remindersAccess: CalendarAccess = .unknown
    @Published private(set) var events: [AgendaEvent] = []
    @Published private(set) var reminders: [ReminderEntry] = []
    /// Day-of-month → event count for the displayed month (heat tint on the grid).
    @Published private(set) var monthDensity: [Int: Int] = [:]
    @Published var selectedDate = Date() { didSet { refreshAgenda() } }
    @Published var displayedMonth = Date() { didSet { refreshDensity() } }

    private let store = EKEventStore()
    private let calendar = Calendar.current
    private var observer: NSObjectProtocol?
    /// A second request while one is in flight wedges the TCC alert on screen (the pane and the
    /// edge flyout both call `start()` on appear), so concurrent requests collapse into one.
    private var isRequestingEvents = false
    private var isRequestingReminders = false

    init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshAll() }
        }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    func start() {
        requestEvents()
        requestReminders()
    }

    private func requestEvents() {
        // Never re-prompt a decided status: asking again while the alert is up is what sticks it.
        if #available(macOS 14.0, *) {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess:
                eventsAccess = .granted; refreshAgenda(); refreshDensity(); return
            case .notDetermined:
                break
            case .denied, .restricted, .writeOnly:
                eventsAccess = .denied; refreshAgenda(); refreshDensity(); return
            @unknown default:
                eventsAccess = .denied; refreshAgenda(); refreshDensity(); return
            }
        } else if EKEventStore.authorizationStatus(for: .event) == .authorized {
            eventsAccess = .granted; refreshAgenda(); refreshDensity(); return
        } else if EKEventStore.authorizationStatus(for: .event) != .notDetermined {
            eventsAccess = .denied; refreshAgenda(); refreshDensity(); return
        }
        guard !isRequestingEvents else { return }
        isRequestingEvents = true
        let done: (Bool) -> Void = { [weak self] ok in
            Task { @MainActor in
                guard let self else { return }
                self.isRequestingEvents = false
                self.eventsAccess = ok ? .granted : .denied
                self.refreshAgenda(); self.refreshDensity()
            }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { ok, _ in done(ok) }
        } else {
            store.requestAccess(to: .event) { ok, _ in done(ok) }
        }
    }

    private func requestReminders() {
        if #available(macOS 14.0, *) {
            switch EKEventStore.authorizationStatus(for: .reminder) {
            case .fullAccess:
                remindersAccess = .granted; refreshReminders(); return
            case .notDetermined:
                break
            case .denied, .restricted, .writeOnly:
                remindersAccess = .denied; refreshReminders(); return
            @unknown default:
                remindersAccess = .denied; refreshReminders(); return
            }
        } else if EKEventStore.authorizationStatus(for: .reminder) == .authorized {
            remindersAccess = .granted; refreshReminders(); return
        } else if EKEventStore.authorizationStatus(for: .reminder) != .notDetermined {
            remindersAccess = .denied; refreshReminders(); return
        }
        guard !isRequestingReminders else { return }
        isRequestingReminders = true
        let done: (Bool) -> Void = { [weak self] ok in
            Task { @MainActor in
                guard let self else { return }
                self.isRequestingReminders = false
                self.remindersAccess = ok ? .granted : .denied
                self.refreshReminders()
            }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToReminders { ok, _ in done(ok) }
        } else {
            store.requestAccess(to: .reminder) { ok, _ in done(ok) }
        }
    }

    func refreshAll() { refreshAgenda(); refreshDensity(); refreshReminders() }

    /// Phase 30i: events whose title matches `query` over the next `days` (empty when not granted).
    func searchEvents(_ query: String, days: Int = 365, limit: Int = 30) -> [EventEntry] {
        guard eventsAccess == .granted else { return [] }
        let start = Date()
        guard let end = calendar.date(byAdding: .day, value: days, to: start) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let needle = query.lowercased()
        return store.events(matching: predicate)
            .filter { needle.isEmpty || ($0.title ?? "").lowercased().contains(needle) }
            .sorted { $0.startDate < $1.startDate }
            .prefix(limit)
            .map { EventEntry(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "", start: $0.startDate, allDay: $0.isAllDay) }
    }

    func refreshAgenda() {
        guard eventsAccess == .granted else { events = []; return }
        let day = calendar.startOfDay(for: selectedDate)
        let end = calendar.date(byAdding: .day, value: 1, to: day)!
        events = store.events(matching: store.predicateForEvents(withStart: day, end: end, calendars: nil))
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate ?? day) < ($1.isAllDay ? 0 : 1, $1.startDate ?? day) }
            .map { e in
                AgendaEvent(
                    id: e.eventIdentifier ?? UUID().uuidString, title: e.title ?? "",
                    start: e.startDate, end: e.endDate, isAllDay: e.isAllDay,
                    color: Color(nsColor: e.calendar.color ?? .systemBlue)
                )
            }
    }

    func refreshDensity() {
        guard eventsAccess == .granted,
              let interval = calendar.dateInterval(of: .month, for: displayedMonth) else { monthDensity = [:]; return }
        var density: [Int: Int] = [:]
        for e in store.events(matching: store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)) {
            density[calendar.component(.day, from: e.startDate), default: 0] += 1
        }
        monthDensity = density
    }

    func refreshReminders() {
        guard remindersAccess == .granted else { reminders = []; return }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] found in
            let entries = (found ?? []).map { r in
                ReminderEntry(id: r.calendarItemIdentifier, title: r.title ?? "", due: r.dueDateComponents?.date)
            }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
            Task { @MainActor in self?.reminders = entries }
        }
    }

    func complete(_ reminder: ReminderEntry) {
        guard let item = store.calendarItem(withIdentifier: reminder.id) as? EKReminder else { return }
        item.isCompleted = true
        try? store.save(item, commit: true)
        reminders.removeAll { $0.id == reminder.id }
    }
}

// MARK: - World clocks

@MainActor
final class WorldClockStore: ObservableObject {
    static let defaultsKey = "com.katikati.calendar.timezones"
    @Published private(set) var identifiers: [String]

    init() {
        identifiers = UserDefaults.standard.stringArray(forKey: Self.defaultsKey)
            .map { Array($0.filter { TimeZone(identifier: $0) != nil }.prefix(WorldClockModel.maxClocks)) }
            ?? Array(WorldClockModel.defaultIdentifiers.prefix(WorldClockModel.maxClocks))
    }

    func add(_ identifier: String) { set(WorldClockModel.adding(identifier, to: identifiers)) }
    func remove(_ identifier: String) { set(identifiers.filter { $0 != identifier }) }

    private func set(_ new: [String]) {
        identifiers = new
        UserDefaults.standard.set(new, forKey: Self.defaultsKey)
    }
}

// MARK: - Focus

@MainActor
final class FocusTimerController: ObservableObject {
    @Published private(set) var model = FocusTimerModel()
    private var timer: Timer?

    func toggle() { model.toggle(); syncTimer() }
    func reset() { model.reset(); syncTimer() }
    func skip() { model.skip(); syncTimer() }

    private func syncTimer() {
        timer?.invalidate(); timer = nil
        guard model.isRunning else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.model.tick() { NSSound(named: "Glass")?.play() }
                self.objectWillChange.send()
            }
        }
    }

    deinit { timer?.invalidate() }
}

// MARK: - Alarms

@MainActor
final class AlarmStore: ObservableObject {
    static let defaultsKey = "com.katikati.calendar.alarms"
    nonisolated private static let requestPrefix = "com.katikati.alarm."
    @Published private(set) var alarms: [AlarmItem]
    private var fallbackTimer: Timer?

    init() {
        let data = UserDefaults.standard.data(forKey: Self.defaultsKey)
        alarms = data.flatMap { try? JSONDecoder().decode([AlarmItem].self, from: $0) } ?? []
        reschedule()
    }

    func add(hour: Int, minute: Int, label: String = "") {
        alarms = AlarmList.sorted(alarms + [AlarmItem(hour: hour, minute: minute, label: label)])
        persist()
    }

    func setEnabled(_ enabled: Bool, for id: UUID) {
        guard let i = alarms.firstIndex(where: { $0.id == id }) else { return }
        alarms[i].isEnabled = enabled
        persist()
    }

    func remove(_ id: UUID) { alarms.removeAll { $0.id == id }; persist() }

    private func persist() {
        if let data = try? JSONEncoder().encode(alarms) { UserDefaults.standard.set(data, forKey: Self.defaultsKey) }
        reschedule()
    }

    /// Local notifications deliver the alarm (and its sound) even if the panel is closed; when
    /// notifications are not authorised an in-app timer plays the chime instead.
    private func reschedule() {
        fallbackTimer?.invalidate(); fallbackTimer = nil
        let center = UNUserNotificationCenter.current()
        let alarms = self.alarms
        center.getPendingNotificationRequests { pending in
            center.removePendingNotificationRequests(
                withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(Self.requestPrefix) }
            )
            guard alarms.contains(where: \.isEnabled) else { return }
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                if granted {
                    for alarm in alarms where alarm.isEnabled { Self.schedule(alarm, on: center) }
                } else {
                    Task { @MainActor [weak self] in self?.armFallback() }
                }
            }
        }
    }

    private nonisolated static func schedule(_ alarm: AlarmItem, on center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = alarm.label.isEmpty ? "Alarm" : alarm.label
        content.sound = .default
        if alarm.weekdays.isEmpty {
            // No weekdays selected = rings every day.
            center.add(UNNotificationRequest(
                identifier: requestPrefix + alarm.id.uuidString, content: content,
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: DateComponents(hour: alarm.hour, minute: alarm.minute), repeats: true)
            ))
        } else {
            for weekday in alarm.weekdays {
                let parts = DateComponents(hour: alarm.hour, minute: alarm.minute, weekday: weekday)
                center.add(UNNotificationRequest(
                    identifier: requestPrefix + alarm.id.uuidString + ".\(weekday)", content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)
                ))
            }
        }
    }

    private func armFallback() {
        fallbackTimer?.invalidate()
        guard let (_, fire) = AlarmList.next(in: alarms, after: Date()) else { return }
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: max(1, fire.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            NSSound(named: "Glass")?.play()
            Task { @MainActor in self?.armFallback() }
        }
    }
}
