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

/// A widget tile on the left-edge widgets bar (Phase 7A-8). Each tile opens its own flyout.
/// Raw values are stored in `com.katikati.widgets.tiles`; never rename them.
enum WidgetTile: String, CaseIterable, Sendable {
    case weather
    case nowPlaying

    /// Parses the stored comma-separated list: unknown ids dropped, duplicates collapsed, order kept.
    static func parse(_ stored: String?) -> [WidgetTile] {
        var seen = Set<WidgetTile>()
        return (stored ?? "").split(separator: ",").compactMap { part in
            guard let tile = WidgetTile(rawValue: part.trimmingCharacters(in: .whitespaces)), seen.insert(tile).inserted else { return nil }
            return tile
        }
    }

    static func serialize(_ tiles: [WidgetTile]) -> String { tiles.map(\.rawValue).joined(separator: ",") }
}

/// What an edge bar hosts. Notes always live on the right edge; status follows the user's side;
/// widgets always live on the left edge.
enum EdgeBarContent: Equatable, Sendable {
    case notes
    case status
    case widget(WidgetTile)
}

/// Combines the preset (notes/status) with the enabled widget tiles into per-edge content.
enum EdgeBarComposition {
    static let widgetsSide: EdgeSide = .left

    /// Widgets lead the left bar (above a left-side status trio); notes/status come from the preset.
    static func resolve(preset: EdgeBarPreset, statusSide: EdgeSide, widgets: [WidgetTile]) -> [EdgeSide: [EdgeBarContent]] {
        var result = preset.content(statusSide: statusSide)
        guard !widgets.isEmpty else { return result }
        result[widgetsSide] = widgets.map(EdgeBarContent.widget) + (result[widgetsSide] ?? [])
        return result
    }
}

/// User-facing edge-bar presets (Phase 7A-2). Pure: resolves to content per edge.
enum EdgeBarPreset: String, CaseIterable, Sendable {
    case off
    case notes
    case notesAndStatus
    case status

    static let notesSide: EdgeSide = .right

    /// Content hosted on each active edge for this preset and status side.
    func content(statusSide: EdgeSide) -> [EdgeSide: [EdgeBarContent]] {
        switch self {
        case .off: return [:]
        case .notes: return [Self.notesSide: [.notes]]
        case .status: return [statusSide: [.status]]
        case .notesAndStatus:
            if statusSide == Self.notesSide { return [Self.notesSide: [.notes, .status]] }
            return [Self.notesSide: [.notes], statusSide: [.status]]
        }
    }

    func activeSides(statusSide: EdgeSide) -> Set<EdgeSide> {
        Set(content(statusSide: statusSide).keys)
    }
}

/// Pure side-edge auto-hide rules (Phase 7A-3). The controller feeds mouse facts in and acts on
/// the returned action; timers and panels stay outside Core.
enum EdgeBarAutoHide {
    /// Width of the invisible strip along the screen side that reveals a hidden bar.
    static let hotZoneWidth: CGFloat = 2
    /// Seconds the pointer must stay away before a shown bar hides.
    static let idleDelay: TimeInterval = 0.4

    enum Action: Equatable {
        case none
        case reveal
        case armIdleHide
        case cancelIdleHide
    }

    /// Reveal strip: `hotZoneWidth` wide at the screen side, spanning the bar's vertical extent.
    static func hotZone(side: EdgeSide, screenFrame: CGRect, barFrame: CGRect) -> CGRect {
        let x = side == .left ? screenFrame.minX : screenFrame.maxX - hotZoneWidth
        return CGRect(x: x, y: barFrame.minY, width: hotZoneWidth, height: barFrame.height)
    }

    static func action(isHidden: Bool, mouseInHotZone: Bool, mouseInBar: Bool, popupOpen: Bool = false) -> Action {
        if isHidden { return mouseInHotZone ? .reveal : .none }
        return (mouseInBar || mouseInHotZone || popupOpen) ? .cancelIdleHide : .armIdleHide
    }
}

/// Pure sizing for what an edge bar hosts (Phase 7A-5). One tile per content kind.
enum EdgeBarLayout {
    static let width: CGFloat = 56
    /// Notes flyout (list + editor).
    static let notesPopupSize = CGSize(width: 440, height: 340)
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
        case .widget: return widgetTileHeight
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
