import Foundation
import AppKit

/// Hydration tracker service (Sydedock-style edge widget).
/// Manages countdown timer to next reminder, daily water glasses logged,
/// 14-day historical chart data, sloshing wave phase, and gentle sound feedback.
@MainActor
public final class HydrationController: ObservableObject {
    public static let shared = HydrationController()
    static let defaultsKey = "com.katikati.hydration.data"

    struct StoredData: Codable {
        var intervalMinutes: Int
        var dailyGoalGlasses: Int
        var secondsRemaining: Int
        var history: [String: Int] // yyyy-MM-dd -> count
        var lastDrinkDate: Date?
        var lastDayString: String
    }

    @Published public var intervalMinutes: Int = 45 {
        didSet { persist() }
    }
    @Published public var dailyGoalGlasses: Int = 8 {
        didSet { persist() }
    }
    @Published public var secondsRemaining: Int = 45 * 60
    @Published public var todayGlasses: Int = 0
    @Published public var isOverdue: Bool = false
    @Published public var history: [String: Int] = [:] // yyyy-MM-dd -> glasses
    @Published public var wavePhase: Double = 0
    @Published public var soundEnabled: Bool = true

    private var timer: Timer?
    private var lastDayString: String = ""

    private static let dayDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()

    private static let dayNameFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "EE"
        return df
    }()

    public init() {
        load()
        checkDayRollover()
        startTimer()
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Actions

    /// Logs a glass of water, increments today's intake, resets timer, and plays gentle water audio.
    public func drinkNow() {
        checkDayRollover()
        todayGlasses += 1
        let todayKey = Self.dayDateFormatter.string(from: Date())
        history[todayKey] = todayGlasses
        secondsRemaining = max(1, intervalMinutes * 60)
        isOverdue = false
        wavePhase = 0

        if soundEnabled {
            playWaterSound()
        }
        persist()
    }

    public func setIntervalMinutes(_ minutes: Int) {
        let clamped = max(5, min(240, minutes))
        intervalMinutes = clamped
        secondsRemaining = min(secondsRemaining, clamped * 60)
    }

    public func setDailyGoal(_ glasses: Int) {
        dailyGoalGlasses = max(1, min(30, glasses))
    }

    /// Progress from 0.0 (empty / need water) to 1.0 (just drank).
    public var intervalProgress: Double {
        let total = Double(max(1, intervalMinutes * 60))
        let rem = Double(max(0, secondsRemaining))
        return min(1.0, max(0.0, rem / total))
    }

    /// Formatted time string "MM:SS" or "HH:MM".
    public var formattedRemainingTime: String {
        let s = max(0, secondsRemaining)
        let mins = s / 60
        let secs = s % 60
        if mins >= 60 {
            let hours = mins / 60
            let m = mins % 60
            return String(format: "%02d:%02d", hours, m)
        }
        return String(format: "%02d:%02d", mins, secs)
    }

    /// 14-day historical chart data for the flyout.
    public func last14DaysData() -> [(dayLabel: String, count: Int, isToday: Bool)] {
        let cal = Calendar.current
        let today = Date()
        var results: [(dayLabel: String, count: Int, isToday: Bool)] = []
        for offset in (0..<14).reversed() {
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = Self.dayDateFormatter.string(from: date)
            let count = history[key] ?? 0
            let label = String(Self.dayNameFormatter.string(from: date).prefix(1))
            results.append((dayLabel: label, count: count, isToday: offset == 0))
        }
        return results
    }

    // MARK: - Internal Timer & Tick

    public func tick() {
        checkDayRollover()
        wavePhase += 0.12
        if secondsRemaining > 0 {
            secondsRemaining -= 1
            if secondsRemaining == 0 {
                isOverdue = true
            }
        } else {
            isOverdue = true
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func checkDayRollover() {
        let todayKey = Self.dayDateFormatter.string(from: Date())
        if todayKey != lastDayString {
            lastDayString = todayKey
            todayGlasses = history[todayKey] ?? 0
        }
    }

    private func playWaterSound() {
        // Subtle water/glass chime
        if let sound = NSSound(named: "Bottle") ?? NSSound(named: "Pop") ?? NSSound(named: "Glass") {
            sound.volume = 0.55
            sound.play()
        }
    }

    // MARK: - Persistence

    private func load() {
        let todayKey = Self.dayDateFormatter.string(from: Date())
        lastDayString = todayKey
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let stored = try? JSONDecoder().decode(StoredData.self, from: data) else {
            secondsRemaining = intervalMinutes * 60
            return
        }
        intervalMinutes = max(5, stored.intervalMinutes)
        dailyGoalGlasses = max(1, stored.dailyGoalGlasses)
        secondsRemaining = stored.secondsRemaining
        history = stored.history
        todayGlasses = stored.history[todayKey] ?? 0
        isOverdue = secondsRemaining <= 0
    }

    private func persist() {
        let todayKey = Self.dayDateFormatter.string(from: Date())
        let stored = StoredData(
            intervalMinutes: intervalMinutes,
            dailyGoalGlasses: dailyGoalGlasses,
            secondsRemaining: secondsRemaining,
            history: history,
            lastDrinkDate: Date(),
            lastDayString: todayKey
        )
        if let encoded = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(encoded, forKey: Self.defaultsKey)
        }
    }
}
