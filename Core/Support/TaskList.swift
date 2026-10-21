import Foundation

/// One to-do with an optional running time tracker (Phase 7A-P3). The checklist and "one tracker at a time"
/// behaviour follow Hop's to-dos and tracker (MIT, NOTICE §9), simplified: no reminders, no estimates.
struct TaskItem: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var text: String
    var done: Bool
    var important: Bool
    var doneAt: Date?
    /// Seconds tracked in finished runs.
    var trackedSeconds: Double
    /// Start of the current run; nil when the tracker is stopped.
    var runningSince: Date?
    /// Phase 56e: the day the task is due (start of that day); nil = no due date.
    var due: Date?

    init(id: UUID = UUID(), text: String, done: Bool = false, important: Bool = false, doneAt: Date? = nil,
         trackedSeconds: Double = 0, runningSince: Date? = nil, due: Date? = nil) {
        self.id = id
        self.text = text
        self.done = done
        self.important = important
        self.doneAt = doneAt
        self.trackedSeconds = trackedSeconds
        self.runningSince = runningSince
        self.due = due
    }

    private enum CodingKeys: String, CodingKey { case id, text, done, important, doneAt, trackedSeconds, runningSince, due }

    /// Every field after `text` decodes leniently, so an older or hand-edited file still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        important = try c.decodeIfPresent(Bool.self, forKey: .important) ?? false
        doneAt = try c.decodeIfPresent(Date.self, forKey: .doneAt)
        trackedSeconds = max(0, try c.decodeIfPresent(Double.self, forKey: .trackedSeconds) ?? 0)
        runningSince = try c.decodeIfPresent(Date.self, forKey: .runningSince)
        due = try c.decodeIfPresent(Date.self, forKey: .due)
    }

    func elapsed(at now: Date) -> Double {
        trackedSeconds + (runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }
}

struct TaskList: Codable, Equatable, Sendable {
    var items: [TaskItem] = []

    private enum CodingKeys: String, CodingKey { case items }

    init(items: [TaskItem] = []) { self.items = items }

    init(from decoder: Decoder) throws {
        items = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent([TaskItem].self, forKey: .items) ?? []
    }

    /// Appends at the bottom; blank text is a no-op.
    @discardableResult
    mutating func add(text: String) -> UUID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let item = TaskItem(text: trimmed)
        items.append(item)
        return item.id
    }

    /// Flips done in place (order never changes). Completing a task stops its tracker.
    mutating func toggle(_ id: UUID, now: Date = Date()) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        if !items[i].done { stop(index: i, now: now) }
        items[i].done.toggle()
        items[i].doneAt = items[i].done ? now : nil
    }

    mutating func toggleImportant(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].important.toggle()
    }

    /// Sets the due day (stored as that day's start) or clears it with nil.
    mutating func setDue(_ id: UUID, _ day: Date?, calendar: Calendar = .current) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].due = day.map { calendar.startOfDay(for: $0) }
    }

    mutating func delete(_ id: UUID) { items.removeAll { $0.id == id } }

    /// Starts the tracker on `id` and stops any other (one run at a time). A done task cannot be tracked.
    mutating func startTracking(_ id: UUID, now: Date = Date()) {
        guard let target = items.firstIndex(where: { $0.id == id }), !items[target].done else { return }
        for i in items.indices where i != target { stop(index: i, now: now) }
        if items[target].runningSince == nil { items[target].runningSince = now }
    }

    mutating func stopTracking(_ id: UUID, now: Date = Date()) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        stop(index: i, now: now)
    }

    /// Removes finished tasks completed before `date`.
    mutating func clearCompleted(before date: Date) {
        items.removeAll { $0.done && ($0.doneAt.map { $0 < date } ?? true) }
    }

    var runningID: UUID? { items.first { $0.runningSince != nil }?.id }
    var openCount: Int { items.filter { !$0.done }.count }

    func totalTracked(at now: Date) -> Double { items.reduce(0) { $0 + $1.elapsed(at: now) } }

    private mutating func stop(index i: Int, now: Date) {
        guard let start = items[i].runningSince else { return }
        items[i].trackedSeconds += max(0, now.timeIntervalSince(start))
        items[i].runningSince = nil
    }
}

enum TaskDisplay {
    /// `4:07` under an hour, `1:04:07` from an hour up.
    static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

enum TaskDue: Equatable {
    case overdue, today, tomorrow, later

    init(_ due: Date, now: Date = Date(), calendar: Calendar = .current) {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0
        self = days < 0 ? .overdue : days == 0 ? .today : days == 1 ? .tomorrow : .later
    }
}

extension Array where Element == TaskItem {
    /// Phase 56d/e: what to work on first. Running tracker, then dated tasks (earliest due first, important
    /// first on a tie), then important undated, then the rest, finished last; list order breaks every tie.
    var smartOrdered: [TaskItem] {
        func key(_ t: TaskItem) -> (Int, Date, Int) {
            if t.done { return (4, .distantPast, 0) }
            if t.runningSince != nil { return (0, .distantPast, 0) }
            if let d = t.due { return (1, d, t.important ? 0 : 1) }
            return (t.important ? 2 : 3, .distantPast, 0)
        }
        return enumerated().sorted {
            let (a, b) = (key($0.element), key($1.element))
            return (a.0, a.1, a.2, $0.offset) < (b.0, b.1, b.2, $1.offset)
        }.map(\.element)
    }
}
