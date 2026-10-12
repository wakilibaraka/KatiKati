import Foundation

/// Size of one Pinboard card on a two-column grid (Phase 7B-V1): small = 1x1, wide = 2x1, large = 2x2.
enum PinboardSize: Equatable, Sendable { case small, wide, large }

/// The catalog of Pinboard widgets. Adding a widget = one case here + one view in `PinboardWidgetViews`.
enum PinboardWidget: String, CaseIterable, Sendable {
    case clock, calendar, weather, nowPlaying, calculator, countdown, screenTime, quickSettings
    case system, network, battery, topApps, batteries

    var size: PinboardSize {
        switch self {
        case .calendar, .weather, .nowPlaying, .countdown, .network, .battery, .topApps: return .small
        case .clock, .calculator, .screenTime, .system, .batteries: return .wide
        case .quickSettings: return .large
        }
    }

    static let defaultOrder: [PinboardWidget] = [.clock, .weather, .calendar, .quickSettings, .system, .network, .battery, .topApps, .batteries, .nowPlaying, .countdown, .calculator, .screenTime]

    /// Comma separated raw values. Unknown ids are dropped, duplicates collapse; nil / empty-after-parse of a
    /// never-written key gives the default, an explicit empty string means "none".
    static func parse(_ raw: String?) -> [PinboardWidget] {
        guard let raw else { return defaultOrder }
        var seen = Set<PinboardWidget>()
        return raw.split(separator: ",").compactMap { PinboardWidget(rawValue: String($0)) }.filter { seen.insert($0).inserted }
    }

    static func serialize(_ widgets: [PinboardWidget]) -> String { widgets.map(\.rawValue).joined(separator: ",") }
}

/// Packs widgets into rows of a two-column grid: two smalls share a row, a wide or large takes a row alone,
/// a lone small stays left. Order is preserved except that a small waits for the next small to pair with.
enum PinboardLayout {
    static func rows(_ widgets: [PinboardWidget]) -> [[PinboardWidget]] {
        var rows: [[PinboardWidget]] = []
        var pendingSmall: PinboardWidget?
        for w in widgets {
            if w.size == .small {
                if let p = pendingSmall { rows.append([p, w]); pendingSmall = nil } else { pendingSmall = w }
            } else {
                rows.append([w])
            }
        }
        if let p = pendingSmall { rows.append([p]) }
        return rows
    }
}

/// One-tap system switches (Phase 7B-V2). State and actions live in the Platform engine; this is the catalog.
enum QuickToggleID: String, CaseIterable, Sendable {
    case darkMode, keepAwake, hideDesktopIcons, showHiddenFiles, dockAutoHide, pathBar
    case muteMic, emptyTrash, ejectDisks, wifi, bluetooth, nightShift

    /// Actions have no on/off state: they run and report done.
    var isAction: Bool { self == .emptyTrash || self == .ejectDisks }
    /// Needs a confirmation click before it runs.
    var needsConfirm: Bool { self == .emptyTrash }

    var symbolName: String {
        switch self {
        case .darkMode: return "moon.fill"
        case .keepAwake: return "cup.and.saucer.fill"
        case .hideDesktopIcons: return "eye.slash.fill"
        case .showHiddenFiles: return "folder.fill"
        case .dockAutoHide: return "dock.rectangle"
        case .pathBar: return "chevron.right.square.fill"
        case .muteMic: return "mic.slash.fill"
        case .emptyTrash: return "trash.fill"
        case .ejectDisks: return "eject.fill"
        case .wifi: return "wifi"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        case .nightShift: return "sun.max.fill"
        }
    }

    static let defaultOrder: [QuickToggleID] = allCases

    static func parse(_ raw: String?) -> [QuickToggleID] {
        guard let raw else { return defaultOrder }
        var seen = Set<QuickToggleID>()
        return raw.split(separator: ",").compactMap { QuickToggleID(rawValue: String($0)) }.filter { seen.insert($0).inserted }
    }

    static func serialize(_ ids: [QuickToggleID]) -> String { ids.map(\.rawValue).joined(separator: ",") }
}

/// Presentation of the Pinboard (Phase 7B): full-screen backdrop (default, like the launcher)
/// or the floating draggable panel (Phase 7B-V1).
/// Raw values are stored in `com.katikati.pinboard.style`; never rename them.
enum PinboardStyle: String, CaseIterable, Sendable {
    case fullScreen
    case floating

    static let `default`: PinboardStyle = .fullScreen

    static func parse(_ stored: String?) -> PinboardStyle {
        stored.flatMap(PinboardStyle.init(rawValue:)) ?? .default
    }
}

/// Full-screen Pinboard geometry (Phase 7B): the widget wall from the reference — the two-column
/// grid from `PinboardLayout` centered on the screen over the launcher backdrop. Cards keep their
/// coloured gradients; only the frame changes. Pure numbers so it is unit-testable.
extension PinboardWidget: Equatable {
    static func == (lhs: PinboardWidget, rhs: PinboardWidget) -> Bool {
        lhs.rawValue == rhs.rawValue
    }
}

    /// Where the Pinboard panel sits: remembered between summons, clamped back on-screen.
enum PinboardPlacement {
    /// Clamps an origin so a panel of `size` stays fully inside `visible`.
    static func clamp(origin: (x: Double, y: Double), size: (w: Double, h: Double),
                      visible: (x: Double, y: Double, w: Double, h: Double)) -> (x: Double, y: Double) {
        let x = min(max(origin.x, visible.x), visible.x + max(0, visible.w - size.w))
        let y = min(max(origin.y, visible.y), visible.y + max(0, visible.h - size.h))
        return (x, y)
    }
}

/// The full-screen Pinboard wall (Phase 7B): every card placed on a dense grid of equal cells — a small is 1x1, a wide
/// 2x1 and the large Quick Settings card 2x2 — then the whole grid is scaled so it fills the screen. Cards are placed in
/// reading order into the first free spot (like CSS `grid-auto-flow: dense`), so the wall has no holes beside the tall
/// card and the card sizes never change relative to each other.
enum PinboardGrid {
    struct Cell: Equatable {
        let widget: PinboardWidget
        let col: Int
        let row: Int
        let cols: Int
        let rows: Int
    }

    struct Fit: Equatable {
        let columns: Int
        let rows: Int
        let scale: Double
    }

    static func span(_ size: PinboardSize) -> (cols: Int, rows: Int) {
        switch size {
        case .small: return (1, 1)
        case .wide: return (2, 1)
        case .large: return (2, 2)
        }
    }

    /// Places `widgets` in `columns` columns (at least 2, so a wide card always fits). Returns the cells and the row count.
    static func pack(_ widgets: [PinboardWidget], columns requested: Int) -> (cells: [Cell], rows: Int) {
        let columns = max(2, requested)
        var occupied: [[Bool]] = []
        func isFree(_ r: Int, _ c: Int, _ w: Int, _ h: Int) -> Bool {
            for rr in r..<(r + h) where rr < occupied.count {
                for cc in c..<(c + w) where occupied[rr][cc] { return false }
            }
            return true
        }
        var cells: [Cell] = []
        for widget in widgets {
            let sp = span(widget.size)
            var placed = false
            var r = 0
            while !placed {
                for c in 0...(columns - sp.cols) where isFree(r, c, sp.cols, sp.rows) {
                    while occupied.count < r + sp.rows { occupied.append(Array(repeating: false, count: columns)) }
                    for rr in r..<(r + sp.rows) { for cc in c..<(c + sp.cols) { occupied[rr][cc] = true } }
                    cells.append(Cell(widget: widget, col: c, row: r, cols: sp.cols, rows: sp.rows))
                    placed = true
                    break
                }
                r += 1
            }
        }
        return (cells, occupied.count)
    }

    /// The column count whose grid, scaled to fit `width` x `height`, comes out largest (cards as big as the screen
    /// allows without scrolling). `unit` and `gap` are the cards' design size; the scale is capped so a short list
    /// of cards is not blown up absurdly.
    static func fit(_ widgets: [PinboardWidget], width: Double, height: Double,
                    unit: Double = 154, gap: Double = 12, maxScale: Double = 2.2, maxColumns: Int = 16) -> Fit {
        guard !widgets.isEmpty, width > 0, height > 0 else { return Fit(columns: 2, rows: 0, scale: 1) }
        var best = Fit(columns: 2, rows: 0, scale: 0)
        for columns in 2...max(2, maxColumns) {
            let rows = pack(widgets, columns: columns).rows
            let w = Double(columns) * unit + Double(columns - 1) * gap
            let h = Double(rows) * unit + Double(max(0, rows - 1)) * gap
            let scale = min(width / w, height / h, maxScale)
            if scale > best.scale + 1e-9 { best = Fit(columns: columns, rows: rows, scale: scale) }
        }
        return best
    }
}
