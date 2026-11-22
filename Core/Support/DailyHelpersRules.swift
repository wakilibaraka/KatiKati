import Foundation

// Phase 36 — pure rules behind the small daily helpers. No AppKit, no clocks, no IO: every threshold and
// transition is unit-tested in `DailyHelpersRulesTests`. `DailyHelpersService` feeds these and shows the result.

/// What a daily-helper notice says (the UI maps each kind to a symbol + localized headline).
enum LiveNoticeKind: String, Equatable, Sendable {
    case capsLockOn, capsLockOff
    case batteryHigh, batteryFull
    case hydrate, pause
}

/// 56e — wellness reminders. Fixed gaps (no picker): water hourly, a screen break every 50 minutes.
extension LiveNoticeKind {
    var reminderInterval: TimeInterval? {
        switch self {
        case .hydrate: return 3600
        case .pause: return 3000
        default: return nil
        }
    }
}

/// 36a — Caps Lock transitions. The first reading only sets the baseline (no notice at launch).
struct CapsLockTracker: Equatable, Sendable {
    private(set) var isOn: Bool?

    mutating func update(isOn now: Bool) -> LiveNoticeKind? {
        defer { isOn = now }
        guard let before = isOn, before != now else { return nil }
        return now ? .capsLockOn : .capsLockOff
    }
}

/// 36b — "unplug" nudges while charging: once at 80% (the battery-health sweet spot) and once when full.
/// The first reading only seeds the state, so launching at 90% plugged in does not announce anything.
/// Each nudge re-arms after the level drops back or the charger is unplugged.
struct BatteryNoticeRule: Equatable, Sendable {
    static let highThreshold = 80
    private var seeded = false
    private var armedHigh = true
    private var armedFull = true

    mutating func update(_ battery: BatteryStatus) -> LiveNoticeKind? {
        guard let level = battery.level else { return nil }
        if !seeded {
            seeded = true
            armedHigh = level < Self.highThreshold
            armedFull = level < 100
            return nil
        }
        if !battery.isPluggedIn || level < Self.highThreshold - 5 { armedHigh = true }
        if !battery.isPluggedIn || level < 95 { armedFull = true }
        guard battery.isPluggedIn else { return nil }
        if level >= 100, armedFull { armedFull = false; armedHigh = false; return .batteryFull }
        if battery.isCharging, level >= Self.highThreshold, armedHigh { armedHigh = false; return .batteryHigh }
        return nil
    }
}

/// 36f — keyboard cleaning lock length. Long enough to wipe a keyboard, short enough that a forgotten
/// lock frees itself (the fixed ⌃⌥⌘P chord from Phase 24b always unlocks sooner).
enum CleaningLock {
    static let defaultSeconds = 60.0
    static func clamped(_ seconds: Double) -> Double { min(max(seconds, 10), 300) }

    /// What a lock that outlived its own process does at the next launch.
    enum Launch: Equatable {
        /// Nothing pending, or the window has passed: the lock must not hold the keyboard.
        case release
        /// Still inside the window: hold it for the seconds left.
        case resume(seconds: Int)
    }

    /// Phase 12 safety fix. The lock pauses the keyboard through the persisted 24b pause, but its
    /// deadline was never written down — so a crash or force-quit mid-lock came up with a dead
    /// keyboard until ⌃⌥⌘P. The deadline is persisted now and this is the whole decision on it:
    /// a window still running resumes, anything else fails **open**.
    ///
    /// The one case it cannot answer: a *pre-fix* crash leaves `isPaused` on with no deadline at
    /// all, which is indistinguishable from a deliberate 24b pause — the caller leaves that alone
    /// (`shortcut:` nothing persists a lock's start before Phase 12, so `nil` must stay hands-off).
    static func launchDecision(deadline: Date?, now: Date) -> Launch {
        guard let deadline else { return .release }
        let left = deadline.timeIntervalSince(now)
        guard left > 0 else { return .release }
        return .resume(seconds: Int(left.rounded(.up)))
    }
}

/// 36c — which mounted volumes get an eject pill: real external, ejectable drives only (never the boot
/// volume, an internal disk, a disk image, or a network share).
enum EjectPolicy {
    static func isOffered(isEjectable: Bool, isInternal: Bool, isLocal: Bool, isRoot: Bool) -> Bool {
        isEjectable && !isInternal && isLocal && !isRoot
    }
}

/// 36h — which privacy dots show (green camera, orange microphone, both can show together).
struct PrivacyDots: Equatable, Sendable {
    var camera = false
    var microphone = false
    var isEmpty: Bool { !camera && !microphone }
}

// MARK: - Droppy-Inspired Slice E-Breather: BreatherWellnessEngine

struct BreatherRingProgress: Equatable, Sendable {
    var completed: Int
    var target: Int

    var progress: Double {
        guard target > 0 else { return 0 }
        return min(1.0, max(0.0, Double(completed) / Double(target)))
    }
}

struct BreatherRings: Equatable, Sendable {
    var eyes: BreatherRingProgress
    var stretch: BreatherRingProgress
    var hydrate: BreatherRingProgress

    var allCompleted: Bool {
        eyes.progress >= 1.0 && stretch.progress >= 1.0 && hydrate.progress >= 1.0
    }
}

struct BreatherStreak: Equatable, Sendable {
    var count: Int
    var lastCompletedDate: Date?

    mutating func recordCompletion(on date: Date, calendar: Calendar = .current) {
        if let last = lastCompletedDate {
            if calendar.isDate(last, inSameDayAs: date) {
                return
            }
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: date),
               calendar.isDate(last, inSameDayAs: yesterday) {
                count += 1
            } else {
                count = 1
            }
        } else {
            count = 1
        }
        lastCompletedDate = date
    }
}

enum BreatherActivityType: String, CaseIterable, Identifiable, Sendable {
    case eyes
    case stretch
    case hydrate

    var id: String { rawValue }

    var intervalSeconds: TimeInterval {
        switch self {
        case .eyes: return 1200
        case .stretch: return 3000
        case .hydrate: return 3600
        }
    }
}

struct BreatherScheduleEngine: Equatable, Sendable {
    var rings: BreatherRings
    var streak: BreatherStreak

    init(
        rings: BreatherRings = BreatherRings(
            eyes: BreatherRingProgress(completed: 0, target: 12),
            stretch: BreatherRingProgress(completed: 0, target: 6),
            hydrate: BreatherRingProgress(completed: 0, target: 8)
        ),
        streak: BreatherStreak = BreatherStreak(count: 0, lastCompletedDate: nil)
    ) {
        self.rings = rings
        self.streak = streak
    }

    /// Evaluates if a reminder prompt should trigger or be suppressed.
    /// Strictly suppressed when camera or microphone is in use, or a call is active.
    static func shouldSuppress(
        cameraInUse: Bool,
        microphoneInUse: Bool,
        callActive: Bool
    ) -> Bool {
        cameraInUse || microphoneInUse || callActive
    }

    /// Logs completion of an activity, advancing the respective ring and updating streaks when all rings are completed.
    mutating func completeActivity(_ type: BreatherActivityType, date: Date = Date(), calendar: Calendar = .current) {
        switch type {
        case .eyes:
            rings.eyes.completed += 1
        case .stretch:
            rings.stretch.completed += 1
        case .hydrate:
            rings.hydrate.completed += 1
        }

        if rings.allCompleted {
            streak.recordCompletion(on: date, calendar: calendar)
        }
    }
}

// MARK: - Slice 4.2: SmartDockAutomationPolicy

enum SmartDockAction: Equatable, Sendable {
    case pauseMedia
    case warnAILimit(provider: String, percent: Double, isWeekly: Bool)
    case notifyAILimitReset(provider: String)
    case setDockHidden(Bool)
}

struct SmartDockAutomationSettings: Equatable, Sendable {
    var pauseMediaBeforeMeeting: Bool = true
    var warnOnAILimitThreshold: Bool = true
    var stepAsideOnFullscreen: Bool = true

    static let pauseMediaKey = "com.katikati.dock.autoPauseMedia"
    static let warnAILimitKey = "com.katikati.dock.warnAILimits"
    static let stepAsideKey = "com.katikati.dock.stepAsideFullscreen"

    static func current(_ d: UserDefaults = .standard) -> SmartDockAutomationSettings {
        var s = SmartDockAutomationSettings()
        if d.object(forKey: pauseMediaKey) != nil {
            s.pauseMediaBeforeMeeting = d.bool(forKey: pauseMediaKey)
        }
        if d.object(forKey: warnAILimitKey) != nil {
            s.warnOnAILimitThreshold = d.bool(forKey: warnAILimitKey)
        }
        if d.object(forKey: stepAsideKey) != nil {
            s.stepAsideOnFullscreen = d.bool(forKey: stepAsideKey)
        }
        return s
    }
}

struct SmartDockAutomationPolicy: Equatable, Sendable {
    var settings: SmartDockAutomationSettings

    init(settings: SmartDockAutomationSettings = SmartDockAutomationSettings()) {
        self.settings = settings
    }

    /// Automatically emits `.pauseMedia` when a Calendar event with a meeting link is within 60s of starting and media is playing.
    func evaluateMeetingMediaPause(
        secondsUntilMeeting: TimeInterval,
        hasMeetingLink: Bool,
        isMediaPlaying: Bool
    ) -> SmartDockAction? {
        guard settings.pauseMediaBeforeMeeting else { return nil }
        guard hasMeetingLink, isMediaPlaying else { return nil }
        if secondsUntilMeeting > 0 && secondsUntilMeeting <= 60 {
            return .pauseMedia
        }
        return nil
    }

    /// Emits a warning when any tracked AI provider's sessionPercent or weeklyPercent crosses 85% (or notifies on limit reset).
    func evaluateAILimitThreshold(
        provider: String,
        sessionPercent: Double,
        weeklyPercent: Double,
        previousMaxPercent: Double = 0
    ) -> SmartDockAction? {
        guard settings.warnOnAILimitThreshold else { return nil }
        let currentMax = max(sessionPercent, weeklyPercent)
        if currentMax >= 85.0 {
            let isWeekly = weeklyPercent >= sessionPercent
            return .warnAILimit(provider: provider, percent: currentMax, isWeekly: isWeekly)
        } else if previousMaxPercent >= 85.0 && currentMax < 10.0 {
            return .notifyAILimitReset(provider: provider)
        }
        return nil
    }

    /// Automatically hides/collapses the dock bar when the active display enters a fullscreen app or video.
    func evaluateFullscreenStepAside(
        isFullscreen: Bool,
        isDockCurrentlyHidden: Bool
    ) -> SmartDockAction? {
        guard settings.stepAsideOnFullscreen else { return nil }
        if isFullscreen && !isDockCurrentlyHidden {
            return .setDockHidden(true)
        } else if !isFullscreen && isDockCurrentlyHidden {
            return .setDockHidden(false)
        }
        return nil
    }
}

// MARK: - Slice 4.3: OpenTaskbar Inline Micro-Tiles

struct InlineTodoItem: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var isDone: Bool
}

struct InlineTodoPillModel: Equatable, Sendable {
    var items: [InlineTodoItem]

    var activeItems: [InlineTodoItem] {
        items.filter { !$0.isDone }
    }

    var remainingCountBadge: String {
        "(\(activeItems.count))"
    }

    var isEmpty: Bool {
        activeItems.isEmpty
    }

    var emptyStateText: String {
        "0 No todos — Click to add one"
    }

    /// Top 2 active items formatted for 2-line rendering
    var topTwoItems: [InlineTodoItem] {
        Array(activeItems.prefix(2))
    }

    func lineText(at index: Int) -> String {
        guard index < topTwoItems.count else { return "" }
        let item = topTwoItems[index]
        return "\(item.isDone ? "☑" : "☐") \(item.title)"
    }
}

struct InlineBarSliderMath: Equatable, Sendable {
    /// Normalizes horizontal drag delta on a pill of given width into 0...1.0 (0% - 100%).
    static func scrubFraction(startFraction: Double, dragDeltaX: CGFloat, totalWidth: CGFloat) -> Double {
        guard totalWidth > 0 else { return startFraction }
        let change = Double(dragDeltaX / totalWidth)
        let raw = startFraction + change
        return min(max(raw, 0.0), 1.0)
    }

    static func formattedPercent(_ fraction: Double) -> String {
        let percent = Int((min(max(fraction, 0.0), 1.0) * 100).rounded())
        return "\(percent)%"
    }

    /// Audio output device cycling state (< | > navigation)
    static func cycleAudioDeviceIndex(currentIndex: Int, totalDevices: Int, forward: Bool) -> Int {
        guard totalDevices > 0 else { return 0 }
        if forward {
            return (currentIndex + 1) % totalDevices
        } else {
            return (currentIndex - 1 + totalDevices) % totalDevices
        }
    }
}

// MARK: - Slice OW-3: the scratchpad

/// A scratch note with the two counts the card shows. Pure, so the badge is unit-tested.
struct ScratchpadDocument: Equatable, Sendable {
    var text: String = ""

    var characterCount: Int { text.count }
    var wordCount: Int { ScratchpadStore.wordCount(in: text) }
    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// OW-3 (behavior ported from `alztrk/OpenWidget`, MIT — see NOTICE): one persistent scratch note, saved
/// atomically to `~/Library/Application Support/KatiKati/scratchpad.txt` on a short debounce, so typing never
/// waits on the disk, with 1-click copy and clear.
@MainActor
final class ScratchpadStore: ObservableObject {
    static let shared = ScratchpadStore()
    static let fileName = "scratchpad.txt"
    static let debounce: TimeInterval = 0.6

    @Published private(set) var document = ScratchpadDocument()
    private let directory: URL
    private let delay: TimeInterval
    private var pending: DispatchWorkItem?

    var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    /// `directory` is injectable so the tests write into a temporary folder, never the owner's note.
    init(directory: URL? = nil, delay: TimeInterval = ScratchpadStore.debounce) {
        self.directory = directory ?? Self.applicationSupportDirectory
        self.delay = delay
        load()
    }

    static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KatiKati", isDirectory: true)
    }

    nonisolated static func wordCount(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Typing: the document updates at once, the file follows after the debounce.
    func update(_ text: String) {
        guard text != document.text else { return }
        document.text = text
        scheduleSave()
    }

    func scheduleSave() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Writes now — what the debounce ends in, and what `clear()` uses. Atomic, so a crash mid-write cannot
    /// leave a half-written note behind.
    func flush() {
        pending?.cancel()
        pending = nil
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try document.text.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            // A failed save keeps the text in memory; the next edit schedules another attempt.
        }
    }

    func load() {
        let stored = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        document = ScratchpadDocument(text: stored)
    }

    /// One-click snapshot: the note exactly as typed.
    func copyAll() -> String { document.text }

    func clear() {
        update("")
        flush()
    }
}

// MARK: - PHN-1: hydration plan, water units, pause prompts, wellness defaults

/// PHN — how the hydration ring reads its numbers. Metric readers get millilitres, imperial readers
/// ounces; the temperature unit is the tell until someone picks one in Settings.
enum WaterUnit: String, CaseIterable, Codable, Sendable, Identifiable {
    case millilitres, ounces

    var id: String { rawValue }

    static let millilitresPerOunce = 29.5735
    static let storageKey = "com.katikati.hydration.unit"

    static func following(_ temperature: TemperatureUnit) -> WaterUnit {
        temperature == .fahrenheit ? .ounces : .millilitres
    }

    /// A recorded millilitre count in this unit, rounded to a whole number.
    func amount(millilitres: Int) -> Int {
        switch self {
        case .millilitres: return millilitres
        case .ounces: return Int((Double(millilitres) / Self.millilitresPerOunce).rounded())
        }
    }

    /// "250 ml" / "8 oz" — verbatim in views (`Text(verbatim:)`), never a lookup key.
    func label(millilitres: Int) -> String { "\(amount(millilitres: millilitres)) \(suffix)" }

    var suffix: String {
        switch self {
        case .millilitres: return "ml"
        case .ounces: return "oz"
        }
    }

    static func resolved(raw: String?, temperature: TemperatureUnit) -> WaterUnit {
        raw.flatMap(WaterUnit.init(rawValue:)) ?? following(temperature)
    }
}

/// The one-tap servings on the ring. Millilitres are the stored truth.
enum DrinkQuickAdd: Int, CaseIterable, Sendable, Identifiable {
    case glass = 150
    case cup = 250
    case bottle = 500

    var id: Int { rawValue }
    var millilitres: Int { rawValue }
}

/// PHN — the pure hydration day: goal in millilitres, what was logged, the 14-day record behind the
/// streak, and the Smart Pause decision. No clock, no IO: `HydrationController` feeds it and persists it.
struct HydrationPlan: Equatable, Sendable {
    static let defaultGoalMillilitres = 2000
    static let glassMillilitres = 250

    /// Whether a reminder may surface right now.
    enum Surfacing: Equatable, Sendable { case running, quiet }

    var goalMillilitres: Int
    var unit: WaterUnit
    var todayMillilitres: Int
    /// day key (`2026-11-22`) → millilitres, today included once something is logged.
    var history: [String: Int]
    private(set) var dayKey: String

    init(goalMillilitres: Int = HydrationPlan.defaultGoalMillilitres,
         unit: WaterUnit = .millilitres,
         todayMillilitres: Int = 0,
         history: [String: Int] = [:],
         dayKey: String = "") {
        self.goalMillilitres = max(1, goalMillilitres)
        self.unit = unit
        self.todayMillilitres = max(0, todayMillilitres)
        self.history = history
        self.dayKey = dayKey
    }

    var glasses: Int { todayMillilitres / Self.glassMillilitres }

    /// 0…1, clamped: a 3 l day does not draw past the ring.
    var progress: Double {
        min(1, max(0, Double(todayMillilitres) / Double(max(1, goalMillilitres))))
    }

    var reachedGoal: Bool { todayMillilitres >= goalMillilitres }

    /// Records a drink and returns the new day total. The day record follows, so the chart and the
    /// streak read the same number the ring shows.
    @discardableResult
    mutating func log(_ millilitres: Int) -> Int {
        todayMillilitres = max(0, todayMillilitres + millilitres)
        if !dayKey.isEmpty { history[dayKey] = todayMillilitres }
        return todayMillilitres
    }

    /// Midnight (or the first drink of a new day): yesterday stays in `history`, today starts at whatever
    /// that day already holds (a relaunch mid-day must not lose it).
    mutating func rollOver(to key: String) {
        guard !key.isEmpty, key != dayKey else {
            if dayKey.isEmpty { dayKey = key; todayMillilitres = history[key] ?? todayMillilitres }
            return
        }
        if !dayKey.isEmpty { history[dayKey] = todayMillilitres }
        dayKey = key
        todayMillilitres = history[key] ?? 0
    }

    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Consecutive goal days ending today. Today counts when it is already met; otherwise the run is
    /// measured to yesterday, so a morning that has not started yet never reads as a broken streak.
    func streak(today: Date, calendar: Calendar = .current) -> Int {
        var cursor = today
        if (history[Self.dayKey(for: today, calendar: calendar)] ?? todayMillilitres) < goalMillilitres {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while (history[Self.dayKey(for: cursor, calendar: calendar)] ?? 0) >= goalMillilitres {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    /// WaterMinder's Smart Pause: reminders hold while a focus session, a camera/mic or a call is live.
    static func surfacing(focusActive: Bool, cameraInUse: Bool, microphoneInUse: Bool, callActive: Bool) -> Surfacing {
        (focusActive || cameraInUse || microphoneInUse || callActive) ? .quiet : .running
    }

    /// 14 days of the chart, oldest first, in the days the caller can name.
    func last14Days(today: Date, calendar: Calendar = .current) -> [(dayKey: String, millilitres: Int, isToday: Bool)] {
        (0..<14).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = Self.dayKey(for: date, calendar: calendar)
            let logged = offset == 0 ? max(todayMillilitres, history[key] ?? 0) : (history[key] ?? 0)
            return (key, logged, offset == 0)
        }
    }
}

// MARK: Pause — three gentle categories, no guilt

enum PauseCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case eyes, body, mind

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .eyes: return "eye"
        case .body: return "figure.walk"
        case .mind: return "brain.head.profile"
        }
    }

    var localizedTitle: String {
        switch self {
        case .eyes: return String(localized: "Eyes")
        case .body: return String(localized: "Body")
        case .mind: return String(localized: "Mind")
        }
    }

    static let storageKey = "com.katikati.pause.categories"
    /// All three ship on; a category is opt-out, never opt-in.
    static let defaultEnabled: Set<PauseCategory> = Set(allCases)
}

/// One line of the prompt pool. `text` is already localized: views render it verbatim.
struct PausePrompt: Equatable, Sendable, Identifiable {
    var id: String
    var category: PauseCategory
    var text: String
}

enum PausePrompts {
    /// Low-pressure by design: an instruction, a small kindness, or a permission — never a score.
    static let all: [PausePrompt] = [
        PausePrompt(id: "eyes-20-20", category: .eyes,
                    text: String(localized: "Look 20 feet away for 20 seconds.")),
        PausePrompt(id: "eyes-blink", category: .eyes,
                    text: String(localized: "Blink slowly a few times. Screens make us forget.")),
        PausePrompt(id: "eyes-sky", category: .eyes,
                    text: String(localized: "Find the furthest thing you can see and rest there.")),
        PausePrompt(id: "body-jaw", category: .body,
                    text: String(localized: "Unclench your jaw and drop your shoulders.")),
        PausePrompt(id: "body-hands", category: .body,
                    text: String(localized: "Let your hands hang for three slow breaths.")),
        PausePrompt(id: "body-stand", category: .body,
                    text: String(localized: "Stand up, stretch tall, sit back down.")),
        PausePrompt(id: "mind-one-step", category: .mind,
                    text: String(localized: "One small step, not ten.")),
        PausePrompt(id: "mind-okay", category: .mind,
                    text: String(localized: "This can wait a minute. So can you.")),
        PausePrompt(id: "mind-notice", category: .mind,
                    text: String(localized: "Name one thing that went fine today.")),
    ]

    static func enabled(_ categories: Set<PauseCategory>) -> [PausePrompt] {
        all.filter { categories.contains($0.category) }
    }
}

/// PHN — the pause the user is actually having: which prompt is next, whether it is snoozed, what was
/// skipped. Skipping never touches `streak` (the whole point of a guilt-free pause).
struct PauseSession: Equatable, Sendable {
    var categories: Set<PauseCategory> = PauseCategory.defaultEnabled
    var snoozeUntil: Date?
    var skippedCount = 0
    var completedCount = 0
    var streak = BreatherStreak(count: 0, lastCompletedDate: nil)
    var reflection = ""
    private(set) var cursor = 0

    var pool: [PausePrompt] { PausePrompts.enabled(categories) }
    var enabledCount: Int { pool.count }

    func isSnoozed(at now: Date) -> Bool {
        guard let snoozeUntil else { return false }
        return snoozeUntil > now
    }

    /// Deterministic rotation through the enabled pool — no RNG, so the tests can pin it.
    mutating func nextPrompt() -> PausePrompt? {
        let prompts = pool
        guard !prompts.isEmpty else { return nil }
        let prompt = prompts[cursor % prompts.count]
        cursor = (cursor + 1) % prompts.count
        return prompt
    }

    mutating func snooze(until date: Date) { snoozeUntil = date }

    /// "Not now" — counted, never punished.
    mutating func skip() {
        skippedCount += 1
        snoozeUntil = nil
    }

    /// "Done": the streak advances and the category ring lands with the caller (`HydrationController`).
    mutating func complete(on date: Date, calendar: Calendar = .current) {
        completedCount += 1
        snoozeUntil = nil
        streak.recordCompletion(on: date, calendar: calendar)
    }

    mutating func setCategory(_ category: PauseCategory, enabled: Bool) {
        if enabled { categories.insert(category) } else { categories.remove(category) }
        cursor = 0
    }
}

// MARK: Wellness blockers

/// PHN — what the system says is happening right now, gathered by the App layer (`PrivacyUseProbe`, the
/// focus timer) and handed to Core. Smart Pause reads `any`; a break reminder only stands down for
/// `inMeeting`, because a focus session is exactly when a pause is worth offering.
struct WellnessBlockers: Equatable, Sendable {
    var focusActive = false
    var cameraInUse = false
    var microphoneInUse = false
    var callActive = false

    static let none = WellnessBlockers()

    var inMeeting: Bool { cameraInUse || microphoneInUse || callActive }
    var any: Bool { focusActive || inMeeting }
}

/// PHN — one place that decides whether a wellness helper is on. Every helper ships **on**:
/// `bool(forKey:)` reads an unset key as `false`, which would silently ship the feature off, so the
/// unset case is `defaultEnabled` (the idiom `MenuBarStatModel.isEnabled` already uses).
enum WellnessDefaults {
    enum Item: String, CaseIterable, Sendable, Identifiable {
        case waterReminder, pauseReminder, smartPause, moveBanners

        var id: String { rawValue }

        /// The keys the services already write, so nothing is stored twice.
        var defaultsKey: String {
            switch self {
            case .waterReminder: return "com.katikati.helpers.hydrate"
            case .pauseReminder: return "com.katikati.helpers.pause"
            case .smartPause: return "com.katikati.hydration.smartPause"
            case .moveBanners: return "com.katikati.notifications.move"
            }
        }

        var localizedTitle: String {
            switch self {
            case .waterReminder: return String(localized: "Water Reminder")
            case .pauseReminder: return String(localized: "Break Reminder")
            case .smartPause: return String(localized: "Smart Pause")
            case .moveBanners: return String(localized: "Move Notification Banners")
            }
        }

        var defaultEnabled: Bool { true }
    }

    static func isEnabled(_ item: Item, defaults: UserDefaults = .standard) -> Bool {
        (defaults.object(forKey: item.defaultsKey) as? Bool) ?? item.defaultEnabled
    }

    static func set(_ enabled: Bool, for item: Item, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: item.defaultsKey)
    }
}
