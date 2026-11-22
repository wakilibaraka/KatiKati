import Foundation
import AppKit

/// Hydration tracker service (Sydedock-style edge widget, PHN-2 wellness wings).
/// Manages the countdown to the next reminder, the millilitres logged today and the 14-day record
/// behind the streak, plus the Pause session the dock wing offers. The arithmetic itself is
/// `HydrationPlan` / `PauseSession` in `DailyHelpersRules.swift` — this type only owns the clock,
/// the persistence and the sound, so the decisions stay unit-tested without a singleton.
@MainActor
public final class HydrationController: ObservableObject {
    public static let shared = HydrationController()
    static let defaultsKey = "com.katikati.hydration.data"

    struct StoredData: Codable {
        var intervalMinutes: Int
        var dailyGoalGlasses: Int
        var secondsRemaining: Int
        var lastDayString: String
        /// PHN-2: millilitres are the truth. `nil` on a record written before the millilitre move.
        var millilitresByDay: [String: Int]?
        var millilitresToday: Int?
        /// The pre-PHN record, in glasses — read once and converted.
        var history: [String: Int]?
        var lastDrinkDate: Date?
        // PHN: the Pause half.
        var pauseCategories: [String]?
        var pauseCompleted: Int?
        var pauseSkipped: Int?
        var pauseStreakCount: Int?
        var pauseStreakLast: Date?
        var pauseReflection: String?
        var eyesCompleted: Int?
        var stretchCompleted: Int?
        var hydrateCompleted: Int?
    }

    @Published public var intervalMinutes: Int = 45 {
        didSet { if !isLoading { persist() } }
    }
    @Published public var dailyGoalGlasses: Int = 8 {
        didSet { if !isLoading { persist() } }
    }
    @Published public var secondsRemaining: Int = 45 * 60
    @Published public private(set) var todayMillilitres: Int = 0
    @Published public var isOverdue: Bool = false
    @Published public var wavePhase: Double = 0
    @Published public var soundEnabled: Bool = true

    /// PHN-2: WaterMinder's Smart Pause — reminders and the ring hold while a focus session or a
    /// call/camera/mic is live, so the app never nudges someone who is mid-meeting.
    @Published public private(set) var smartPaused: Bool = false
    @Published public private(set) var streak: Int = 0

    /// PHN-2: the pause the user is actually having, and the prompt it is showing.
    @Published private(set) var pauseSession = PauseSession()
    @Published private(set) var currentPause: PausePrompt?
    @Published private(set) var breather = BreatherScheduleEngine()

    private var timer: Timer?
    private var probe: Timer?
    private var isLoading = true
    private var lastDayString: String = ""
    private var millilitresByDay: [String: Int] = [:]
    /// Filled by `DailyHelpersService` each probe tick: the app layer owns those system reads.
    @Published private(set) var blockers = WellnessBlockers.none

    private static let dayNameFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "EE"
        return df
    }()

    public init() {
        load()
        checkDayRollover()
        isLoading = false
        startTimer()
    }

    deinit {
        timer?.invalidate()
        probe?.invalidate()
    }

    // MARK: - Derived state

    /// Glasses, the unit the chart and the Goal slider speak.
    public var todayGlasses: Int { todayMillilitres / HydrationPlan.glassMillilitres }
    public var goalMillilitres: Int { dailyGoalGlasses * HydrationPlan.glassMillilitres }

    /// Per-day glasses, the shape the pre-PHN UI already read.
    public var history: [String: Int] {
        millilitresByDay.mapValues { $0 / HydrationPlan.glassMillilitres }
    }

    /// The day's progress toward the goal — what the ring draws.
    public var dayProgress: Double {
        min(1, max(0, Double(todayMillilitres) / Double(max(1, goalMillilitres))))
    }

    var waterUnit: WaterUnit {
        let raw = UserDefaults.standard.string(forKey: WaterUnit.storageKey)
        let temperature = UserDefaults.standard.string(forKey: WeatherUnits.temperatureKey)
            .flatMap(TemperatureUnit.init(rawValue:)) ?? .celsius
        return WaterUnit.resolved(raw: raw, temperature: temperature)
    }

    /// The pure view of today, for callers that want the plan rather than the published pieces.
    var plan: HydrationPlan {
        HydrationPlan(goalMillilitres: goalMillilitres, unit: waterUnit, todayMillilitres: todayMillilitres,
                      history: millilitresByDay,
                      dayKey: lastDayString.isEmpty ? Self.dayKey() : lastDayString)
    }

    public var pauseStreak: Int { pauseSession.streak.count }
    public var pauseSnoozed: Bool { pauseSession.isSnoozed(at: Date()) }

    /// Progress from 0.0 (just drank / paused) to 1.0 (the next reminder is due).
    public var intervalProgress: Double {
        let total = Double(max(1, intervalMinutes * 60))
        let rem = Double(max(0, secondsRemaining))
        return min(1.0, max(0.0, rem / total))
    }

    public var formattedRemainingTime: String {
        let s = max(0, secondsRemaining)
        let mins = s / 60
        let secs = s % 60
        if mins >= 60 {
            return String(format: "%02d:%02d", mins / 60, mins % 60)
        }
        return String(format: "%02d:%02d", mins, secs)
    }

    public func last14DaysData() -> [(dayLabel: String, count: Int, isToday: Bool)] {
        let calendar = Calendar.current
        return plan.last14Days(today: Date(), calendar: calendar).map { row in
            let date = Self.date(forDayKey: row.dayKey, calendar: calendar) ?? Date()
            let label = String(Self.dayNameFormatter.string(from: date).prefix(1))
            return (label, row.millilitres / HydrationPlan.glassMillilitres, row.isToday)
        }
    }

    // MARK: - Actions

    /// One glass (250 ml) — what the existing "Drink now" buttons call.
    public func drinkNow() { add(millilitres: HydrationPlan.glassMillilitres) }

    /// A quick-add serving: the day total, the record, the streak and the reminder all move together.
    public func add(millilitres: Int) {
        guard millilitres != 0 else { return }
        checkDayRollover()
        var plan = plan
        plan.rollOver(to: lastDayString.isEmpty ? Self.dayKey() : lastDayString)
        plan.log(millilitres)
        todayMillilitres = plan.todayMillilitres
        millilitresByDay = plan.history
        streak = plan.streak(today: Date())
        secondsRemaining = max(1, intervalMinutes * 60)
        isOverdue = false
        wavePhase = 0
        if millilitres > 0 { breather.completeActivity(.hydrate) }
        if soundEnabled { playWaterSound() }
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

    // MARK: - Smart Pause

    /// The App layer knows whether a focus session or a call is live; Core must not read those itself.
    public func setExternalBlockers(focusActive: Bool, cameraInUse: Bool, microphoneInUse: Bool, callActive: Bool) {
        let next = WellnessBlockers(focusActive: focusActive, cameraInUse: cameraInUse,
                                    microphoneInUse: microphoneInUse, callActive: callActive)
        if next != blockers { blockers = next }
        refreshSmartPause()
    }

    public func refreshSmartPause() {
        let wanted = WellnessDefaults.isEnabled(.smartPause) && blockers.any
        setSmartPaused(wanted)
    }

    /// While paused the 1 Hz countdown timer is released (a 15 s probe keeps watching for the end of
    /// the call), so a paused widget costs almost nothing.
    public func setSmartPaused(_ on: Bool) {
        guard on != smartPaused else { return }
        smartPaused = on
        if on {
            timer?.invalidate(); timer = nil
            startProbe()
        } else {
            probe?.invalidate(); probe = nil
            startTimer()
        }
    }

    // MARK: - Pause session

    /// Fills `currentPause` when there is none, or when its category was switched off.
    public func refreshPausePrompt() {
        if let current = currentPause, pauseSession.categories.contains(current.category) { return }
        currentPause = pauseSession.nextPrompt()
    }

    public func nextPausePrompt() {
        currentPause = pauseSession.nextPrompt()
    }

    /// "Done": the pause streak advances, the matching breather ring fills, the next line loads.
    public func completePause() {
        if currentPause == nil { refreshPausePrompt() }
        let category = currentPause?.category
        pauseSession.complete(on: Date())
        if let ring = Self.ring(for: category) { breather.completeActivity(ring) }
        currentPause = pauseSession.nextPrompt()
        persist()
    }

    /// "Not now" — counted in `skippedCount`, never against the streak.
    public func skipPause() {
        pauseSession.skip()
        currentPause = pauseSession.nextPrompt()
        persist()
    }

    public func snoozePause(minutes: Int = 15) {
        pauseSession.snooze(until: Date().addingTimeInterval(TimeInterval(minutes * 60)))
        persist()
    }

    func setPauseCategory(_ category: PauseCategory, enabled: Bool) {
        pauseSession.setCategory(category, enabled: enabled)
        refreshPausePrompt()
        persist()
    }

    public func setPauseReflection(_ text: String) {
        pauseSession.reflection = text
        persist()
    }

    private static func ring(for category: PauseCategory?) -> BreatherActivityType? {
        switch category {
        case .eyes: return .eyes
        case .body: return .stretch
        case .mind, .none: return nil
        }
    }

    // MARK: - Internal Timer & Tick

    public func tick() {
        checkDayRollover()
        refreshSmartPause()
        guard !smartPaused else { return }
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
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func startProbe() {
        probe?.invalidate()
        probe = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshSmartPause()
            }
        }
    }

    private func checkDayRollover() {
        let todayKey = Self.dayKey()
        guard todayKey != lastDayString else { return }
        if !lastDayString.isEmpty { millilitresByDay[lastDayString] = todayMillilitres }
        lastDayString = todayKey
        todayMillilitres = millilitresByDay[todayKey] ?? 0
        streak = plan.streak(today: Date())
        persist()
    }

    private func playWaterSound() {
        if let sound = NSSound(named: "Bottle") ?? NSSound(named: "Pop") ?? NSSound(named: "Glass") {
            sound.volume = 0.55
            sound.play()
        }
    }

    // MARK: - Day keys

    private static func dayKey(for date: Date = Date()) -> String {
        HydrationPlan.dayKey(for: date, calendar: .current)
    }

    private static func date(forDayKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    // MARK: - Persistence

    private func load() {
        isLoading = true
        lastDayString = Self.dayKey()
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let stored = try? JSONDecoder().decode(StoredData.self, from: data) else {
            secondsRemaining = intervalMinutes * 60
            isLoading = false
            return
        }
        intervalMinutes = max(5, stored.intervalMinutes)
        dailyGoalGlasses = max(1, stored.dailyGoalGlasses)
        secondsRemaining = stored.secondsRemaining
        if let millilitres = stored.millilitresByDay {
            millilitresByDay = millilitres
        } else if let glasses = stored.history {
            millilitresByDay = glasses.mapValues { $0 * HydrationPlan.glassMillilitres }
        }
        todayMillilitres = stored.millilitresToday ?? (millilitresByDay[lastDayString] ?? 0)
        isOverdue = secondsRemaining <= 0

        let categories = Set((stored.pauseCategories ?? []).compactMap(PauseCategory.init(rawValue:)))
        pauseSession.categories = categories.isEmpty ? PauseCategory.defaultEnabled : categories
        pauseSession.completedCount = stored.pauseCompleted ?? 0
        pauseSession.skippedCount = stored.pauseSkipped ?? 0
        pauseSession.reflection = stored.pauseReflection ?? ""
        pauseSession.streak = BreatherStreak(count: stored.pauseStreakCount ?? 0,
                                             lastCompletedDate: stored.pauseStreakLast)
        breather = BreatherScheduleEngine(
            rings: BreatherRings(
                eyes: BreatherRingProgress(completed: stored.eyesCompleted ?? 0, target: 12),
                stretch: BreatherRingProgress(completed: stored.stretchCompleted ?? 0, target: 6),
                hydrate: BreatherRingProgress(completed: stored.hydrateCompleted ?? 0, target: 8)
            ),
            streak: pauseSession.streak
        )
        streak = plan.streak(today: Date())
        isLoading = false
    }

    private func persist() {
        guard !isLoading else { return }
        millilitresByDay[lastDayString.isEmpty ? Self.dayKey() : lastDayString] = todayMillilitres
        let stored = StoredData(
            intervalMinutes: intervalMinutes,
            dailyGoalGlasses: dailyGoalGlasses,
            secondsRemaining: secondsRemaining,
            lastDayString: lastDayString,
            millilitresByDay: millilitresByDay,
            millilitresToday: todayMillilitres,
            history: nil,
            lastDrinkDate: Date(),
            pauseCategories: pauseSession.categories.map(\.rawValue).sorted(),
            pauseCompleted: pauseSession.completedCount,
            pauseSkipped: pauseSession.skippedCount,
            pauseStreakCount: pauseSession.streak.count,
            pauseStreakLast: pauseSession.streak.lastCompletedDate,
            pauseReflection: pauseSession.reflection,
            eyesCompleted: breather.rings.eyes.completed,
            stretchCompleted: breather.rings.stretch.completed,
            hydrateCompleted: breather.rings.hydrate.completed
        )
        if let encoded = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(encoded, forKey: Self.defaultsKey)
        }
    }
}
