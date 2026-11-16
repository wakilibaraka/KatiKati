import Foundation

/// Which screen edge an edge bar (Phase 7A) hugs.
enum EdgeSide: String, CaseIterable, Sendable {
    case left
    case right
}

/// Pure calculation of edge-bar slots across displays. Parallel to `IslandSlotSet`
/// (bottom islands) — it never changes island slot semantics. Keys render as
/// `displayUUID#edge-left` / `displayUUID#edge-right`.
enum EdgeSlotSet {
    struct SlotKey: Hashable, Sendable, CustomStringConvertible {
        /// nil = follow settings (default display); otherwise the fixed display UUID.
        let display: String?
        let side: EdgeSide

        var description: String {
            "\(display ?? "follow")#edge-\(side.rawValue)"
        }
    }

    /// Desired edge slots: each display key from `TaskbarDisplaySet.desiredUnitKeys` crossed
    /// with the enabled sides, sides in `EdgeSide.allCases` order (left, right).
    static func desiredSlots(
        placement: TaskbarScreenPlacement,
        connectedKeys: [String],
        sides: Set<EdgeSide>
    ) -> [SlotKey] {
        guard !sides.isEmpty else { return [] }
        let displayKeys = TaskbarDisplaySet.desiredUnitKeys(placement: placement, connectedKeys: connectedKeys)
        return displayKeys.flatMap { display in
            EdgeSide.allCases.filter(sides.contains).map { SlotKey(display: display, side: $0) }
        }
    }
}

/// Parses a stored comma-separated id list: unknown ids dropped, duplicates collapsed, order kept.
private func parseIDList<T: RawRepresentable & Hashable>(_ stored: String?) -> [T] where T.RawValue == String {
    var seen = Set<T>()
    return (stored ?? "").split(separator: ",").compactMap { part in
        guard let item = T(rawValue: part.trimmingCharacters(in: .whitespaces)), seen.insert(item).inserted else { return nil }
        return item
    }
}

/// A widget tile (Phase 7A-8). Each tile opens its own flyout.
/// Raw values are stored in `com.katikati.widgets.tiles`; never rename them.
enum WidgetTile: String, CaseIterable, Sendable {
    case weather
    case nowPlaying
    case bluetooth
    case systemMonitor

    static func parse(_ stored: String?) -> [WidgetTile] { parseIDList(stored) }
    static func serialize(_ tiles: [WidgetTile]) -> String { tiles.map(\.rawValue).joined(separator: ",") }
}

/// A productivity button (Phase 7A-P1). Each opens its own flyout.
/// Raw values are stored in `com.katikati.productivity.items`; never rename them.
enum ProductivityItem: String, CaseIterable, Sendable {
    case reminders
    case alarms
    case time
    case tasks
    case clipboard
    case capture
    /// 13e: select an area and copy it to the clipboard (never saved to a file).
    case screenshot
    case windows
    case screenTime

    /// Items whose flyout exists. An item appears on a bar only once built (no placeholders); P2–P6 built them all,
    /// so this is the full set — a future item is added to the enum first and to this set when its flyout lands.
    static let built = Set(allCases)

    static func parse(_ stored: String?) -> [ProductivityItem] { parseIDList(stored) }
    static func serialize(_ items: [ProductivityItem]) -> String { items.map(\.rawValue).joined(separator: ",") }
}

/// What an edge bar hosts, in render order.
enum EdgeBarContent: Equatable, Sendable {
    case apps
    /// Sydedock-style glanceable widget cards
    case focus
    case clock
    case batteryWifi
    case habits
    case hydration
    case food
    case notesPreview
    /// The note tabs.
    case notes
    case newNote
    case settings
    case status
    case widget(WidgetTile)
    case productivity(ProductivityItem)
}

/// Where a movable item lives (Custom layout, 7A-P1).
enum EdgePlacement: String, CaseIterable, Sendable {
    case left
    case right
    case hidden

    var side: EdgeSide? {
        switch self {
        case .left: return .left
        case .right: return .right
        case .hidden: return nil
        }
    }
}

/// Every item a bar can host. Case order = top-to-bottom render order on a bar. Raw values are stored in
/// `com.katikati.edge.custom`; never rename them.
enum EdgeItem: String, CaseIterable, Sendable {
    case apps
    case focus, clock, batteryWifi, habits, hydration, food, notesPreview
    case notes, newNote
    case reminders, alarms, time, tasks, clipboard, capture, screenshot, windows, screenTime
    case weather, nowPlaying, bluetooth, systemMonitor
    case status
    case settings

    var content: EdgeBarContent {
        switch self {
        case .apps: return .apps
        case .focus: return .focus
        case .clock: return .clock
        case .batteryWifi: return .batteryWifi
        case .habits: return .habits
        case .hydration: return .hydration
        case .food: return .food
        case .notesPreview: return .notesPreview
        case .notes: return .notes
        case .newNote: return .newNote
        case .settings: return .settings
        case .status: return .status
        case .weather: return .widget(.weather)
        case .nowPlaying: return .widget(.nowPlaying)
        case .bluetooth: return .widget(.bluetooth)
        case .systemMonitor: return .widget(.systemMonitor)
        case .reminders: return .productivity(.reminders)
        case .alarms: return .productivity(.alarms)
        case .time: return .productivity(.time)
        case .tasks: return .productivity(.tasks)
        case .clipboard: return .productivity(.clipboard)
        case .capture: return .productivity(.capture)
        case .screenshot: return .productivity(.screenshot)
        case .windows: return .productivity(.windows)
        case .screenTime: return .productivity(.screenTime)
        }
    }

    var productivity: ProductivityItem? {
        if case let .productivity(item) = content { return item }
        return nil
    }

    var widget: WidgetTile? {
        if case let .widget(tile) = content { return tile }
        return nil
    }

    /// Whether the item can be shown (productivity items need a built flyout).
    func isBuilt(_ built: Set<ProductivityItem> = ProductivityItem.built) -> Bool {
        productivity.map(built.contains) ?? true
    }

    /// Stored form: `notes:right,weather:left,clipboard:hidden`. Unknown ids / placements dropped, last entry wins.
    static func parsePlacements(_ stored: String?) -> [EdgeItem: EdgePlacement] {
        var result: [EdgeItem: EdgePlacement] = [:]
        for part in (stored ?? "").split(separator: ",") {
            let pair = part.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2, let item = EdgeItem(rawValue: pair[0]), let place = EdgePlacement(rawValue: pair[1]) else { continue }
            result[item] = place
        }
        return result
    }

    static func serialize(_ placements: [EdgeItem: EdgePlacement]) -> String {
        allCases.compactMap { item in placements[item].map { "\(item.rawValue):\($0.rawValue)" } }.joined(separator: ",")
    }
}

/// Resolves a preset (or the custom layout) into per-edge content.
enum EdgeBarComposition {
    /// Where every item sits for the preset. All edge bars now consolidate exclusively on the right edge,
    /// leaving the left edge free for the window drawer/sidebar. Any legacy `.left` custom placement maps to `.right`.
    static func placements(
        preset: EdgeBarPreset,
        primary: EdgeSide,
        widgets: [WidgetTile],
        productivity: [ProductivityItem],
        custom: [EdgeItem: EdgePlacement]
    ) -> [EdgeItem: EdgePlacement] {
        let main: EdgePlacement = .right
        var result: [EdgeItem: EdgePlacement] = [:]
        func put(_ items: [EdgeItem], _ place: EdgePlacement) { items.forEach { result[$0] = place } }
        let notesGroup: [EdgeItem] = [.notes, .newNote, .settings]
        let widgetItems = EdgeItem.allCases.filter { $0.widget.map(widgets.contains) ?? false }
        let productivityItems = EdgeItem.allCases.filter { $0.productivity.map(productivity.contains) ?? false }
        switch preset {
        case .off: break
        case .sydedock:
            put([.focus, .clock, .batteryWifi, .habits, .hydration, .food, .notesPreview, .apps, .settings], main)
        case .extraDock:
            put([.apps] + widgetItems + [.status, .settings], main)
        case .notes: put(notesGroup + widgetItems, main)
        case .status: put([.status] + widgetItems, main)
        case .notesAndStatus: put(notesGroup + [.status] + widgetItems, main)
        case .productivityAndRest:
            put(notesGroup + productivityItems + [.status] + widgetItems, main)
        case .custom:
            let fallback = placements(preset: .productivityAndRest, primary: .right, widgets: WidgetTile.allCases,
                                      productivity: ProductivityItem.allCases, custom: [:])
            let normalized = custom.mapValues { $0 == .left ? EdgePlacement.right : $0 }
            return fallback.merging(normalized) { _, mine in mine }
        }
        return result
    }

    static func resolve(
        preset: EdgeBarPreset,
        primary: EdgeSide,
        widgets: [WidgetTile],
        productivity: [ProductivityItem],
        custom: [EdgeItem: EdgePlacement],
        built: Set<ProductivityItem> = ProductivityItem.built
    ) -> [EdgeSide: [EdgeBarContent]] {
        let map = placements(preset: preset, primary: primary, widgets: widgets, productivity: productivity, custom: custom)
        var result: [EdgeSide: [EdgeBarContent]] = [:]
        for item in EdgeItem.allCases where item.isBuilt(built) {
            guard let place = map[item], place != .hidden else { continue }
            result[.right, default: []].append(item.content)
        }
        return result
    }
}

/// User-facing edge-bar layouts (Phase 7A-2, 7A-P1). The default is `productivityAndRest`.
enum EdgeBarPreset: String, CaseIterable, Sendable {
    case off
    case sydedock
    case extraDock
    case notes
    case notesAndStatus
    case status
    case productivityAndRest
    case custom

    static let `default`: EdgeBarPreset = .productivityAndRest
}
