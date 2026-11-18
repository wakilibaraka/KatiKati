import CoreGraphics
import Foundation

/// Logical content sections of the taskbar.
///
/// Canonical left-to-right order is always:
/// 1. `launcher` (left FAB, inert until Phase 7d)
/// 2. `weather`
/// 3. `apps` (window chips and tungsten utilities: drawer, shelf, trash, pinned folders)
/// 4. `media` (Now Playing mini icon and popup)
/// 5. `clock` (combined clock chip & calendar popup)
/// 6. `widgets` (right FAB, inert until Phase 7e)
///
/// The `media` section is grouped with `.apps` in split modes, appearing at the
/// right end of the apps island (Phase 4U decision 2).
///
/// Across layout modes, this sequence is never rearranged; only the grouping into
/// discrete island slots varies.
enum BarSection: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case launcher
    case weather
    case apps
    case media
    case clock
    /// Date badge + next meeting with its countdown; hover lists upcoming meetings with a Join button.
    case calendar
    /// CPU / RAM / SSD at a glance; hover shows the four sparklines.
    case system
    /// Battery levels of connected AirPods / mouse / keyboard.
    case devices
    /// Free space of every mounted drive, and the DiskView panel on hover.
    case drives
    /// Look-up card for any word: opens the dictionary panel. On by default (owner 2026-11-05).
    case dictionary
    /// Shell in a floating panel (SwiftTerm). On by default.
    case terminal
    /// AI usage spend, live agent heartbeat, inline approvals, and Loadout presets. On by default.
    case ai
    case widgets

    /// Canonical left-to-right order (Phase 4U-A).
    static let canonicalOrder: [BarSection] = [.launcher, .weather, .apps, .media, .clock, .calendar, .system, .devices, .drives, .dictionary, .terminal, .ai, .widgets]

    /// The six sections a fresh dock shows: what every layout API assumes unless it is handed a real order.
    static let defaultOrder: [BarSection] = canonicalOrder.filter { !$0.startsHidden }

    /// Widgets added after the original six start hidden, so a dock upgraded in place looks exactly as it did.
    var startsHidden: Bool {
        switch self {
        case .calendar, .system, .devices, .drives: return true
        case .launcher, .weather, .apps, .media, .clock, .widgets, .dictionary, .terminal, .ai: return false
        }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .launcher: return "Launcher"
        case .weather: return "Weather"
        case .apps: return "Apps"
        case .media: return "Now Playing"
        case .clock: return "Clock"
        case .calendar: return "Calendar"
        case .system: return "System"
        case .devices: return "Devices"
        case .drives: return "Drives"
        case .dictionary: return "Dictionary"
        case .terminal: return "Terminal"
        case .ai: return "AI"
        case .widgets: return "Widgets"
        }
    }

    var placeholderEntryID: String {
        "sec-\(rawValue)"
    }

    /// The width this section's S/M/L presets are built on. Phase 4U decision 3 still holds — the order is
    /// hardcoded and widths are settings-only — but the exact-width sliders retired in Phase 40e, so a
    /// preset (or the rail's own geometry) is the only input now; nothing stores an arbitrary number here.
    ///
    /// **215 for `.media`** (Phase 49): `NowPlayingPreset.expandedCard` is the default preset and needs
    /// 215 pt to fit artwork + title + transport controls + pagination dots without cramping the apps
    /// island. Previously `DockStripView` silently bumped `.media` to 215 pt while the solver assumed 140,
    /// stealing 75 pt from the apps island.
    var defaultWidgetWidth: CGFloat {
        switch self {
        case .launcher: return 40
        case .weather: return 150
        case .apps: return 0
        case .media: return 215
        case .clock: return 160
        case .calendar: return 170
        case .system: return 150
        case .devices: return 150
        case .drives: return 130
        case .dictionary, .terminal: return 56
        case .ai: return 112
        case .widgets: return 40
        }
    }

    /// Minimum usable width: the chip's intrinsic content below this is
    /// clipped (DockStripView `.clipped()`), so stored/slider/solver widths
    /// are floored here. Clock ≈ 104 content + 20 island padding ≈ 124;
    /// weather/media keep headroom under their defaults.
    var minimumWidgetWidth: CGFloat {
        switch self {
        case .launcher: return 40
        case .weather: return 64
        case .apps: return 0
        case .media: return 72
        case .clock: return 76
        case .calendar, .system, .devices, .drives, .dictionary, .terminal, .ai: return 56
        case .widgets: return 40
        }
    }

    /// Floor for a **hand-set** width (Settings slider): the S presets are compact forms, but an exact
    /// width keeps the full pill (and the flip tiles) from clipping, so it stays at the old minimums.
    var minimumExactWidth: CGFloat {
        switch self {
        case .weather: return 110
        case .media: return 80
        case .clock: return 120
        default: return minimumWidgetWidth
        }
    }

    /// Widgets added after the six original sections: in the split modes they share the island of the section
    /// before them, so a mode keeps its slot count whichever of them are shown.
    private var joinsPreviousIsland: Bool {
        switch self {
        case .calendar, .system, .devices, .drives, .dictionary, .terminal, .ai: return true
        default: return false
        }
    }

    /// Grouping of sections into island slots for each layout mode.
    static func islands(for mode: BarLayoutMode, order: [BarSection] = BarSection.defaultOrder) -> [[BarSection]] {
        let groups = rawIslands(for: mode, order: order)
        guard mode.isSplit else { return groups }
        var merged: [[BarSection]] = []
        for group in groups {
            if group.allSatisfy(\.joinsPreviousIsland), !merged.isEmpty {
                merged[merged.count - 1] += group
            } else {
                merged.append(group)
            }
        }
        return merged
    }

    private static func rawIslands(for mode: BarLayoutMode, order: [BarSection]) -> [[BarSection]] {
        switch mode {
        case .windows, .centered:
            return [order]
        case .split3, .split4, .split5:
            // Left group, apps (+ media), right group — split4 separates media.
            guard let appsIndex = order.firstIndex(of: .apps) else {
                return [order]
            }
            let left = Array(order[..<appsIndex])
            var rightStartIndex = appsIndex + 1
            var hasMedia = false
            if rightStartIndex < order.count && order[rightStartIndex] == .media {
                hasMedia = true
                rightStartIndex += 1
            }
            let right = Array(order[rightStartIndex...])

            if mode == .split5 {
                let center: [BarSection] = hasMedia ? [.apps, .media] : [.apps]
                return left.map { [$0] } + [center] + right.map { [$0] }
            }
            // split3: media rides with apps; split4 detaches it into its own island.
            if mode == .split4 && hasMedia {
                return [left, [.apps], [.media], right].filter { !$0.isEmpty }
            }
            return [left, hasMedia ? [.apps, .media] : [.apps], right].filter { !$0.isEmpty }
        }
    }

    /// The 0-based slot index that hosts this section in the given layout mode.
    func slotIndex(for mode: BarLayoutMode, order: [BarSection] = BarSection.defaultOrder) -> Int {
        let islandGroups = Self.islands(for: mode, order: order)
        for (index, group) in islandGroups.enumerated() {
            if group.contains(self) {
                return index
            }
        }
        return 0
    }
}

/// Slice DI-1: Dictionary and Terminal are **modules** — one `BarSection`, one glyph, one switch.
///
/// Each stands for exactly one app, and that app can also reach the strip as an icon of its own
/// (Terminal running without a window, a kept app, Dictionary after a lookup). Two glyphs for one
/// tool read as a bug, so a visible module owns its app's app-level icon and the apps strip drops it.
/// Hidden modules own nothing: switching the module off brings the app icon straight back.
enum DockToolDeduplication {
    /// The app each tool module stands for. The keys are the only two modules that name a bundle.
    static let bundleIDBySection: [BarSection: String] = [
        .dictionary: "com.apple.Dictionary",
        .terminal: "com.apple.Terminal",
    ]

    /// Bundle IDs whose app-level dock icon a visible module already stands for. Takes the layout's
    /// `visibleOrder`, so hidden modules (and modules in any island) resolve here, not in the view.
    static func suppressedAppBundleIDs(enabledSections: [BarSection]) -> Set<String> {
        Set(enabledSections.compactMap { bundleIDBySection[$0] })
    }

    /// True when an app-level icon must not be drawn because its module is on the bar.
    static func isModuleOwned(_ bundleID: String?, by suppressed: Set<String>) -> Bool {
        guard let bundleID else { return false }
        return suppressed.contains(bundleID)
    }

    /// The apps strip's icon list once the visible modules have taken their apps over. Kept pure so the
    /// rule is testable without `DockStripView`; window chips are not part of this list.
    static func visibleAppBundleIDs(_ bundleIDs: [String], enabledSections: [BarSection]) -> [String] {
        let suppressed = suppressedAppBundleIDs(enabledSections: enabledSections)
        return bundleIDs.filter { !suppressed.contains($0) }
    }
}
