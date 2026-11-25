import CoreGraphics
import Foundation

/// Phase 16v: Control Center size presets. Width per preset; height is always content-sized
/// (the panel never scrolls). Raw values are stored in `com.katikati.controlcenter.size`.
enum ControlCenterSize: String, CaseIterable, Sendable {
    case small, medium, large

    static let `default`: ControlCenterSize = .medium
    static let storageKey = "com.katikati.controlcenter.size"

    /// Panel width per preset. Medium (360) is the pre-preset width, frozen.
    var width: CGFloat {
        switch self {
        case .small: return 300
        case .medium: return 360
        case .large: return 440
        }
    }

    static func parse(_ raw: String?) -> ControlCenterSize {
        raw.flatMap(ControlCenterSize.init(rawValue:)) ?? .default
    }
}

/// Vertical anchor of the Control Center panel on its edge. Top (default) is the pre-anchor
/// behavior: top-aligned under the menu bar. Bottom sits above the dock clearance.
enum ControlCenterAnchor: String, CaseIterable, Sendable {
    case top, center, bottom

    static let `default`: ControlCenterAnchor = .top
    static let storageKey = "com.katikati.controlcenter.anchor"

    static func parse(_ raw: String?) -> ControlCenterAnchor {
        raw.flatMap(ControlCenterAnchor.init(rawValue:)) ?? .default
    }
}

/// Visual preset of the Control Center: the original dock-themed panel, or the iPadOS-style glass bento.
enum ControlCenterStyle: String, CaseIterable, Sendable {
    case classic, ipad

    static let `default`: ControlCenterStyle = .classic
    static let storageKey = "com.katikati.controlcenter.style"

    static func parse(_ raw: String?) -> ControlCenterStyle {
        raw.flatMap(ControlCenterStyle.init(rawValue:)) ?? .default
    }
}

/// 57a: wheel travel on the Control Center volume row. Six points of trackpad travel (or half a mouse-wheel
/// click) is 1.25 % volume, and at most one step per 60 ms so a momentum burst cannot jump the level.
enum ControlCenterScroll {
    static let travelPerStep: CGFloat = 6
    static let volumePerStep: Double = 0.0125
    static let stepInterval: TimeInterval = 0.06
    /// A notched wheel has lines, not points; one click counts as two steps' worth of travel.
    static let notchSteps = 2

    /// What a gesture carries between events. Leftovers under one step are kept, so slow scrolling adds up.
    struct State: Equatable {
        var travel: CGFloat = 0
        var lastStepAt: Date = .distantPast
    }

    /// Scrolling away from the user (positive `deltaY`) raises the volume. Returns the new level when a step
    /// is due, nil while travel is still adding up or the rate limit holds it back.
    static func consume(deltaY: CGFloat, precise: Bool, level: Double, state: inout State,
                        now: Date = Date()) -> Double? {
        guard deltaY != 0 else { return nil }
        state.travel += precise ? deltaY : (deltaY < 0 ? -1 : 1) * CGFloat(notchSteps) * travelPerStep
        let steps = (state.travel / travelPerStep).rounded(.towardZero)
        guard steps != 0, now.timeIntervalSince(state.lastStepAt) >= stepInterval else { return nil }
        state.travel -= steps * travelPerStep
        state.lastStepAt = now
        return min(1, max(0, level + Double(steps) * volumePerStep))
    }
}

/// The Control Center's switch grid: four toggles per row normally, five when four would run past the
/// screen and five saves a row. Pure so the choice is unit-tested instead of being eyeballed.
enum ControlCenterGrid {
    static let baseColumns = 4
    static let wideColumns = 5

    /// Rows the grid needs for `count` cells at `columns` per row. 0 for an empty grid.
    static func rows(count: Int, columns: Int) -> Int {
        guard count > 0, columns > 0 else { return 0 }
        return (count + columns - 1) / columns
    }

    /// Cells per row for a grid that has room for `rowsFit` rows. Four while the panel's height can
    /// hold that many; five when it cannot, so the grid narrows its rows instead of running off the
    /// panel. `rowsFit` is measured from the grid's own height, not from the screen.
    static func columns(count: Int, rowsFit: Int) -> Int {
        guard count > 0, rowsFit > 0 else { return baseColumns }
        return count <= rowsFit * baseColumns ? baseColumns : wideColumns
    }
}

// MARK: - CC-2: presets, tile identity, span packer

/// Layout presets. `classic` is today's panel; `custom` is what an edit produces, and it remembers
/// the preset it started from so Reset can go back instead of guessing.
enum ControlCenterPreset: String, CaseIterable, Sendable {
    case classic, modular, bento, custom

    static let `default`: ControlCenterPreset = .classic
    static let storageKey = "com.katikati.controlcenter.preset"

    static func parse(_ raw: String?) -> ControlCenterPreset {
        raw.flatMap(ControlCenterPreset.init(rawValue:)) ?? .default
    }
}

/// A named block of the panel. Sections are what presets arrange; toggles are what the user adds.
enum ControlCenterSection: String, CaseIterable, Sendable {
    case header, peripherals, connectivity, nowPlaying, network, sliders, utilities, account
}

/// Four sizes, four columns at medium width. `hero` always takes the full row; `wide` takes two.
enum ControlCenterTileSize: String, CaseIterable, Sendable {
    case icon, standard, wide, hero

    static let `default`: ControlCenterTileSize = .standard

    /// Columns the tile wants. Clamped by the packer to the row width it actually has.
    var span: Int {
        switch self {
        case .icon, .standard: return 1
        case .wide: return 2
        case .hero: return 4
        }
    }
}

/// Tile identity is wider than a toggle: sections and toggles share one catalogue order.
enum ControlCenterTileID: Hashable, Sendable {
    case section(ControlCenterSection)
    case toggle(QuickToggleID)

    var token: String {
        switch self {
        case .section(let section): return "section.\(section.rawValue)"
        case .toggle(let toggle): return "toggle.\(toggle.rawValue)"
        }
    }

    init?(token: String) {
        if token.hasPrefix("section."),
           let section = ControlCenterSection(rawValue: String(token.dropFirst(8))) {
            self = .section(section)
        } else if token.hasPrefix("toggle."),
                  let toggle = QuickToggleID(rawValue: String(token.dropFirst(7))) {
            self = .toggle(toggle)
        } else {
            return nil
        }
    }
}

struct ControlCenterTileSpec: Equatable, Sendable {
    var id: ControlCenterTileID
    var size: ControlCenterTileSize = .standard
}

struct ControlCenterLayoutSpec: Equatable, Sendable {
    var preset: ControlCenterPreset
    var basedOn: ControlCenterPreset
    var tiles: [ControlCenterTileSpec]
}

extension ControlCenterLayoutSpec {
    /// `classic` is today's panel order, so an existing profile that never opens Settings sees no
    /// change. `custom` falls back to `classic` until an edit writes a spec.
    static func preset(_ preset: ControlCenterPreset) -> ControlCenterLayoutSpec {
        switch preset {
        case .classic, .custom:
            return .init(preset: .classic, basedOn: .classic, tiles: classicTiles)
        case .modular:
            return .init(preset: .modular, basedOn: .modular, tiles: [
                .init(id: .section(.header), size: .hero),
                .init(id: .section(.connectivity), size: .hero),
                .init(id: .section(.network)),
                .init(id: .section(.nowPlaying), size: .wide),
                .init(id: .section(.sliders), size: .wide),
                .init(id: .section(.utilities)),
                .init(id: .section(.account)),
                .init(id: .section(.peripherals)),
            ])
        case .bento:
            return .init(preset: .bento, basedOn: .bento, tiles: [
                .init(id: .section(.header), size: .hero),
                .init(id: .section(.connectivity), size: .wide),
                .init(id: .section(.peripherals), size: .wide),
                .init(id: .section(.sliders), size: .hero),
                .init(id: .section(.network), size: .wide),
                .init(id: .section(.utilities)),
                .init(id: .section(.account)),
                .init(id: .section(.nowPlaying), size: .hero),
            ])
        }
    }

    /// Classic is the pre-preset panel: every section stacked, full width, in today's order.
    static let classicTiles: [ControlCenterTileSpec] = [
        .init(id: .section(.header), size: .hero),
        .init(id: .section(.peripherals), size: .hero),
        .init(id: .section(.connectivity), size: .hero),
        .init(id: .section(.nowPlaying), size: .hero),
        .init(id: .section(.network), size: .hero),
        .init(id: .section(.sliders), size: .hero),
        .init(id: .section(.utilities), size: .hero),
        .init(id: .section(.account), size: .hero),
    ]
}

/// A finish layered on the dock theme's own colours — not a second theme system.
enum ControlCenterGlassStyle: String, CaseIterable, Sendable {
    case clear, semi, tinted

    static let `default`: ControlCenterGlassStyle = .semi
    static let storageKey = "com.katikati.controlcenter.glass"

    var cardAlpha: Double {
        switch self {
        case .clear: return 0.05
        case .semi: return 0.10
        case .tinted: return 0.16
        }
    }

    static func parse(_ raw: String?) -> ControlCenterGlassStyle {
        raw.flatMap(ControlCenterGlassStyle.init(rawValue:)) ?? .default
    }
}

/// Where the Control Centre lives. `edge` is the standalone deck; `menuBar` hands the panel to the
/// menu-bar item and frees the edge deck for a different job.
enum ControlCenterSurfaceMode: String, CaseIterable, Sendable {
    case edge, menuBar

    static let `default`: ControlCenterSurfaceMode = .edge
    static let storageKey = "com.katikati.controlcenter.surface"

    static func parse(_ raw: String?) -> ControlCenterSurfaceMode {
        raw.flatMap(ControlCenterSurfaceMode.init(rawValue:)) ?? .default
    }
}

/// What the edge deck does once Control Centre moves to the menu bar. Choosing the menu-bar home is
/// the only thing that switches this, so nobody's deck changes job without asking.
extension Notification.Name {
    /// Posted when the Control Centre home changes. The Settings pane can only write the key, so
    /// the app layer listens and closes the surface it just left (Hub or standalone panel).
    static let controlCenterSurfaceDidChange = Notification.Name("com.katikati.controlcenter.surfaceDidChange")
}

enum ControlCenterEdgeRole: String, CaseIterable, Sendable {
    case controlCenter, backgroundActivity

    /// The role a surface mode implies, plus whether the owner still needs to be told about it.
    static func implied(by mode: ControlCenterSurfaceMode, hasBeenTold: Bool) -> (role: ControlCenterEdgeRole, needsPrompt: Bool) {
        guard mode == .menuBar else { return (.controlCenter, false) }
        return (.backgroundActivity, !hasBeenTold)
    }

    static let promptSeenKey = "com.katikati.controlcenter.menuBarRolePromptSeen"
}

/// Music surfaces that can own the now-playing card. The notch wins over the dock widget when both
/// are on, but either one is enough to suppress the panel's own card.
enum ControlCenterMusicSurface: String, CaseIterable, Sendable {
    case notch, dock
}

struct ControlCenterDedupeOptions: Equatable, Sendable {
    var singleBattery = true
    var singleNowPlaying = true
    var showNowPlayingAnyway = false

    static let singleBatteryKey = "com.katikati.controlcenter.singleBattery"
    static let singleNowPlayingKey = "com.katikati.controlcenter.singleNowPlaying"
    static let showNowPlayingAnywayKey = "com.katikati.controlcenter.showNowPlayingAnyway"

    /// Missing keys keep the approved defaults (both on), so existing profiles gain the dedupe
    /// without a migration.
    static func stored(_ defaults: UserDefaults = .standard) -> ControlCenterDedupeOptions {
        var options = ControlCenterDedupeOptions()
        if let value = defaults.object(forKey: singleBatteryKey) as? Bool { options.singleBattery = value }
        if let value = defaults.object(forKey: singleNowPlayingKey) as? Bool { options.singleNowPlaying = value }
        options.showNowPlayingAnyway = defaults.bool(forKey: showNowPlayingAnywayKey)
        return options
    }
}

/// Dedupe is opt-out, never magic: it only hides the row the header already answers, and the
/// settings override always wins.
enum ControlCenterDedupe {
    static func hidesSystemRow(hasBatteryPill: Bool, options: ControlCenterDedupeOptions) -> Bool {
        options.singleBattery && hasBatteryPill
    }

    static func hidesNowPlaying(surfacesOn: Set<ControlCenterMusicSurface>,
                                options: ControlCenterDedupeOptions) -> Bool {
        guard options.singleNowPlaying, !options.showNowPlayingAnyway else { return false }
        return !surfacesOn.isEmpty
    }
}

/// Versioned, tolerant storage for a custom layout. A malformed or unknown value falls back to the
/// preset the profile already had, so a half-written preferences file can never empty the panel.
enum ControlCenterLayoutCodec {
    static let storageKey = "com.katikati.controlcenter.layout.v1"
    private static let prefix = "v1"

    static func encode(_ spec: ControlCenterLayoutSpec) -> String {
        let tiles = spec.tiles.map { "\($0.id.token):\($0.size.rawValue)" }.joined(separator: ",")
        return "\(prefix)|\(spec.preset.rawValue)|\(spec.basedOn.rawValue)|\(tiles)"
    }

    static func decode(_ raw: String?) -> ControlCenterLayoutSpec? {
        guard let raw else { return nil }
        let parts = raw.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, parts[0] == prefix else { return nil }
        let preset = ControlCenterPreset(rawValue: parts[1]) ?? .custom
        let basedOn = ControlCenterPreset(rawValue: parts[2]) ?? .classic
        var seen = Set<ControlCenterTileID>()
        let tiles: [ControlCenterTileSpec] = parts[3].split(separator: ",").compactMap { entry in
            let bits = entry.split(separator: ":", maxSplits: 1).map(String.init)
            guard let id = ControlCenterTileID(token: bits.first ?? ""), seen.insert(id).inserted else { return nil }
            let size = bits.count > 1 ? (ControlCenterTileSize(rawValue: bits[1]) ?? .standard) : .standard
            return ControlCenterTileSpec(id: id, size: size)
        }
        guard !tiles.isEmpty else { return nil }
        return ControlCenterLayoutSpec(preset: preset, basedOn: basedOn, tiles: tiles)
    }
}

/// One packed row. `columnsUsed` lets the view hug the leading edge without measuring text.
struct ControlCenterPackedRow: Equatable, Sendable {
    let tiles: [ControlCenterTileSpec]
    let columnsUsed: Int
}

/// Resolves spans into rows. Pure, stable, and it never leaves a hole before a tile that would fit:
/// a tile that does not fit the remainder starts the next row instead of being clipped.
enum ControlCenterPacker {
    static let wideColumns = 4

    /// Below 400 pt the panel degrades to one column rather than shrinking text or clipping.
    static func columns(width: CGFloat) -> Int {
        width < 400 ? 1 : wideColumns
    }

    static func rows(_ tiles: [ControlCenterTileSpec], columns: Int) -> [ControlCenterPackedRow] {
        let limit = max(1, columns)
        var rows: [ControlCenterPackedRow] = []
        var current: [ControlCenterTileSpec] = []
        var used = 0
        for tile in tiles {
            let span = min(max(tile.size.span, 1), limit)
            if used + span > limit, !current.isEmpty {
                rows.append(ControlCenterPackedRow(tiles: current, columnsUsed: used))
                current = []
                used = 0
            }
            current.append(tile)
            used += span
            if used >= limit {
                rows.append(ControlCenterPackedRow(tiles: current, columnsUsed: used))
                current = []
                used = 0
            }
        }
        if !current.isEmpty {
            rows.append(ControlCenterPackedRow(tiles: current, columnsUsed: used))
        }
        return rows
    }
}

/// Control Center open animation. Instant (default) is the pre-animation behavior.
enum ControlCenterAnimation: String, CaseIterable, Sendable {
    case instant, fade, slide

    static let `default`: ControlCenterAnimation = .instant
    static let storageKey = "com.katikati.controlcenter.animation"

    static func parse(_ raw: String?) -> ControlCenterAnimation {
        raw.flatMap(ControlCenterAnimation.init(rawValue:)) ?? .default
    }
}

/// The Bluetooth rune as geometry, so the drawn tile mark and its scaling test share one source.
/// Strokes are unit-normalised: the stem, then the two crossed blades.
enum BluetoothRuneGeometry {
    static let strokes: [[CGPoint]] = [
        [CGPoint(x: 0.50, y: 0.10), CGPoint(x: 0.50, y: 0.90)],
        [CGPoint(x: 0.50, y: 0.10), CGPoint(x: 0.78, y: 0.30), CGPoint(x: 0.22, y: 0.70)],
        [CGPoint(x: 0.50, y: 0.90), CGPoint(x: 0.78, y: 0.70), CGPoint(x: 0.22, y: 0.30)],
    ]

    static func points(in side: CGFloat) -> [[CGPoint]] {
        strokes.map { stroke in stroke.map { CGPoint(x: $0.x * side, y: $0.y * side) } }
    }

    /// The rune's ink bounds inside a `side`-point square: never outside it, always proportional.
    static func bounds(in side: CGFloat) -> CGRect {
        let all = points(in: side).flatMap { $0 }
        let xs = all.map(\.x), ys = all.map(\.y)
        return CGRect(x: xs.min() ?? 0, y: ys.min() ?? 0,
                      width: (xs.max() ?? 0) - (xs.min() ?? 0),
                      height: (ys.max() ?? 0) - (ys.min() ?? 0))
    }

    /// Stroke weight stays visually constant relative to the square, with a 1.3 pt floor.
    static func lineWidth(for side: CGFloat) -> CGFloat { max(1.3, side * 0.11) }
}
