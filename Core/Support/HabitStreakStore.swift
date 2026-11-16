import Foundation
import AppKit

/// A user habit or daily routine item.
public struct HabitItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var isDoneToday: Bool

    public init(id: UUID = UUID(), title: String, isDoneToday: Bool = false) {
        self.id = id
        self.title = title
        self.isDoneToday = isDoneToday
    }
}

/// 6-week habit and streak tracking store (Sydedock-style edge widget).
/// Manages a 42-day dot matrix (6 weeks × 7 days) where dots fill and brighten
/// according to daily completed habits and tasks.
@MainActor
public final class HabitStreakStore: ObservableObject {
    public static let shared = HabitStreakStore()
    static let defaultsKey = "com.katikati.habits.data"

    struct StoredData: Codable {
        var habits: [HabitItem]
        var history: [String: Int] // yyyy-MM-dd -> completed count (0...4+)
        var streakCount: Int
        var lastDayString: String
    }

    @Published public var habits: [HabitItem] = [
        HabitItem(title: "Hydrate (2L water)"),
        HabitItem(title: "25m Deep focus session"),
        HabitItem(title: "Stretch / Walk"),
        HabitItem(title: "Review daily notes")
    ] {
        didSet { persist() }
    }

    @Published public var history: [String: Int] = [:] {
        didSet { persist() }
    }

    @Published public var streakCount: Int = 5 {
        didSet { persist() }
    }

    private var lastDayString: String = ""

    private static let dayDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()

    public init() {
        load()
        checkDayRollover()
        recalculateStreak()
    }

    // MARK: - Actions

    public func toggleHabit(id: UUID) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        habits[idx].isDoneToday.toggle()
        updateTodayHistory()
        recalculateStreak()
        persist()
    }

    public func addHabit(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        habits.append(HabitItem(title: trimmed))
        persist()
    }

    public func removeHabit(id: UUID) {
        habits.removeAll { $0.id == id }
        updateTodayHistory()
        recalculateStreak()
        persist()
    }

    public func recordActivity(date: Date = Date(), count: Int = 1) {
        let key = Self.dayDateFormatter.string(from: date)
        let current = history[key] ?? 0
        history[key] = current + count
        recalculateStreak()
        persist()
    }

    /// 42 dots for the 6-week matrix (ordered chronological from 41 days ago to today).
    public func matrix42Days() -> [(date: Date, level: Int, isToday: Bool)] {
        let cal = Calendar.current
        let today = Date()
        var dots: [(date: Date, level: Int, isToday: Bool)] = []
        for offset in (0..<42).reversed() {
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = Self.dayDateFormatter.string(from: d)
            let count = history[key] ?? 0
            // Level: 0 = empty, 1 = low, 2 = medium, 3 = high/full
            let level: Int
            if count == 0 { level = 0 }
            else if count == 1 { level = 1 }
            else if count <= 3 { level = 2 }
            else { level = 3 }
            dots.append((date: d, level: level, isToday: offset == 0))
        }
        return dots
    }

    // MARK: - Private Helpers

    private func updateTodayHistory() {
        let todayKey = Self.dayDateFormatter.string(from: Date())
        let done = habits.filter(\.isDoneToday).count
        history[todayKey] = done
    }

    private func recalculateStreak() {
        let cal = Calendar.current
        var current = 0
        var day = Date()
        let todayKey = Self.dayDateFormatter.string(from: day)

        // If today has activity, include today; otherwise start from yesterday
        if (history[todayKey] ?? 0) > 0 {
            current += 1
        }

        while let prev = cal.date(byAdding: .day, value: -1, to: day) {
            let key = Self.dayDateFormatter.string(from: prev)
            if (history[key] ?? 0) > 0 {
                current += 1
                day = prev
            } else {
                break
            }
        }
        streakCount = current
    }

    private func checkDayRollover() {
        let todayKey = Self.dayDateFormatter.string(from: Date())
        if todayKey != lastDayString {
            lastDayString = todayKey
            // Reset daily habit checks
            for i in habits.indices {
                habits[i].isDoneToday = false
            }
        }
    }

    // MARK: - Persistence

    private func load() {
        let todayKey = Self.dayDateFormatter.string(from: Date())
        lastDayString = todayKey
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let stored = try? JSONDecoder().decode(StoredData.self, from: data) else {
            seedSampleHistory()
            return
        }
        habits = stored.habits
        history = stored.history
        streakCount = stored.streakCount

        if stored.lastDayString != todayKey {
            for i in habits.indices {
                habits[i].isDoneToday = false
            }
        }
    }

    private func seedSampleHistory() {
        // Provide gentle initial history so the matrix displays beautifully on first launch
        let cal = Calendar.current
        let today = Date()
        var seeded: [String: Int] = [:]
        for offset in 0..<30 {
            if let d = cal.date(byAdding: .day, value: -offset, to: today) {
                let k = Self.dayDateFormatter.string(from: d)
                // Randomish seed: 75% active days
                if offset % 4 != 3 {
                    seeded[k] = (offset % 3) + 1
                }
            }
        }
        history = seeded
        recalculateStreak()
    }

    private func persist() {
        let todayKey = Self.dayDateFormatter.string(from: Date())
        let stored = StoredData(
            habits: habits,
            history: history,
            streakCount: streakCount,
            lastDayString: todayKey
        )
        if let encoded = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(encoded, forKey: Self.defaultsKey)
        }
    }
}
