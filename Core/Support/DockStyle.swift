import CoreGraphics
import Foundation

/// Bar size in three friendly steps (Settings › Layout, Phase 11e). Exact heights stay
/// reachable in Fine-tune; these are the values a style card writes.
enum DockSizeClass: String, CaseIterable, Codable, Sendable {
    case small, medium, large

    var barHeight: CGFloat {
        switch self {
        case .small: return 46
        case .medium: return 54 // DockPanelHeight.native — the fresh-install bar
        case .large: return 68
        }
    }

    /// The step a height reads as (nearest), for the segmented control's selection.
    static func nearest(to height: CGFloat) -> DockSizeClass {
        allCases.min { abs($0.barHeight - height) < abs($1.barHeight - height) } ?? .medium
    }
}

/// Island gap + side margin in three friendly steps.
enum DockSpacing: String, CaseIterable, Codable, Sendable {
    case compact, comfortable, airy

    var gap: CGFloat {
        switch self {
        case .compact: return 4
        case .comfortable: return 10
        case .airy: return 18
        }
    }

    var margin: CGFloat {
        switch self {
        case .compact: return 6
        case .comfortable: return 12
        case .airy: return 24
        }
    }

    /// Exact match only: a hand-tuned gap/margin reads as no step (Custom).
    static func matching(gap: CGFloat, margin: CGFloat) -> DockSpacing? {
        allCases.first { abs($0.gap - gap) < 0.25 && abs($0.margin - margin) < 0.25 }
    }
}

/// A one-tap dock look (owner 2026-10-13: "presets with little edits"): layout mode + size +
/// spacing + bottom edge, and optionally a widget preset. Never touches the theme — theme stays
/// its own choice (owner decision 3, Phase 11/18 plan).
struct DockStyle: Equatable, Identifiable, Sendable {
    var id: String
    var mode: BarLayoutMode
    var size: DockSizeClass
    var spacing: DockSpacing
    var bottomGap: CGFloat
    /// `WidgetPresets` id applied with the style; `nil` keeps the user's widgets as they are.
    var widgetPresetID: String?
    /// Which edge the strip sits on (Phase 18h); the global placement a style writes.
    var placement: StripPlacement = .bottom

    /// Localized card title (literal keys so the localization gate sees them).
    var localizedTitle: String {
        switch id {
        case "style.islands": return String(localized: "Islands")
        case "style.classic": return String(localized: "Classic")
        case "style.wide": return String(localized: "Wide")
        case "style.minimal": return String(localized: "Minimal")
        case "style.sideRail": return String(localized: "Side Rail")
        default: return id
        }
    }

    static let islands = DockStyle(id: "style.islands", mode: .split3, size: .medium, spacing: .comfortable,
                                   bottomGap: PanelLayoutMetrics.floatingBottomGap, widgetPresetID: nil)
    static let classic = DockStyle(id: "style.classic", mode: .centered, size: .medium, spacing: .comfortable,
                                   bottomGap: PanelLayoutMetrics.floatingBottomGap, widgetPresetID: nil)
    static let wide = DockStyle(id: "style.wide", mode: .windows, size: .small, spacing: .compact,
                                bottomGap: PanelLayoutMetrics.huggingBottomGap, widgetPresetID: nil)
    // No built-in applies a widget preset: a style that hid widgets left them hidden after switching
    // to another style (live check 11g) — widgets, like the theme, stay the user's own choice.
    static let minimal = DockStyle(id: "style.minimal", mode: .centered, size: .small, spacing: .compact,
                                   bottomGap: PanelLayoutMetrics.floatingBottomGap, widgetPresetID: nil)

    /// Mode-aware rail on the left edge (owner decision 1): three stacked islands, compact tiles.
    static let sideRail = DockStyle(id: "style.sideRail", mode: .split3, size: .medium, spacing: .comfortable,
                                    bottomGap: PanelLayoutMetrics.floatingBottomGap, widgetPresetID: nil,
                                    placement: .left)

    /// Card order in Settings and the welcome guide. Islands first: it is the fresh-install look.
    static let builtIns: [DockStyle] = [.islands, .classic, .wide, .minimal, .sideRail]

    /// The built-in the live values equal, or `nil` (= Custom). Widget presets are not compared:
    /// re-arranging widgets after picking a style keeps the style selected.
    static func matching(mode: BarLayoutMode, barHeight: CGFloat, gap: CGFloat, margin: CGFloat,
                         bottomGap: CGFloat, placement: StripPlacement = .bottom) -> DockStyle? {
        builtIns.first { style in
            style.mode == mode
                && style.placement == placement
                && abs(style.size.barHeight - barHeight) < 0.5
                && abs(style.spacing.gap - gap) < 0.25
                && abs(style.spacing.margin - margin) < 0.25
                && abs(style.bottomGap - bottomGap) < 0.25
        }
    }
}

/// Makes a style fit the screen it is applied on (Phase 11e): when the solver would overflow the
/// apps row below `minimumAppTiles`, step the size down, then the spacing, until it fits or
/// nothing is left to give. Pure; the solver is the authority on what fits.
enum DockStyleFit {
    static let minimumAppTiles = 6

    static func resolve(_ style: DockStyle, screenWidth: CGFloat, widgetOrder: [BarSection],
                        widgetWidths: [BarSection: CGFloat] = [:]) -> DockStyle {
        var candidate = style
        while !fits(candidate, screenWidth: screenWidth, widgetOrder: widgetOrder, widgetWidths: widgetWidths) {
            if let smaller = DockSizeClass.allCases.last(where: { $0.barHeight < candidate.size.barHeight }) {
                candidate.size = smaller
            } else if let tighter = DockSpacing.allCases.last(where: { $0.gap < candidate.spacing.gap }) {
                candidate.spacing = tighter
            } else {
                break
            }
        }
        return candidate
    }

    static func fits(_ style: DockStyle, screenWidth: CGFloat, widgetOrder: [BarSection],
                     widgetWidths: [BarSection: CGFloat]) -> Bool {
        // A rail's room is the screen height, not its width; its compact tiles always fit there.
        guard !style.placement.isVertical else { return true }
        let height = style.size.barHeight
        let layout = IslandLayoutSolver.layout(
            screenWidth: screenWidth, mode: style.mode, widgetOrder: widgetOrder, widgetWidths: widgetWidths,
            tileStride: IslandLayoutSolver.tileStride(barHeight: height), appCount: minimumAppTiles,
            weatherWidth: BarSection.weather.defaultWidgetWidth, clockWidth: BarSection.clock.defaultWidgetWidth,
            clusterWidth: height, gap: style.spacing.gap, margin: style.spacing.margin,
            barHeight: height, bottomMargin: style.bottomGap)
        return !layout.showsOverflow
    }

    /// Fine-tune's Bar Height cap: the tallest height (whole points, ≤ `DockPanelHeight.maximum`)
    /// at which this mode/spacing still shows `minimumAppTiles` without overflow on this screen.
    static func maximumBarHeight(mode: BarLayoutMode, gap: CGFloat, margin: CGFloat, bottomGap: CGFloat,
                                 screenWidth: CGFloat, widgetOrder: [BarSection],
                                 widgetWidths: [BarSection: CGFloat] = [:],
                                 range: ClosedRange<CGFloat>) -> CGFloat {
        var height = range.upperBound.rounded(.down)
        while height > range.lowerBound {
            let layout = IslandLayoutSolver.layout(
                screenWidth: screenWidth, mode: mode, widgetOrder: widgetOrder, widgetWidths: widgetWidths,
                tileStride: IslandLayoutSolver.tileStride(barHeight: height), appCount: minimumAppTiles,
                weatherWidth: BarSection.weather.defaultWidgetWidth, clockWidth: BarSection.clock.defaultWidgetWidth,
                clusterWidth: height, gap: gap, margin: margin, barHeight: height, bottomMargin: bottomGap)
            if !layout.showsOverflow { return height }
            height -= 1
        }
        return range.lowerBound
    }
}

