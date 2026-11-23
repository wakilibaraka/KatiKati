import CoreGraphics
import Foundation

// Phase 9a — per-app window-chip grouping. Pure: no AppKit, no clock, no strings.
//
// Today every window gets its own chip ("separate"). A user can opt an app into "grouped": all of
// that app's windows collapse into ONE chip (reusing the multi-member chip the native-tab-group
// path already renders). The default stays `.separate`, so nothing moves unless the user asks —
// golden tests pin that.

enum WindowChipGroupPolicy: String, CaseIterable, Codable, Sendable {
    case separate
    case grouped
}

struct WindowChipGroupingPlan: Equatable, Sendable {
    var defaultPolicy: WindowChipGroupPolicy = .separate
    /// bundle ID → explicit policy. Absent = follow `defaultPolicy`.
    var overrides: [String: WindowChipGroupPolicy] = [:]

    static let ungrouped = WindowChipGroupingPlan()

    func policy(for bundleID: String?) -> WindowChipGroupPolicy {
        guard let bundleID else { return .separate }
        return overrides[bundleID] ?? defaultPolicy
    }

    /// True when no app can possibly be grouped (lets callers skip all work).
    var isInert: Bool {
        defaultPolicy == .separate && !overrides.values.contains(.grouped)
    }

    /// Stable chip identity for an app-level group. Never changes as windows come and go.
    static func groupToken(bundleID: String) -> String { "appgrp-\(bundleID)" }
    static func bundleID(fromToken token: String) -> String? {
        token.hasPrefix("appgrp-") ? String(token.dropFirst("appgrp-".count)) : nil
    }
}

enum WindowChipGrouping {
    /// Merges every app's slots into one slot when the plan groups that app and it has ≥ 2 real
    /// slots. The merged slot sits where the app's first slot was (first-appearance order, like the
    /// native tab-group collapse). Fallback (`app-*`) slots and ungrouped apps pass through untouched.
    static func merge<T>(
        slots: [[T]],
        bundleID: (T) -> String?,
        isFallback: (T) -> Bool,
        plan: WindowChipGroupingPlan
    ) -> [[T]] {
        guard !plan.isInert else { return slots }
        var result: [[T]] = []
        var indexByBundle: [String: Int] = [:]
        for slot in slots {
            guard let first = slot.first, !isFallback(first),
                  let bid = bundleID(first), plan.policy(for: bid) == .grouped else {
                result.append(slot)
                continue
            }
            if let idx = indexByBundle[bid] {
                result[idx].append(contentsOf: slot)
            } else {
                indexByBundle[bid] = result.count
                result.append(slot)
            }
        }
        return result
    }

    /// Which member a click on a grouped chip should raise: the window after the front one
    /// (wrapping), so repeated clicks cycle the app's windows. `frontIndex == nil` → the first.
    static func nextIndex(count: Int, frontIndex: Int?) -> Int {
        guard count > 0 else { return 0 }
        guard let frontIndex else { return 0 }
        return (frontIndex + 1) % count
    }
}

// MARK: - App Icon Presentation Presets & Dynamic Compression (Slice DO-6)

/// Named presets preserving existing per-window and grouped-app engines across horizontal/vertical docks.
enum AppIconPresentationPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case appPills
    case windowCards
    case iconsOnly
    case windows11Grouped
    case windows10Taskbar

    static let defaultsKey = "com.katikati.dock.appIconPreset"
    static let defaultHorizontal: Self = .appPills
    static let defaultVertical: Self = .iconsOnly

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .appPills: return String(localized: "App Pills")
        case .windowCards: return String(localized: "Window Cards")
        case .iconsOnly: return String(localized: "Icons Only")
        case .windows11Grouped: return String(localized: "Windows 11 Grouped")
        case .windows10Taskbar: return String(localized: "Windows 10 Taskbar")
        }
    }

    var groupingPolicy: WindowChipGroupPolicy {
        switch self {
        case .appPills, .iconsOnly, .windows11Grouped: return .grouped
        case .windowCards, .windows10Taskbar: return .separate
        }
    }

    var showsLabel: Bool {
        switch self {
        case .appPills, .windowCards, .windows10Taskbar: return true
        case .iconsOnly, .windows11Grouped: return false
        }
    }

    var usesAppNameOnly: Bool { self == .appPills }

    var showsMultiWindowBadge: Bool {
        switch self {
        case .windows11Grouped, .appPills, .iconsOnly: return true
        case .windowCards, .windows10Taskbar: return false
        }
    }

    var maxLabelWidth: CGFloat {
        switch self {
        case .appPills: return 132
        case .windowCards: return 164
        case .windows10Taskbar: return 196
        case .iconsOnly, .windows11Grouped: return 0
        }
    }

    func effectiveIconOnly(isVertical: Bool) -> Bool { isVertical || !showsLabel }

    static func resolved(stored: String?, isVertical: Bool) -> AppIconPresentationPreset {
        stored.flatMap(Self.init(rawValue:)) ?? (isVertical ? .iconsOnly : .appPills)
    }
}

/// Symmetrical spacing configuration for Dock app icons and inter-section gaps.
struct DockSpacingConfig: Equatable, Codable, Sendable {
    static let defaultsKey = "com.katikati.dock.spacingConfig.v1"
    static let iconSpacingRange: ClosedRange<CGFloat> = 2...16
    static let sectionSpacingRange: ClosedRange<CGFloat> = 6...24

    var iconSpacing: CGFloat = 6
    var sectionSpacing: CGFloat = 12
    var dynamicCompressionEnabled: Bool = true

    static let `default` = DockSpacingConfig()

    func clamped() -> DockSpacingConfig {
        DockSpacingConfig(
            iconSpacing: min(max(iconSpacing, Self.iconSpacingRange.lowerBound), Self.iconSpacingRange.upperBound),
            sectionSpacing: min(max(sectionSpacing, Self.sectionSpacingRange.lowerBound), Self.sectionSpacingRange.upperBound),
            dynamicCompressionEnabled: dynamicCompressionEnabled
        )
    }
}

struct DockDynamicCompressionResult: Equatable, Sendable {
    var labelWidth: CGFloat
    var iconSpacing: CGFloat
    var sectionSpacing: CGFloat
    var iconScale: CGFloat
    var stage: Int
    var needsScroll: Bool
}

/// Three-stage anti-overflow solver: (1) shrink pill labels -> (2) tighten spacing symmetrically -> (3) gently scale icons.
enum DockDynamicCompressionSolver {
    static let minLabelWidth: CGFloat = 88
    static let minIconSpacing: CGFloat = 2
    static let minSectionSpacing: CGFloat = 5
    static let minIconScale: CGFloat = 0.78

    static func solve(
        availableWidth: CGFloat,
        fixedWidth: CGFloat,
        labeledChipCount: Int,
        iconChipCount: Int,
        baseIconWidth: CGFloat = 40,
        baseLabelWidth: CGFloat = 164,
        spacing: DockSpacingConfig = .default,
        sectionGapCount: Int = 0
    ) -> DockDynamicCompressionResult {
        let cfg = spacing.clamped()
        let labeled = max(0, labeledChipCount)
        let totalChips = labeled + max(0, iconChipCount)
        let chipGaps = CGFloat(max(0, totalChips - 1))
        let sectionGaps = CGFloat(max(0, sectionGapCount))
        let baseLabel = labeled > 0 ? max(0, baseLabelWidth) : 0

        func totalWidth(labelWidth: CGFloat, iconGap: CGFloat, sectionGap: CGFloat, scale: CGFloat) -> CGFloat {
            fixedWidth + scale * (
                CGFloat(totalChips) * baseIconWidth
                    + CGFloat(labeled) * labelWidth
                    + chipGaps * iconGap
                    + sectionGaps * sectionGap
            )
        }

        let natural = totalWidth(labelWidth: baseLabel, iconGap: cfg.iconSpacing, sectionGap: cfg.sectionSpacing, scale: 1.0)
        if !cfg.dynamicCompressionEnabled || natural <= availableWidth {
            return .init(labelWidth: baseLabel, iconSpacing: cfg.iconSpacing, sectionSpacing: cfg.sectionSpacing,
                         iconScale: 1.0, stage: 0, needsScroll: natural > availableWidth)
        }

        // Stage 1: shrink pill label width toward minLabelWidth
        let minLabel = min(baseLabel, minLabelWidth)
        if labeled > 0, baseLabel > minLabel {
            let maxReduction = CGFloat(labeled) * (baseLabel - minLabel)
            let excess = natural - availableWidth
            if excess <= maxReduction {
                return .init(labelWidth: baseLabel - excess / CGFloat(labeled), iconSpacing: cfg.iconSpacing,
                             sectionSpacing: cfg.sectionSpacing, iconScale: 1.0, stage: 1, needsScroll: false)
            }
        }
        let s1Label = labeled > 0 ? minLabel : baseLabel
        let w1 = totalWidth(labelWidth: s1Label, iconGap: cfg.iconSpacing, sectionGap: cfg.sectionSpacing, scale: 1.0)

        // Stage 2: tighten icon & section spacing symmetrically toward floors
        let minIcon = min(cfg.iconSpacing, minIconSpacing)
        let minSection = min(cfg.sectionSpacing, minSectionSpacing)
        let maxGapReduction = chipGaps * (cfg.iconSpacing - minIcon) + sectionGaps * (cfg.sectionSpacing - minSection)
        if maxGapReduction > 0, (w1 - availableWidth) <= maxGapReduction {
            let t = min(1, max(0, (w1 - availableWidth) / maxGapReduction))
            return .init(labelWidth: s1Label, iconSpacing: cfg.iconSpacing - (cfg.iconSpacing - minIcon) * t,
                         sectionSpacing: cfg.sectionSpacing - (cfg.sectionSpacing - minSection) * t,
                         iconScale: 1.0, stage: 2, needsScroll: false)
        }
        let w2 = totalWidth(labelWidth: s1Label, iconGap: minIcon, sectionGap: minSection, scale: 1.0)

        // Stage 3: gentle icon/pill scale down to minIconScale before resorting to scroll
        let scalable = max(0, w2 - fixedWidth)
        let scale: CGFloat = scalable > 0
            ? max(minIconScale, min(1.0, max(0, availableWidth - fixedWidth) / scalable))
            : minIconScale
        let w3 = totalWidth(labelWidth: s1Label, iconGap: minIcon, sectionGap: minSection, scale: scale)
        return .init(labelWidth: s1Label, iconSpacing: minIcon, sectionSpacing: minSection,
                     iconScale: scale, stage: 3, needsScroll: w3 > availableWidth + 0.5)
    }
}
