import Combine
import Foundation

// Dynamic Island behavior choices (ported in spirit from vorssaint-utils, GPL-3.0): how the island opens,
// how long it waits, and which design each screen gets. Pure and dual-compiled; the settings pane and
// `NotchPanelController` both read through here.

enum NotchOpenMode: String, CaseIterable, Identifiable, Sendable {
    case hover, click
    var id: String { rawValue }
    static let defaultsKey = "com.katikati.notch.openMode"
    static func current(_ d: UserDefaults = .standard) -> NotchOpenMode {
        NotchOpenMode(rawValue: d.string(forKey: defaultsKey) ?? "") ?? .hover
    }
}

/// 51f: which island design a display gets. A Mac's notch screen defaults to the notch, every other
/// display to the wide bar (no cutout to hug); the owner overrides per display. Stored as a
/// `[displayID: rawValue]` dictionary under `defaultsKey`.
enum NotchDesign: String, CaseIterable, Identifiable, Sendable {
    case notch, wideBar, off
    var id: String { rawValue }
    static let defaultsKey = "com.katikati.notch.displayDesigns"

    static func stored(_ d: UserDefaults = .standard) -> [String: NotchDesign] {
        (d.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]).compactMapValues(NotchDesign.init(rawValue:))
    }

    static func set(_ design: NotchDesign, for display: String, _ d: UserDefaults = .standard) {
        var raw = d.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
        raw[display] = design.rawValue
        d.set(raw, forKey: defaultsKey)
    }

    static func resolve(
        display: String,
        displayUUID: String? = nil,
        hasHardwareNotch: Bool,
        stored: [String: NotchDesign]
    ) -> NotchDesign {
        if let displayUUID, !displayUUID.isEmpty, let match = stored[displayUUID] {
            return match
        }
        return stored[display] ?? (hasHardwareNotch ? .notch : .wideBar)
    }
}

/// 51h: which wide-bar items fit at a given width (the bar is as wide as the open panel: 544 compact, 640 standard, 768 spacious) (time is always kept).
enum NotchWideBarSpec {
    enum Item: Sendable { case time, battery, status, nowPlaying, timer, weather, storage, system }
    /// Drop order as the bar narrows: system, storage, weather, timer, now playing, Wi-Fi/volume, battery.
    static func items(width: CGFloat) -> [Item] {
        let steps: [(CGFloat, Item)] = [(360, .battery), (400, .status), (440, .nowPlaying), (480, .timer),
                                        (520, .weather), (580, .storage), (700, .system)]
        return [.time] + steps.filter { width >= $0.0 }.map(\.1)
    }
}

/// What the closed island shows when nothing is live (vorssaint-utils' "At rest"). `dockChips` is
/// KatiKati's original storage + battery pair.
enum NotchRestContent: String, CaseIterable, Identifiable, Sendable {
    case dockChips, timeBattery, storage, time, battery, nothing
    var id: String { rawValue }

    /// Curated left/right pairs; single-item presets split symmetrically across both wings,
    /// while `nothing` leaves the bare notch.
    enum Ear: Equatable, Sendable {
        case storage, storageLabel, time, date, battery, batteryIcon, batteryPercent
    }
    var left: Ear? {
        switch self {
        case .dockChips: return .storage
        case .timeBattery: return .time
        case .battery: return .batteryIcon
        case .storage: return .storageLabel
        case .time: return .date
        case .nothing: return nil
        }
    }
    var right: Ear? {
        switch self {
        case .dockChips, .timeBattery: return .battery
        case .battery: return .batteryPercent
        case .storage: return .storage
        case .time: return .time
        case .nothing: return nil
        }
    }
    static let defaultsKey = "com.katikati.notch.restContent"
    static func current(_ d: UserDefaults = .standard) -> NotchRestContent {
        NotchRestContent(rawValue: d.string(forKey: defaultsKey) ?? "") ?? .dockChips
    }
}

enum NotchBehavior {
    static let lowBatteryTintKey = "com.katikati.notch.lowBatteryTint"
    static let lowBatteryThresholdKey = "com.katikati.notch.lowBatteryThreshold"
    static let defaultLowBatteryThreshold = 20
    static let lowBatteryRange = 5...50
    /// 59b: one low level for the Mac. The Notifications page owns it; a value stored here before that
    /// page existed is still read, so upgrading does not silently change a user's tint level.
    static func lowBatteryThreshold(_ d: UserDefaults = .standard) -> Int {
        let shared = (d.object(forKey: PowerNotificationRules.Storage.lowThreshold) as? Int).flatMap { $0 == 0 ? nil : $0 }
        let v = shared ?? (d.object(forKey: lowBatteryThresholdKey) as? Int) ?? defaultLowBatteryThreshold
        return min(lowBatteryRange.upperBound, max(lowBatteryRange.lowerBound, v))
    }

    static let hoverDelayKey = "com.katikati.notch.hoverDelay"
    static let closeDelayKey = "com.katikati.notch.closeDelay"
    static let hapticKey = "com.katikati.notch.haptic"
    static let musicBatteryKey = "com.katikati.notch.musicBattery"
    static let defaultHoverDelay = 0.05
    static let defaultCloseDelay = 0.25
    static let hoverDelayRange = 0.0...1.0
    static let closeDelayRange = 0.10...2.0

    static func clamp(_ v: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        v.isFinite ? min(range.upperBound, max(range.lowerBound, v)) : fallback
    }

    static func hoverDelay(_ d: UserDefaults = .standard) -> Double {
        clamp(d.object(forKey: hoverDelayKey) as? Double ?? defaultHoverDelay, hoverDelayRange, fallback: defaultHoverDelay)
    }

    static func closeDelay(_ d: UserDefaults = .standard) -> Double {
        clamp(d.object(forKey: closeDelayKey) as? Double ?? defaultCloseDelay, closeDelayRange, fallback: defaultCloseDelay)
    }

    static func haptic(_ d: UserDefaults = .standard) -> Bool {
        d.object(forKey: hapticKey) as? Bool ?? true
    }

    static func showBatteryDuringMusic(_ d: UserDefaults = .standard) -> Bool {
        d.object(forKey: musicBatteryKey) as? Bool ?? true
    }
}

/// Open-panel size presets, after vorssaint-utils' Layout tab. KatiKati's pages are laid out at one size
/// and scaled, so a preset is a width multiplier (height follows the aspect ratio).
enum NotchSizePreset: String, CaseIterable {
    case compact, standard, spacious, custom

    static let defaultsKey = "com.katikati.notch.sizePreset"
    static let customScaleKey = "com.katikati.notch.customScale"
    static let customScaleRange = 0.70...1.30
    static let outlineKey = "com.katikati.notch.outline"
    static let translucentKey = "com.katikati.notch.translucent"

    static func scale(preset raw: String, custom: Double) -> CGFloat {
        switch NotchSizePreset(rawValue: raw) ?? .standard {
        case .compact: return 0.85
        case .standard: return 1
        case .spacious: return 1.2
        case .custom: return CGFloat(NotchBehavior.clamp(custom, customScaleRange, fallback: 1))
        }
    }

    static func current(_ d: UserDefaults = .standard) -> CGFloat {
        scale(preset: d.string(forKey: defaultsKey) ?? "", custom: d.object(forKey: customScaleKey) as? Double ?? 1)
    }
}

// MARK: - Time Travel, Focus Deferral & Sixth-Sense Backoff

struct NotchTimeTravelEntry: Equatable, Sendable, Identifiable {
    let id: UUID
    let icon: String
    let title: String
    let subtitle: String?
    let timestamp: Date

    init(
        id: UUID = UUID(),
        icon: String,
        title: String,
        subtitle: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.timestamp = timestamp
    }
}

/// Fixed-capacity ring buffer of recent notch events supporting `Option+Scroll` time travel.
struct NotchTimeTravelBuffer: Equatable, Sendable {
    static let maxCapacity = 25
    private(set) var entries: [NotchTimeTravelEntry] = []
    private(set) var cursor: Int?

    var currentPosition: (index: Int, total: Int)? {
        guard let cursor, entries.indices.contains(cursor) else { return nil }
        return (cursor + 1, entries.count)
    }

    mutating func record(_ entry: NotchTimeTravelEntry) {
        entries.append(entry)
        if entries.count > Self.maxCapacity {
            entries.removeFirst(entries.count - Self.maxCapacity)
        }
        cursor = nil
    }

    mutating func step(delta: Int) -> NotchTimeTravelEntry? {
        guard !entries.isEmpty else {
            cursor = nil
            return nil
        }
        let next: Int
        if let current = cursor {
            next = min(max(current + delta, 0), entries.count - 1)
        } else {
            next = entries.count - 1
        }
        cursor = next
        return entries[next]
    }

    mutating func resetCursor() {
        cursor = nil
    }
}

/// Holds non-critical notch alerts while macOS Focus is active and flushes a summary afterwards.
struct DeferredFocusQueue: Equatable, Sendable {
    private(set) var held: [NotchTimeTravelEntry] = []

    /// Returns `true` when the alert should display immediately, or `false` if held for Focus.
    mutating func shouldPresentImmediately(
        _ entry: NotchTimeTravelEntry,
        isCritical: Bool,
        isFocusActive: Bool
    ) -> Bool {
        if isCritical || !isFocusActive {
            return true
        }
        held.append(entry)
        return false
    }

    mutating func flush() -> (items: [NotchTimeTravelEntry], summary: String?) {
        guard !held.isEmpty else { return ([], nil) }
        let items = held
        held.removeAll()
        let summary: String
        if items.count == 1, let first = items.first {
            summary = "1 update held while in Focus: \(first.title)"
        } else {
            summary = "\(items.count) updates held while in Focus"
        }
        return (items, summary)
    }
}

/// Mutes recurring Sixth-Sense suggestions for a rule key after 5 dismissals until accepted or reset.
struct SuggestionBackoffTracker: Equatable, Sendable {
    static let dismissalThreshold = 5
    static let defaultsKey = "com.katikati.notch.suggestionDismissals"
    private(set) var dismissals: [String: Int]

    init(dismissals: [String: Int] = [:]) {
        self.dismissals = dismissals
    }

    func shouldSuggest(ruleKey: String) -> Bool {
        (dismissals[ruleKey] ?? 0) < Self.dismissalThreshold
    }

    mutating func recordDismissal(ruleKey: String) {
        dismissals[ruleKey, default: 0] += 1
    }

    mutating func recordAccepted(ruleKey: String) {
        dismissals.removeValue(forKey: ruleKey)
    }

    mutating func reset(ruleKey: String? = nil) {
        if let ruleKey {
            dismissals.removeValue(forKey: ruleKey)
        } else {
            dismissals.removeAll()
        }
    }

    static func load(_ defaults: UserDefaults = .standard) -> SuggestionBackoffTracker {
        let dict = defaults.dictionary(forKey: defaultsKey) as? [String: Int] ?? [:]
        return SuggestionBackoffTracker(dismissals: dict)
    }

    func save(_ defaults: UserDefaults = .standard) {
        defaults.set(dismissals, forKey: Self.defaultsKey)
    }
}

struct TimeTravelPreview: Equatable, Sendable {
    let entry: NotchTimeTravelEntry
    let index: Int
    let total: Int
}

/// Shared Time Travel, Focus Deferral & Sixth-Sense Backoff bus across Notch and Dock surfaces.
@MainActor
final class SurfaceTimeTravelCoordinator: ObservableObject {
    static let shared = SurfaceTimeTravelCoordinator()

    @Published private(set) var buffer = NotchTimeTravelBuffer()
    @Published private(set) var activePreview: TimeTravelPreview?
    @Published var suggestionBackoff = SuggestionBackoffTracker.load()

    private var focusQueue = DeferredFocusQueue()
    private var previewExpireWork: DispatchWorkItem?
    private var scrollDelta: CGFloat = 0

    var heldFocusCount: Int { focusQueue.held.count }

    func record(_ entry: NotchTimeTravelEntry) {
        buffer.record(entry)
    }

    @discardableResult
    func step(delta: Int) -> TimeTravelPreview? {
        guard let entry = buffer.step(delta: delta), let pos = buffer.currentPosition else { return nil }
        let preview = TimeTravelPreview(entry: entry, index: pos.index, total: pos.total)
        activePreview = preview
        schedulePreviewClear()
        return preview
    }

    @discardableResult
    func scrub(deltaY: CGFloat, hasPreciseDeltas: Bool) -> TimeTravelPreview? {
        guard !buffer.entries.isEmpty else { return nil }
        let stepDir: Int?
        if !hasPreciseDeltas {
            scrollDelta = 0
            stepDir = abs(deltaY) > 0.01 ? (deltaY > 0 ? -1 : 1) : nil
        } else {
            scrollDelta += deltaY
            if abs(scrollDelta) >= 28 {
                stepDir = scrollDelta > 0 ? -1 : 1
                scrollDelta = 0
            } else {
                stepDir = nil
            }
        }
        guard let stepDir else { return nil }
        return step(delta: stepDir)
    }

    func resetScrollAccumulator() {
        scrollDelta = 0
    }

    func shouldDeliverImmediately(
        _ entry: NotchTimeTravelEntry,
        isCritical: Bool,
        isFocusActive: Bool
    ) -> Bool {
        focusQueue.shouldPresentImmediately(entry, isCritical: isCritical, isFocusActive: isFocusActive)
    }

    func flushFocusQueue() -> (items: [NotchTimeTravelEntry], summary: String?) {
        let flushed = focusQueue.flush()
        for item in flushed.items {
            buffer.record(item)
        }
        return flushed
    }

    func dismissSuggestion(ruleKey: String) {
        suggestionBackoff.recordDismissal(ruleKey: ruleKey)
        suggestionBackoff.save()
    }

    func acceptSuggestion(ruleKey: String) {
        suggestionBackoff.recordAccepted(ruleKey: ruleKey)
        suggestionBackoff.save()
    }

    func resetSuggestion(ruleKey: String? = nil) {
        suggestionBackoff.reset(ruleKey: ruleKey)
        suggestionBackoff.save()
    }

    private func schedulePreviewClear() {
        previewExpireWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.activePreview = nil
            self?.buffer.resetCursor()
        }
        previewExpireWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }
}
