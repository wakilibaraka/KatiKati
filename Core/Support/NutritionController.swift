import Foundation
import AppKit

/// Protocol presets for intermittent fasting.
public enum FastingProtocol: String, CaseIterable, Codable, Sendable {
    case none
    case fast16_8
    case fast18_6
    case fast14_10
    case custom

    public var title: String {
        switch self {
        case .none: return "Off"
        case .fast16_8: return "16:8 Fast"
        case .fast18_6: return "18:6 Fast"
        case .fast14_10: return "14:10 Fast"
        case .custom: return "Custom"
        }
    }

    public var targetFastHours: Double {
        switch self {
        case .none: return 0
        case .fast16_8: return 16
        case .fast18_6: return 18
        case .fast14_10: return 14
        case .custom: return 16
        }
    }

    public var targetEatingHours: Double {
        max(0, 24 - targetFastHours)
    }
}

/// Food, Nutrition & Fasting controller for the Sydedock-style edge widget.
/// Manages 3 unified sections:
/// 1. Intermittent Fasting timer and eating window
/// 2. Meal & snack interval cadence timer
/// 3. Daily calories and macro tracker
@MainActor
public final class NutritionController: ObservableObject {
    public static let shared = NutritionController()
    static let defaultsKey = "com.katikati.nutrition.data"

    struct StoredData: Codable {
        var protocolType: FastingProtocol
        var fastStartTime: Date?
        var isFasting: Bool
        var customFastHours: Double
        var mealIntervalHours: Double
        var secondsUntilNextMeal: Int
        var todayMealsCount: Int
        var dailyCalorieGoal: Int
        var todayCalories: Int
        var proteinGrams: Int
        var carbsGrams: Int
        var fatGrams: Int
        var lastDayString: String
    }

    // MARK: - Section 1: Intermittent Fasting
    @Published public var protocolType: FastingProtocol = .fast16_8 {
        didSet { persist() }
    }
    @Published public var customFastHours: Double = 16 {
        didSet { persist() }
    }
    @Published public var isFasting: Bool = true {
        didSet { persist() }
    }
    @Published public var fastStartTime: Date? = Date().addingTimeInterval(-14 * 3600) {
        didSet { persist() }
    }

    // MARK: - Section 2: Meal & Snack Cadence
    @Published public var mealIntervalHours: Double = 3.5 {
        didSet { persist() }
    }
    @Published public var secondsUntilNextMeal: Int = Int(3.5 * 3600)
    @Published public var todayMealsCount: Int = 2

    // MARK: - Section 3: Calories & Macros
    @Published public var dailyCalorieGoal: Int = 2000 {
        didSet { persist() }
    }
    @Published public var todayCalories: Int = 1250
    @Published public var proteinGrams: Int = 95
    @Published public var carbsGrams: Int = 120
    @Published public var fatGrams: Int = 45

    @Published public var soundEnabled: Bool = true

    private var timer: Timer?
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
        startTimer()
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Fasting Actions

    public func startFast() {
        isFasting = true
        fastStartTime = Date()
        persist()
    }

    public func endFast() {
        isFasting = false
        fastStartTime = nil
        resetMealTimer()
        persist()
    }

    /// Elapsed seconds of active fast.
    public var elapsedFastSeconds: TimeInterval {
        guard isFasting, let start = fastStartTime else { return 0 }
        return max(0, Date().timeIntervalSince(start))
    }

    /// Target seconds of fast based on active protocol.
    public var targetFastSeconds: TimeInterval {
        let hours = protocolType == .custom ? customFastHours : protocolType.targetFastHours
        return max(1, hours * 3600)
    }

    /// Progress of current fast from 0.0 to 1.0 (or >1.0 if exceeded).
    public var fastProgress: Double {
        guard targetFastSeconds > 0 else { return 0 }
        return elapsedFastSeconds / targetFastSeconds
    }

    public var formattedFastTime: String {
        let totalSecs = Int(elapsedFastSeconds)
        let hours = totalSecs / 3600
        let mins = (totalSecs % 3600) / 60
        return String(format: "%02d:%02d", hours, mins)
    }

    // MARK: - Meal Cadence Actions

    public func logMeal(calories: Int = 450, protein: Int = 30, carbs: Int = 45, fat: Int = 15) {
        checkDayRollover()
        todayMealsCount += 1
        todayCalories += max(0, calories)
        proteinGrams += max(0, protein)
        carbsGrams += max(0, carbs)
        fatGrams += max(0, fat)
        resetMealTimer()

        if soundEnabled {
            NSSound(named: "Pop")?.play()
        }
        persist()
    }

    public func resetMealTimer() {
        secondsUntilNextMeal = max(60, Int(mealIntervalHours * 3600))
    }

    public var formattedNextMealTime: String {
        let s = max(0, secondsUntilNextMeal)
        let hours = s / 3600
        let mins = (s % 3600) / 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, mins)
        }
        return String(format: "%02d min", mins)
    }

    // MARK: - Calories & Macros

    public var calorieProgress: Double {
        guard dailyCalorieGoal > 0 else { return 0 }
        return min(1.0, Double(todayCalories) / Double(dailyCalorieGoal))
    }

    // MARK: - Timer & Ticks

    public func tick() {
        checkDayRollover()
        if secondsUntilNextMeal > 0 {
            secondsUntilNextMeal -= 1
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
            todayMealsCount = 0
            todayCalories = 0
            proteinGrams = 0
            carbsGrams = 0
            fatGrams = 0
        }
    }

    // MARK: - Persistence

    private func load() {
        let todayKey = Self.dayDateFormatter.string(from: Date())
        lastDayString = todayKey
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let stored = try? JSONDecoder().decode(StoredData.self, from: data) else {
            return
        }
        protocolType = stored.protocolType
        fastStartTime = stored.fastStartTime
        isFasting = stored.isFasting
        customFastHours = stored.customFastHours
        mealIntervalHours = stored.mealIntervalHours
        secondsUntilNextMeal = stored.secondsUntilNextMeal
        dailyCalorieGoal = stored.dailyCalorieGoal

        if stored.lastDayString == todayKey {
            todayMealsCount = stored.todayMealsCount
            todayCalories = stored.todayCalories
            proteinGrams = stored.proteinGrams
            carbsGrams = stored.carbsGrams
            fatGrams = stored.fatGrams
        } else {
            todayMealsCount = 0
            todayCalories = 0
            proteinGrams = 0
            carbsGrams = 0
            fatGrams = 0
        }
    }

    private func persist() {
        let todayKey = Self.dayDateFormatter.string(from: Date())
        let stored = StoredData(
            protocolType: protocolType,
            fastStartTime: fastStartTime,
            isFasting: isFasting,
            customFastHours: customFastHours,
            mealIntervalHours: mealIntervalHours,
            secondsUntilNextMeal: secondsUntilNextMeal,
            todayMealsCount: todayMealsCount,
            dailyCalorieGoal: dailyCalorieGoal,
            todayCalories: todayCalories,
            proteinGrams: proteinGrams,
            carbsGrams: carbsGrams,
            fatGrams: fatGrams,
            lastDayString: todayKey
        )
        if let encoded = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(encoded, forKey: Self.defaultsKey)
        }
    }
}
