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
    case windows

    /// Items whose flyout exists. An item appears on a bar only once built (no placeholders); P2–P6 add to this.
    static let built: Set<ProductivityItem> = []

    static func parse(_ stored: String?) -> [ProductivityItem] { parseIDList(stored) }
    static func serialize(_ items: [ProductivityItem]) -> String { items.map(\.rawValue).joined(separator: ",") }
}

/// What an edge bar hosts, in render order.
enum EdgeBarContent: Equatable, Sendable {
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
    case notes, newNote
    case reminders, alarms, time, tasks, clipboard, capture, windows
    case weather, nowPlaying, bluetooth
    case status
    case settings

    var content: EdgeBarContent {
        switch self {
        case .notes: return .notes
        case .newNote: return .newNote
        case .settings: return .settings
        case .status: return .status
        case .weather: return .widget(.weather)
        case .nowPlaying: return .widget(.nowPlaying)
        case .bluetooth: return .widget(.bluetooth)
        case .reminders: return .productivity(.reminders)
        case .alarms: return .productivity(.alarms)
        case .time: return .productivity(.time)
        case .tasks: return .productivity(.tasks)
        case .clipboard: return .productivity(.clipboard)
        case .capture: return .productivity(.capture)
        case .windows: return .productivity(.windows)
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
    /// Where every item sits for the preset. `primary` hosts notes / productivity; the rest goes opposite. Custom
    /// entries win, and an item missing from the stored layout falls back to the Productivity + Rest placement.
    static func placements(
        preset: EdgeBarPreset,
        primary: EdgeSide,
        widgets: [WidgetTile],
        productivity: [ProductivityItem],
        custom: [EdgeItem: EdgePlacement]
    ) -> [EdgeItem: EdgePlacement] {
        let main = EdgePlacement(rawValue: primary.rawValue) ?? .right
        let other: EdgePlacement = main == .left ? .right : .left
        var result: [EdgeItem: EdgePlacement] = [:]
        func put(_ items: [EdgeItem], _ place: EdgePlacement) { items.forEach { result[$0] = place } }
        let notesGroup: [EdgeItem] = [.notes, .newNote, .settings]
        let widgetItems = EdgeItem.allCases.filter { $0.widget.map(widgets.contains) ?? false }
        let productivityItems = EdgeItem.allCases.filter { $0.productivity.map(productivity.contains) ?? false }
        switch preset {
        case .off: break
        case .notes: put(notesGroup, main); put(widgetItems, other)
        case .status: put([.status], main); put(widgetItems, other)
        case .notesAndStatus: put(notesGroup + [.status], main); put(widgetItems, other)
        case .productivityAndRest:
            put(notesGroup + productivityItems, main); put([.status] + widgetItems, other)
        case .custom:
            let fallback = placements(preset: .productivityAndRest, primary: primary, widgets: WidgetTile.allCases,
                                      productivity: ProductivityItem.allCases, custom: [:])
            return fallback.merging(custom) { _, mine in mine }
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
            guard let side = map[item]?.side else { continue }
            result[side, default: []].append(item.content)
        }
        return result
    }
}

/// User-facing edge-bar layouts (Phase 7A-2, 7A-P1). The default is `productivityAndRest`.
enum EdgeBarPreset: String, CaseIterable, Sendable {
    case off
    case notes
    case notesAndStatus
    case status
    case productivityAndRest
    case custom

    static let `default`: EdgeBarPreset = .productivityAndRest
}

/// Pure sizing for what an edge bar hosts (Phase 7A-5). One tile per content kind.
enum EdgeBarLayout {
    static let width: CGFloat = 56
    /// Notes glyph tile (placeholder until 7A-7).
    static let notesTileHeight: CGFloat = 56
    /// Status trio: three stacked glyph buttons.
    static let statusRowHeight: CGFloat = 40
    static let statusTileHeight: CGFloat = statusRowHeight * 3 + 16
    /// One widget tile (glyph button).
    static let widgetTileHeight: CGFloat = 48
    static let tileSpacing: CGFloat = 8
    static let verticalPadding: CGFloat = 10

    static func tileHeight(_ content: EdgeBarContent) -> CGFloat {
        switch content {
        case .notes: return notesTileHeight
        case .status: return statusTileHeight
        case .widget, .newNote, .settings, .productivity: return widgetTileHeight
        }
    }

    /// Total bar height for the given content, in order. Empty content = 0 (no bar).
    static func contentHeight(_ content: [EdgeBarContent]) -> CGFloat {
        guard !content.isEmpty else { return 0 }
        let tiles = content.map(tileHeight).reduce(0, +)
        return tiles + CGFloat(content.count - 1) * tileSpacing + 2 * verticalPadding
    }

    /// Screen-space rect of one tile (bar frame is bottom-left origin; content flows top → bottom).
    static func tileFrame(at index: Int, of content: [EdgeBarContent], in barFrame: CGRect) -> CGRect {
        guard content.indices.contains(index) else { return .zero }
        var top = barFrame.maxY - verticalPadding
        for i in 0..<index { top -= tileHeight(content[i]) + tileSpacing }
        let h = tileHeight(content[index])
        return CGRect(x: barFrame.minX, y: top - h, width: barFrame.width, height: h)
    }
}
