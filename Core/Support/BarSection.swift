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
    case utilities
    case clock
    /// Date badge + next meeting with its countdown; hover lists upcoming meetings with a Join button.
    case calendar
    /// CPU / RAM / SSD at a glance; hover shows the four sparklines.
    case system
    /// Battery levels of connected AirPods / mouse / keyboard.
    case devices
    /// Free space of every mounted drive, and the DiskView panel on hover.
    case drives
    /// Look-up card for any word: opens the dictionary panel. Lives in Utilities by default.
    case dictionary
    /// Shell in a floating panel (SwiftTerm). Lives in Utilities by default.
    case terminal
    /// AI usage spend, live agent heartbeat, inline approvals, and Loadout presets. On by default.
    case ai
    case widgets

    /// Canonical left-to-right order (Phase 4U-A).
    static let canonicalOrder: [BarSection] = [.launcher, .weather, .apps, .media, .utilities, .clock, .calendar, .system, .devices, .drives, .dictionary, .terminal, .ai, .widgets]

    /// The core sections a fresh dock shows.
    static let defaultOrder: [BarSection] = canonicalOrder.filter { !$0.startsHidden }

    /// Widgets added after the core strip start hidden unless enabled in Settings.
    var startsHidden: Bool {
        switch self {
        case .calendar, .system, .devices, .drives, .dictionary, .terminal: return true
        case .launcher, .weather, .apps, .media, .utilities, .clock, .widgets, .ai: return false
        }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .launcher: return "Launcher"
        case .weather: return "Weather"
        case .apps: return "Apps"
        case .media: return "Now Playing"
        case .utilities: return "Utilities"
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
        case .utilities: return 112
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
        case .calendar, .system, .devices, .drives, .dictionary, .terminal, .ai, .utilities: return 56
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
        case .calendar, .system, .devices, .drives, .dictionary, .terminal, .ai, .utilities: return true
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
    static func suppressedAppBundleIDs(enabledSections: [BarSection], dockUtilities: DockUtilitiesConfig? = nil) -> Set<String> {
        var ids = Set(enabledSections.compactMap { bundleIDBySection[$0] })
        if enabledSections.contains(.utilities), let dockUtilities {
            ids.formUnion(dockUtilities.suppressedAppBundleIDs())
        }
        return ids
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

/// Modular utility tiles hosted in the Mid-Dock Utilities cluster.
enum DockUtilityKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case drawer
    case screenshots
    case clipboard
    case dictionary
    case terminal
    case downloads
    case trash

    var id: String { rawValue }

    var bundleID: String? {
        switch self {
        case .dictionary: return "com.apple.Dictionary"
        case .terminal: return "com.apple.Terminal"
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .drawer: return String(localized: "Drawer")
        case .screenshots: return String(localized: "Screenshots")
        case .clipboard: return String(localized: "Clipboard")
        case .dictionary: return String(localized: "Dictionary")
        case .terminal: return String(localized: "Terminal")
        case .downloads: return String(localized: "Downloads")
        case .trash: return String(localized: "Trash")
        }
    }

    var symbolName: String {
        switch self {
        case .drawer: return "square.grid.2x2"
        case .screenshots: return "viewfinder"
        case .clipboard: return "doc.on.clipboard"
        case .dictionary: return "text.book.closed"
        case .terminal: return "terminal"
        case .downloads: return "arrow.down.circle"
        case .trash: return "trash"
        }
    }
}

/// Where Dock utility cards & flyouts (Terminal, Dictionary, Screenshots, Clipboard, Downloads, Drawer) open.
enum UtilityPopoverPlacement: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Anchored directly above (or beside, on a vertical rail) its Dock icon with a `v` pointer when enabled.
    case anchored
    /// Floating cleanly above the Dock centered horizontally on screen (no `v` pointer).
    case bottomFloat
    /// Floating centered in the active display (no `v` pointer).
    case centerFloat

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .anchored: return String(localized: "Anchored (v)")
        case .bottomFloat: return String(localized: "Bottom Float")
        case .centerFloat: return String(localized: "Center Float")
        }
    }
}

/// Visual preset for Downloads, Screenshots, Clipboard, and utility flyouts.
enum UtilityFlyoutPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Rich Shelf-inspired card deck anchored with the downward `v` pointer.
    case shelfDeck
    /// Classic compact multi-column icon grid anchored with the downward `v` pointer.
    case compactGrid
    /// Borderless floating Shelf-style glass deck without any `v` arrow stem.
    case cleanFloat

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .shelfDeck: return String(localized: "Shelf Deck (v)")
        case .compactGrid: return String(localized: "Compact Grid (v)")
        case .cleanFloat: return String(localized: "Clean Float (No v)")
        }
    }

    /// True only when both the preset and placement allow an anchored `v` pointer.
    func resolvesArrowVisible(for placement: UtilityPopoverPlacement, isVerticalRail: Bool = false) -> Bool {
        guard !isVerticalRail, placement == .anchored else { return false }
        return self != .cleanFloat
    }
}

/// Dismissal rule when clicking outside or pressing Esc on Terminal, Dictionary, and utility cards.
enum UtilityDismissalBehavior: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Default: Terminal stays open across focus switches until explicitly closed; Dictionary & flyouts dismiss on outside click.
    case persistentTerminal
    /// Dismisses on outside click when anchored with `v`, and stays open when floating at Bottom or Center.
    case transientWhenAnchored
    /// All panels dismiss on outside click/Esc unless locked open via their header Pin toggle.
    case unifiedWithPin

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .persistentTerminal: return String(localized: "Persistent Terminal")
        case .transientWhenAnchored: return String(localized: "Transient Anchored")
        case .unifiedWithPin: return String(localized: "Click-Outside + Pin")
        }
    }

    func dismissesOnOutsideClick(isTerminal: Bool, placement: UtilityPopoverPlacement, isPinned: Bool) -> Bool {
        if isPinned { return false }
        switch self {
        case .persistentTerminal:
            return !isTerminal
        case .transientWhenAnchored:
            return placement == .anchored
        case .unifiedWithPin:
            return true
        }
    }
}

/// Pure ordered + visibility state for Mid-Dock Utilities modularity.
struct DockUtilitiesConfig: Codable, Equatable, Sendable {
    static let defaultsKey = "com.katikati.dock.utilitiesConfig.v1"

    var order: [DockUtilityKind]
    var hidden: Set<DockUtilityKind>
    var popoverPlacement: UtilityPopoverPlacement
    var flyoutPreset: UtilityFlyoutPreset
    var dismissalBehavior: UtilityDismissalBehavior

    static let defaultOrder: [DockUtilityKind] = [
        .drawer, .screenshots, .clipboard, .dictionary, .terminal, .downloads, .trash
    ]

    init(
        order: [DockUtilityKind] = defaultOrder,
        hidden: Set<DockUtilityKind> = [],
        popoverPlacement: UtilityPopoverPlacement = .anchored,
        flyoutPreset: UtilityFlyoutPreset = .shelfDeck,
        dismissalBehavior: UtilityDismissalBehavior = .persistentTerminal
    ) {
        self.order = Self.normalizedOrder(order)
        self.hidden = hidden
        self.popoverPlacement = popoverPlacement
        self.flyoutPreset = flyoutPreset
        self.dismissalBehavior = dismissalBehavior
    }

    enum CodingKeys: String, CodingKey {
        case order, hidden, popoverPlacement, flyoutPreset, dismissalBehavior
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let order = try c.decodeIfPresent([DockUtilityKind].self, forKey: .order) ?? Self.defaultOrder
        let hidden = try c.decodeIfPresent(Set<DockUtilityKind>.self, forKey: .hidden) ?? []
        let placement = try c.decodeIfPresent(UtilityPopoverPlacement.self, forKey: .popoverPlacement) ?? .anchored
        let preset = try c.decodeIfPresent(UtilityFlyoutPreset.self, forKey: .flyoutPreset) ?? .shelfDeck
        let dismissal = try c.decodeIfPresent(UtilityDismissalBehavior.self, forKey: .dismissalBehavior) ?? .persistentTerminal
        self.init(order: order, hidden: hidden, popoverPlacement: placement, flyoutPreset: preset, dismissalBehavior: dismissal)
    }

    static let `default` = DockUtilitiesConfig()

    var visibleUtilities: [DockUtilityKind] {
        order.filter { !hidden.contains($0) }
    }

    var effectivePlacementForPreset: UtilityPopoverPlacement {
        if flyoutPreset == .cleanFloat && popoverPlacement == .anchored {
            return .bottomFloat
        }
        return popoverPlacement
    }

    func moving(_ item: DockUtilityKind, by delta: Int) -> DockUtilitiesConfig {
        guard let idx = order.firstIndex(of: item) else { return self }
        let target = min(max(0, idx + delta), order.count - 1)
        guard target != idx else { return self }
        var next = order
        next.remove(at: idx)
        next.insert(item, at: target)
        return DockUtilitiesConfig(
            order: next,
            hidden: hidden,
            popoverPlacement: popoverPlacement,
            flyoutPreset: flyoutPreset,
            dismissalBehavior: dismissalBehavior
        )
    }

    func setting(_ item: DockUtilityKind, visible: Bool) -> DockUtilitiesConfig {
        var nextHidden = hidden
        if visible { nextHidden.remove(item) } else { nextHidden.insert(item) }
        return DockUtilitiesConfig(
            order: order,
            hidden: nextHidden,
            popoverPlacement: popoverPlacement,
            flyoutPreset: flyoutPreset,
            dismissalBehavior: dismissalBehavior
        )
    }

    func suppressedAppBundleIDs() -> Set<String> {
        Set(visibleUtilities.compactMap(\.bundleID))
    }

    static func normalizedOrder(_ raw: [DockUtilityKind]) -> [DockUtilityKind] {
        var seen = Set<DockUtilityKind>()
        var result: [DockUtilityKind] = []
        for item in raw where seen.insert(item).inserted { result.append(item) }
        for item in defaultOrder where seen.insert(item).inserted { result.append(item) }
        return result
    }

    static func decode(_ data: Data?) -> DockUtilitiesConfig? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(DockUtilitiesConfig.self, from: data)
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }
}
