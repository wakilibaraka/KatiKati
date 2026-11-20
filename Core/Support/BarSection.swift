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

    /// True only when both the preset and placement allow an anchored pointer (`v` / `<` / `>`).
    func resolvesArrowVisible(for placement: UtilityPopoverPlacement, isVerticalRail: Bool = false) -> Bool {
        guard placement == .anchored else { return false }
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

// MARK: - Modular Dock (slice MD-1)

/// One addressable slot on the modular Dock. `aiTracking` is not `ai`: `BarSection.ai` and
/// `DockWidgetPresetType.ai` already exist, and a third `.ai` makes unqualified use ambiguous.
///
/// `apps` is deliberately absent — the apps island is structural (running-app chips), so `.apps`
/// uniqueness is asserted on the derived section order instead of being a duplicable slot.
enum DockSlotItem: String, CaseIterable, Codable, Identifiable, Sendable {
    case weather
    case launcher
    case drawer
    case shelf
    case backgroundApps
    case music
    case clockCalendar
    case controlCenter
    case screenshots
    case clipboard
    case dictionary
    case terminal
    case downloads
    case trash
    case aiTracking

    var id: String { rawValue }

    /// The app-level icon this slot already stands for, so the apps strip can drop it (I3).
    var bundleID: String? { utilityKind?.bundleID }

    var utilityKind: DockUtilityKind? {
        switch self {
        case .drawer: return .drawer
        case .screenshots: return .screenshots
        case .clipboard: return .clipboard
        case .dictionary: return .dictionary
        case .terminal: return .terminal
        case .downloads: return .downloads
        case .trash: return .trash
        case .weather, .launcher, .shelf, .backgroundApps, .music, .clockCalendar,
             .controlCenter, .aiTracking: return nil
        }
    }

    /// The section this slot renders as. `shelf`, `backgroundApps` and `controlCenter` are
    /// strip-level blocks — `BarSection` has no case for them, so they map to nil.
    var section: BarSection? {
        switch self {
        case .weather: return .weather
        case .launcher: return .launcher
        case .drawer, .screenshots, .clipboard, .downloads, .trash: return .utilities
        case .music: return .media
        case .clockCalendar: return .clock
        case .dictionary: return .dictionary
        case .terminal: return .terminal
        case .aiTracking: return .ai
        case .shelf, .backgroundApps, .controlCenter: return nil
        }
    }

    var isCapsuleEligible: Bool { self == .controlCenter }

    /// Settings label. Every name but `Control Centre` already existed as a localized key.
    var title: String {
        switch self {
        case .weather: return String(localized: "Weather")
        case .launcher: return String(localized: "Launcher")
        case .drawer: return String(localized: "Drawer")
        case .shelf: return String(localized: "Shelf")
        case .backgroundApps: return String(localized: "Background Apps")
        case .music: return String(localized: "Now Playing")
        case .clockCalendar: return String(localized: "Clock & Date")
        case .controlCenter: return String(localized: "Control Centre")
        case .screenshots: return String(localized: "Screenshots")
        case .clipboard: return String(localized: "Clipboard")
        case .dictionary: return String(localized: "Dictionary")
        case .terminal: return String(localized: "Terminal")
        case .downloads: return String(localized: "Downloads")
        case .trash: return String(localized: "Trash")
        case .aiTracking: return String(localized: "AI")
        }
    }

    /// Where this slot sits relative to the structural apps island. `music` rides with the apps
    /// island except in `.split4`, mirroring `BarSection.rawIslands`.
    var clusterAffinity: DockSlotClusterAffinity {
        switch self {
        case .weather, .drawer, .launcher: return .leading
        case .music: return .ridesWithApps
        case .shelf, .backgroundApps, .clockCalendar, .controlCenter, .screenshots,
             .clipboard, .dictionary, .terminal, .downloads, .trash, .aiTracking: return .trailing
        }
    }
}

enum DockSlotClusterAffinity: String, Codable, Sendable {
    case leading
    case ridesWithApps
    case trailing
}

/// One slot plus its hidden flag. Presence in `items` keeps a hidden slot's position (I2).
struct DockSlotEntry: Codable, Equatable, Sendable, Identifiable {
    var item: DockSlotItem
    var isHidden: Bool

    var id: DockSlotItem { item }

    enum CodingKeys: String, CodingKey { case item, isHidden }
}

/// The one ordered Dock layout (I1). Decoding never normalises or reorders.
struct DockSlotLayout: Codable, Equatable, Sendable {
    /// MD-2 writes this. MD-1 only declares it.
    static let defaultsKey = "com.katikati.dock.slotLayout.v1"

    var items: [DockSlotEntry]
    var trailingCapsule: DockSlotItem?
    var groupAdjacentUtilities: Bool

    init(items: [DockSlotEntry], trailingCapsule: DockSlotItem? = nil, groupAdjacentUtilities: Bool = true) {
        self.items = items
        self.trailingCapsule = trailingCapsule
        self.groupAdjacentUtilities = groupAdjacentUtilities
    }

    /// Strip order for every slot, `controlCenter` last so repair can restore it.
    static let defaultPresetOrder: [DockSlotItem] = [
        .weather, .drawer, .launcher, .music, .clockCalendar, .shelf, .backgroundApps,
        .screenshots, .clipboard, .dictionary, .terminal, .downloads, .trash,
        .aiTracking, .controlCenter,
    ]

    static let defaultHidden: Set<DockSlotItem> = [.aiTracking]

    static let `default` = DockSlotLayout(
        items: defaultPresetOrder.filter { $0 != .controlCenter }.map {
            DockSlotEntry(item: $0, isHidden: defaultHidden.contains($0))
        },
        trailingCapsule: .controlCenter
    )

    /// Strip-visible slots in order. The capsule is not in `items`, so it never appears here (I4).
    var visibleItems: [DockSlotItem] { items.filter { !$0.isHidden }.map(\.item) }

    /// Every slot in strip order, the capsule-hosted one included last.
    var orderedItems: [DockSlotItem] { visibleItems + (trailingCapsule.map { [$0] } ?? []) }

    enum CodingKeys: String, CodingKey { case items, trailingCapsule, groupAdjacentUtilities }

    /// Tolerant by design: a schema change must not throw on the launch path (I6).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try? c.decodeIfPresent([LenientSlotEntry].self, forKey: .items)
        let decoded = (raw ?? nil)?.compactMap(\.entry) ?? []
        self.items = decoded.isEmpty ? Self.default.items : decoded
        self.trailingCapsule = (try? c.decodeIfPresent(DockSlotItem.self, forKey: .trailingCapsule)) ?? nil
        self.groupAdjacentUtilities = (try? c.decodeIfPresent(Bool.self, forKey: .groupAdjacentUtilities)) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(items, forKey: .items)
        try c.encodeIfPresent(trailingCapsule, forKey: .trailingCapsule)
        try c.encode(groupAdjacentUtilities, forKey: .groupAdjacentUtilities)
    }

    private struct LenientSlotEntry: Decodable {
        let entry: DockSlotEntry?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: DockSlotEntry.CodingKeys.self)
            guard let raw = try c.decodeIfPresent(String.self, forKey: .item),
                  let item = DockSlotItem(rawValue: raw) else {
                entry = nil
                return
            }
            entry = DockSlotEntry(item: item,
                                  isHidden: try c.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false)
        }
    }

    /// Main-axis length of a side rail, computed **after** capsule extraction and hidden removal.
    /// Adjacent utility slots form one cluster when `groupAdjacentUtilities` is set, matching the
    /// legacy `.utilities` tile length. `barHeight` is accepted for parity with
    /// `BarSection.railTileLength`; rail tiles are a fixed square today.
    func railTileLength(barHeight: CGFloat) -> CGFloat {
        var groups: [[DockSlotItem]] = []
        for item in visibleItems {
            let joinsPrevious = groupAdjacentUtilities && item.utilityKind != nil
                && groups.last?.last?.utilityKind != nil
            if joinsPrevious {
                groups[groups.count - 1].append(item)
            } else {
                groups.append([item])
            }
        }
        var total: CGFloat = 0
        for (index, group) in groups.enumerated() {
            if index > 0 { total += IslandChrome.railChipSpacing }
            let allUtilities = group.allSatisfy { $0.utilityKind != nil }
            if allUtilities && group.count > 1 {
                total += BarSection.utilitiesRailLength(visibleCount: group.count)
            } else {
                total += CGFloat(group.count) * BarSection.railTileSize
            }
        }
        return total
    }
}

/// One island for a layout mode. `index` is the 0-based island order.
struct DockSlotCluster: Equatable, Sendable, Identifiable {
    var index: Int
    var items: [DockSlotItem]
    /// True for the structural apps island, which holds running-app chips rather than slots.
    var containsApps: Bool

    var id: Int { index }
}

/// Pure, total, non-throwing repair and derivation.
enum DockModularityValidator {
    /// Duplicates collapse (first occurrence wins), the capsule wins over a strip copy, an
    /// ineligible capsule item is demoted, and missing items are restored at preset positions.
    /// Hidden flags and custom order are never disturbed (I2).
    static func validate(_ layout: DockSlotLayout) -> DockSlotLayout {
        var capsule = layout.trailingCapsule
        if let candidate = capsule, !candidate.isCapsuleEligible { capsule = nil }

        var kept: [DockSlotEntry] = []
        var seen = Set<DockSlotItem>()
        for entry in layout.items {
            if let capsule, entry.item == capsule { continue }
            guard seen.insert(entry.item).inserted else { continue }
            kept.append(entry)
        }
        if let capsule { seen.insert(capsule) }

        for item in DockSlotLayout.defaultPresetOrder where !seen.contains(item) {
            let entry = DockSlotEntry(item: item, isHidden: DockSlotLayout.defaultHidden.contains(item))
            kept.insert(entry, at: insertionIndex(for: item, in: kept))
            seen.insert(item)
        }
        return DockSlotLayout(items: kept,
                              trailingCapsule: capsule,
                              groupAdjacentUtilities: layout.groupAdjacentUtilities)
    }

    /// Rule check without repair, so tests can prove a repair happened.
    static func isModular(_ layout: DockSlotLayout) -> Bool {
        let all = layout.items.map(\.item) + (layout.trailingCapsule.map { [$0] } ?? [])
        guard all.count == DockSlotItem.allCases.count, Set(all).count == all.count else { return false }
        if let capsule = layout.trailingCapsule, !capsule.isCapsuleEligible { return false }
        return derivedSections(for: layout).filter { $0 == .apps }.count == 1
    }

    /// Island shapes matching `BarSection.rawIslands` (L158–190).
    static func clusters(for layout: DockSlotLayout, mode: BarLayoutMode) -> [DockSlotCluster] {
        let visible = layout.visibleItems
        let leading = visible.filter { $0.clusterAffinity == .leading }
        let rides = visible.filter { $0.clusterAffinity == .ridesWithApps }
        let trailing = visible.filter { $0.clusterAffinity == .trailing }

        var shapes: [(apps: Bool, items: [DockSlotItem])]
        switch mode {
        case .windows, .centered:
            shapes = [(true, visible)]
        case .split3:
            shapes = [(false, leading), (true, rides), (false, trailing)]
        case .split4:
            shapes = [(false, leading), (true, []), (false, rides), (false, trailing)]
        case .split5:
            shapes = leading.map { (false, [$0]) } + [(true, rides)] + trailing.map { (false, [$0]) }
        }

        var result: [DockSlotCluster] = []
        for shape in shapes where shape.apps || !shape.items.isEmpty {
            result.append(DockSlotCluster(index: result.count, items: shape.items, containsApps: shape.apps))
        }
        return result
    }

    /// `BarSection` order this layout produces, with the structural apps island inserted once.
    static func derivedSections(for layout: DockSlotLayout,
                                mode: BarLayoutMode = .windows) -> [BarSection] {
        var result: [BarSection] = []
        for cluster in clusters(for: layout, mode: mode) {
            // Inside a mixed island the apps chips sit after the leading slots, not at its head.
            var emittedApps = false
            for item in cluster.items {
                if cluster.containsApps, !emittedApps, item.clusterAffinity != .leading {
                    result.append(.apps)
                    emittedApps = true
                }
                if let section = item.section { result.append(section) }
            }
            if cluster.containsApps, !emittedApps { result.append(.apps) }
        }
        return result
    }

    /// The strip's render order (slice MD-3a): the slot layout owns every section it has a slot for,
    /// and the sections it has none for (`system`, `devices`, `drives`, `widgets`) are spliced back
    /// after their nearest predecessor in the legacy order. Without that splice the switch would
    /// silently delete enabled widgets the slot model never modelled.
    static func renderOrder(for layout: DockSlotLayout,
                            mode: BarLayoutMode = .windows,
                            legacyOrder: [BarSection] = []) -> [BarSection] {
        // Several slots (the seven utilities) stand for one section: the strip draws that section
        // once, so repeats collapse to their first position.
        var seen = Set<BarSection>()
        var result = derivedSections(for: layout, mode: mode).filter { seen.insert($0).inserted }
        // Only sections this model has no slot for are spliced back; a slot-backed section that the
        // layout hides must disappear, not return from the legacy list.
        let slotBacked = Set(DockSlotItem.allCases.compactMap(\.section))
        for extra in legacyOrder
        where extra != .apps && !slotBacked.contains(extra) && !result.contains(extra) {
            guard let index = legacyOrder.firstIndex(of: extra) else { continue }
            let anchor = legacyOrder[..<index].last { result.contains($0) }
            let at = anchor.flatMap { result.lastIndex(of: $0) }.map { $0 + 1 } ?? result.count
            result.insert(extra, at: at)
        }
        return result
    }

    static func insertionIndex(for item: DockSlotItem, in items: [DockSlotEntry]) -> Int {
        let preset = DockSlotLayout.defaultPresetOrder
        guard let target = preset.firstIndex(of: item) else { return items.count }
        for (offset, entry) in items.enumerated() {
            guard let index = preset.firstIndex(of: entry.item) else { continue }
            if index > target { return offset }
        }
        return items.count
    }
}

// MARK: - Capsule-aware deduplication (additive, slice MD-1)

extension DockToolDeduplication {
    /// Bundle IDs the layout already stands for. Hidden slots own nothing (I3).
    static func suppressedAppBundleIDs(slotLayout: DockSlotLayout) -> Set<String> {
        Set(slotLayout.orderedItems.compactMap(\.bundleID))
    }

    static func visibleAppBundleIDs(_ bundleIDs: [String], slotLayout: DockSlotLayout) -> [String] {
        let suppressed = suppressedAppBundleIDs(slotLayout: slotLayout)
        return bundleIDs.filter { !suppressed.contains($0) }
    }
}

// MARK: - Modular Dock legacy migration (slice MD-2)

extension DockSlotLayout {
    static func decode(_ data: Data?) -> DockSlotLayout? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(DockSlotLayout.self, from: data)
    }

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    /// Main-axis length of the utilities cluster on a side rail, counted from the **slots** rather
    /// than `DockUtilitiesConfig`, so hiding a utility moves the rail by exactly one tile.
    var utilitiesRailLength: CGFloat {
        let count = visibleItems.filter { $0.utilityKind != nil }.count
        guard count > 1 else { return CGFloat(count) * BarSection.railTileSize }
        return BarSection.utilitiesRailLength(visibleCount: count)
    }

    /// One-time translation of the pre-modular state into a slot layout.
    ///
    /// Order first: the user's section order and the utilities cluster order are carried over as-is,
    /// with every hidden flag intact, so nothing that was positioned moves (I2). Promoted blocks —
    /// slots `BarSection` has no case for, plus `launcher`/`controlCenter` — are only then inserted at
    /// their preset positions, and never in front of nothing, never displacing a user item (step 3).
    /// `validate` fills whatever the legacy state never mentioned; it never reorders what is there.
    static func migrating(utilities: DockUtilitiesConfig,
                          sectionOrder: [BarSection],
                          hiddenSections: Set<BarSection> = [],
                          shelfVisible: Bool = true,
                          backgroundAppsVisible: Bool = true,
                          capsuleEnabled: Bool = true) -> DockSlotLayout {
        let visibleModules = Set(sectionOrder.filter { !hiddenSections.contains($0) })
        var entries: [DockSlotEntry] = []
        var seen = Set<DockSlotItem>()
        for section in sectionOrder {
            for item in slots(for: section, utilities: utilities) where seen.insert(item).inserted {
                entries.append(DockSlotEntry(
                    item: item,
                    isHidden: isHidden(item, in: section, visibleModules: visibleModules, utilities: utilities)
                ))
            }
        }

        let promoted: [(DockSlotItem, Bool)] = [
            (.launcher, false),
            (.shelf, !shelfVisible),
            (.backgroundApps, !backgroundAppsVisible),
            (.controlCenter, false),
        ]
        for (item, hidden) in promoted where seen.insert(item).inserted {
            entries.insert(DockSlotEntry(item: item, isHidden: hidden),
                           at: DockModularityValidator.insertionIndex(for: item, in: entries))
        }

        return DockModularityValidator.validate(
            DockSlotLayout(items: entries, trailingCapsule: capsuleEnabled ? .controlCenter : nil)
        )
    }

    /// Makes the capsule agree with the legacy `controlCentreTrailing` flag, which stays the
    /// authority for installs that shipped before the slot model.
    ///
    /// MD-2's migration always parked Control Centre in the capsule, so an install that had the disc
    /// on the strip ended up with a layout claiming the capsule while the flag (and therefore the
    /// strip's own drawing) said otherwise — Settings showed one placement and the bar rendered the
    /// other. Reconciling in the flag's direction leaves what a user sees untouched.
    static func reconciled(_ layout: DockSlotLayout, controlCentreTrailing: Bool) -> DockSlotLayout {
        guard (layout.trailingCapsule == .controlCenter) != controlCentreTrailing else { return layout }
        var items = layout.items.filter { $0.item != .controlCenter }
        if !controlCentreTrailing {
            items.insert(DockSlotEntry(item: .controlCenter, isHidden: false),
                         at: DockModularityValidator.insertionIndex(for: .controlCenter, in: items))
        }
        return DockModularityValidator.validate(
            DockSlotLayout(items: items,
                           trailingCapsule: controlCentreTrailing ? .controlCenter : nil,
                           groupAdjacentUtilities: layout.groupAdjacentUtilities)
        )
    }

    /// The slots a legacy section hosted, in the order that section painted them.
    private static func slots(for section: BarSection, utilities: DockUtilitiesConfig) -> [DockSlotItem] {
        switch section {
        case .weather: return [.weather]
        case .launcher: return [.launcher]
        case .media: return [.music]
        case .utilities: return utilities.order.map(slot(for:))
        case .clock, .calendar: return [.clockCalendar]
        case .dictionary: return [.dictionary]
        case .terminal: return [.terminal]
        case .ai: return [.aiTracking]
        case .apps, .system, .devices, .drives, .widgets: return []
        }
    }

    private static func slot(for kind: DockUtilityKind) -> DockSlotItem {
        switch kind {
        case .drawer: return .drawer
        case .screenshots: return .screenshots
        case .clipboard: return .clipboard
        case .dictionary: return .dictionary
        case .terminal: return .terminal
        case .downloads: return .downloads
        case .trash: return .trash
        }
    }

    /// DI-1 keeps one stored truth per tool: either its utilities-cluster membership or its own
    /// section. Visible in either place means the slot comes back visible.
    private static func isHidden(_ item: DockSlotItem,
                                 in section: BarSection,
                                 visibleModules: Set<BarSection>,
                                 utilities: DockUtilitiesConfig) -> Bool {
        switch item {
        case .dictionary:
            return !(visibleModules.contains(.dictionary)
                || !utilities.hidden.contains(.dictionary))
        case .terminal:
            return !(visibleModules.contains(.terminal)
                || !utilities.hidden.contains(.terminal))
        default:
            guard let kind = item.utilityKind else { return !visibleModules.contains(section) }
            return utilities.hidden.contains(kind)
        }
    }
}
