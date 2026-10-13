import CoreGraphics
import Foundation

/// Preset size of a strip widget (Phase 10a): S = glyph + value, M = adds a label,
/// L = adds detail. `medium` equals today's `BarSection.defaultWidgetWidth`, so the
/// default layout renders exactly as before.
enum WidgetSize: String, Codable, CaseIterable, Sendable, Comparable {
    case small
    case medium
    case large

    private var rank: Int {
        switch self {
        case .small: return 0
        case .medium: return 1
        case .large: return 2
        }
    }

    static func < (lhs: WidgetSize, rhs: WidgetSize) -> Bool { lhs.rank < rhs.rank }
}

extension BarSection {
    /// Sections that offer S/M/L presets. The others keep a single fixed width.
    var supportsWidgetSizes: Bool {
        switch self {
        case .weather, .media, .clock: return true
        case .launcher, .apps, .widgets: return false
        }
    }

    /// Declared width for a size preset. Non-sizable sections always return their default.
    func widgetWidth(for size: WidgetSize) -> CGFloat {
        guard supportsWidgetSizes else { return defaultWidgetWidth }
        switch (self, size) {
        // 84, not 64: S keeps glyph + temperature, and 64 left ~28 pt inside the slot and pill
        // padding — the temperature truncated to "°" (Phase 11d live check).
        case (.weather, .small): return 84
        case (.weather, .medium): return 150
        case (.weather, .large): return 230
        case (.clock, .small): return 76
        case (.clock, .medium): return 160
        case (.clock, .large): return 210
        case (.media, .small): return 72
        case (.media, .medium): return 140
        case (.media, .large): return 240
        default: return defaultWidgetWidth
        }
    }
}

/// Auto-degrade rule ("presets when they hold less space"): L → M → S.
enum WidgetSizePolicy {
    /// The largest size ≤ `requested` whose declared width fits `availableWidth`;
    /// falls back to `.small` when nothing fits.
    static func resolve(_ section: BarSection, requested: WidgetSize, availableWidth: CGFloat) -> WidgetSize {
        guard section.supportsWidgetSizes else { return requested }
        for size in WidgetSize.allCases.reversed() where size <= requested {
            if section.widgetWidth(for: size) <= availableWidth { return size }
        }
        return .small
    }
}

/// One placed widget. `exactWidth` is the advanced slider override (legacy `widgetWidths`)
/// and wins over the size preset.
struct WidgetInstance: Codable, Equatable, Sendable {
    var section: BarSection
    var size: WidgetSize = .medium
    var isVisible: Bool = true
    var exactWidth: CGFloat?
    /// 10a-6: when set, this slot is a Smart Stack holding these widgets and shows the most relevant one.
    var stack: [BarSection]?
}

/// The persisted widget arrangement: order + per-widget size/visibility.
struct WidgetLayout: Codable, Equatable, Sendable {
    static let defaultsKey = "com.katikati.widgets.layout.v1"

    private(set) var instances: [WidgetInstance]

    /// Today's behaviour: canonical order, every widget visible at medium, no overrides.
    static let `default` = WidgetLayout(instances: BarSection.canonicalOrder.map { WidgetInstance(section: $0) })

    /// Always a permutation of all sections: unknown/duplicate entries dropped, missing appended.
    init(instances: [WidgetInstance]) {
        var seen = Set<BarSection>()
        var normalized = instances.filter { seen.insert($0.section).inserted }
        for section in BarSection.canonicalOrder where !seen.contains(section) {
            normalized.append(WidgetInstance(section: section))
        }
        self.instances = normalized
    }

    var order: [BarSection] { instances.map(\.section) }

    func instance(for section: BarSection) -> WidgetInstance {
        instances.first { $0.section == section } ?? WidgetInstance(section: section)
    }

    /// Order handed to the island solver / strip: hidden widgets dropped (`apps` can't be hidden).
    var visibleOrder: [BarSection] {
        instances.filter { $0.isVisible || $0.section == .apps }.map(\.section)
    }

    /// Moves the section at `source` offsets to `destination` (SwiftUI `onMove` semantics).
    func moving(from source: IndexSet, to destination: Int) -> WidgetLayout {
        var list = instances
        let moved = source.sorted().map { list[$0] }
        let before = source.filter { $0 < destination }.count
        for index in source.sorted().reversed() { list.remove(at: index) }
        list.insert(contentsOf: moved, at: destination - before)
        return WidgetLayout(instances: list)
    }

    var hiddenSections: Set<BarSection> {
        Set(instances.filter { !$0.isVisible }.map(\.section))
    }

    /// Width overrides to hand `IslandLayoutSolver` (`widgetWidths`). Empty for the default
    /// layout — the solver then uses its own defaults, so nothing changes.
    func solverWidths(availableWidth: CGFloat = .greatestFiniteMagnitude) -> [BarSection: CGFloat] {
        var result: [BarSection: CGFloat] = [:]
        for inst in instances {
            if let exact = inst.exactWidth {
                result[inst.section] = exact
            } else if inst.section.supportsWidgetSizes {
                let size = WidgetSizePolicy.resolve(inst.section, requested: inst.size, availableWidth: availableWidth)
                if size != .medium { result[inst.section] = inst.section.widgetWidth(for: size) }
            }
        }
        return result
    }

    /// Copy with `section` edited; no-op for unknown sections.
    func updating(_ section: BarSection, _ edit: (inout WidgetInstance) -> Void) -> WidgetLayout {
        WidgetLayout(instances: instances.map { inst in
            guard inst.section == section else { return inst }
            var copy = inst
            edit(&copy)
            return copy
        })
    }

    /// Width the strip should give `section`: exact override, else the size preset, floored at
    /// the section's intrinsic minimum.
    func width(for section: BarSection) -> CGFloat {
        let inst = instance(for: section)
        let raw = inst.exactWidth ?? section.widgetWidth(for: inst.size)
        return max(raw, inst.exactWidth == nil ? section.minimumWidgetWidth : section.minimumExactWidth)
    }

    /// Auto-degrade to fit a width budget (L→M→S, widest first) — the "presets when they hold less space"
    /// behaviour. Hand-set exact widths and non-sizable widgets are never touched. Not persisted.
    func fitted(toBudget budget: CGFloat) -> WidgetLayout {
        var layout = self
        func total(_ l: WidgetLayout) -> CGFloat {
            l.instances.filter { $0.isVisible && $0.section != .apps }.reduce(0) { $0 + l.width(for: $1.section) }
        }
        while total(layout) > budget {
            let candidate = layout.instances
                .filter { $0.isVisible && $0.exactWidth == nil && $0.section.supportsWidgetSizes && $0.size > .small }
                .max { layout.width(for: $0.section) < layout.width(for: $1.section) }
            guard let section = candidate?.section else { break }
            layout = layout.updating(section) { $0.size = $0.size == .large ? .medium : .small }
        }
        return layout
    }

    /// What the island row can spend on widgets: the screen minus side margins, island gaps and room for ~6 app tiles.
    /// With a `mode`, the gaps are that mode's island gaps plus the strip chrome each island draws
    /// (`IslandChrome.overhead`), so widgets degrade before split islands could collide (Phase 11a);
    /// the result is in native-scale points, the unit widget widths are authored in.
    static func widgetBudget(screenWidth: CGFloat, margin: CGFloat, gap: CGFloat, tileStride: CGFloat,
                             mode: BarLayoutMode? = nil, order: [BarSection] = BarSection.canonicalOrder,
                             barHeight: CGFloat = IslandChrome.nativeBarHeight) -> CGFloat {
        let apps = 6 * tileStride + 24
        guard let mode else { return screenWidth - 2 * margin - 5 * gap - apps }
        let scale = IslandChrome.scale(barHeight: barHeight)
        let overhead = IslandChrome.overhead(mode: mode, order: order, gap: gap, scale: scale)
        // Widths are compared at native scale (they are drawn scaled by bar height, Phase 11d).
        return (screenWidth - 2 * margin - overhead - apps) / max(scale, 0.01)
    }

    /// First-run migration from the legacy `widgetWidths` slider overrides.
    static func migrating(legacyWidths: [String: CGFloat]) -> WidgetLayout {
        WidgetLayout(instances: BarSection.canonicalOrder.map { section in
            var inst = WidgetInstance(section: section)
            if let width = legacyWidths[section.rawValue] { inst.exactWidth = width }
            return inst
        })
    }

    static func decode(_ data: Data?) -> WidgetLayout? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(WidgetLayout.self, from: data)
    }

    func encoded() -> Data? { try? JSONEncoder().encode(self) }
}
