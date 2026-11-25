import XCTest
@testable import KatiKati

final class WindowChipGroupingTests: XCTestCase {
    private struct W: Equatable { let id: String; let bundle: String?; let fallback: Bool }
    private func merge(_ slots: [[W]], _ plan: WindowChipGroupingPlan) -> [[W]] {
        WindowChipGrouping.merge(slots: slots, bundleID: { $0.bundle }, isFallback: { $0.fallback }, plan: plan)
    }
    private let a1 = W(id: "a1", bundle: "A", fallback: false)
    private let b1 = W(id: "b1", bundle: "B", fallback: false)
    private let a2 = W(id: "a2", bundle: "A", fallback: false)
    private let a3 = W(id: "a3", bundle: "A", fallback: false)

    /// Golden: the default plan must return today's output unchanged.
    func testDefaultPlanChangesNothing() {
        let slots = [[a1], [b1], [a2]]
        XCTAssertEqual(merge(slots, .ungrouped), slots)
        XCTAssertTrue(WindowChipGroupingPlan.ungrouped.isInert)
    }

    func testGroupedAppCollapsesAtFirstAppearance() {
        var plan = WindowChipGroupingPlan()
        plan.overrides["A"] = .grouped
        XCTAssertEqual(merge([[a1], [b1], [a2], [a3]], plan), [[a1, a2, a3], [b1]])
    }

    func testDefaultGroupedWithSeparateOverride() {
        var plan = WindowChipGroupingPlan(defaultPolicy: .grouped)
        plan.overrides["B"] = .separate
        let b2 = W(id: "b2", bundle: "B", fallback: false)
        XCTAssertEqual(merge([[a1], [b1], [a2], [b2]], plan), [[a1, a2], [b1], [b2]])
    }

    func testFallbackAndUnknownBundlePassThrough() {
        let fb = W(id: "app-A", bundle: "A", fallback: true)
        let anon = W(id: "x", bundle: nil, fallback: false)
        let plan = WindowChipGroupingPlan(defaultPolicy: .grouped)
        XCTAssertEqual(merge([[fb], [anon], [anon]], plan), [[fb], [anon], [anon]])
    }

    func testNativeTabGroupSlotsStayTogether() {
        var plan = WindowChipGroupingPlan()
        plan.overrides["A"] = .grouped
        XCTAssertEqual(merge([[a1, a2], [a3]], plan), [[a1, a2, a3]])
    }

    func testTokenRoundTrip() {
        let t = WindowChipGroupingPlan.groupToken(bundleID: "com.x.y")
        XCTAssertEqual(WindowChipGroupingPlan.bundleID(fromToken: t), "com.x.y")
        XCTAssertNil(WindowChipGroupingPlan.bundleID(fromToken: "tabgrp-1"))
    }

    func testCycleWrapsAndStartsAtFirst() {
        XCTAssertEqual(WindowChipGrouping.nextIndex(count: 3, frontIndex: nil), 0)
        XCTAssertEqual(WindowChipGrouping.nextIndex(count: 3, frontIndex: 0), 1)
        XCTAssertEqual(WindowChipGrouping.nextIndex(count: 3, frontIndex: 2), 0)
        XCTAssertEqual(WindowChipGrouping.nextIndex(count: 0, frontIndex: nil), 0)
    }

    func testAppIconPresentationPresetPropertiesAndResolution() {
        XCTAssertEqual(AppIconPresentationPreset.defaultHorizontal, .appPills)
        XCTAssertEqual(AppIconPresentationPreset.defaultVertical, .iconsOnly)
        XCTAssertEqual(AppIconPresentationPreset.resolved(stored: nil, isVertical: false), .appPills)
        XCTAssertEqual(AppIconPresentationPreset.resolved(stored: nil, isVertical: true), .iconsOnly)
        XCTAssertEqual(AppIconPresentationPreset.resolved(stored: "windowCards", isVertical: true), .windowCards)

        XCTAssertEqual(AppIconPresentationPreset.appPills.groupingPolicy, .grouped)
        XCTAssertTrue(AppIconPresentationPreset.appPills.usesAppNameOnly)
        XCTAssertTrue(AppIconPresentationPreset.appPills.showsLabel)
        XCTAssertFalse(AppIconPresentationPreset.appPills.effectiveIconOnly(isVertical: false))
        XCTAssertTrue(AppIconPresentationPreset.appPills.effectiveIconOnly(isVertical: true))

        XCTAssertEqual(AppIconPresentationPreset.windowCards.groupingPolicy, .separate)
        XCTAssertFalse(AppIconPresentationPreset.windowCards.usesAppNameOnly)
        XCTAssertFalse(AppIconPresentationPreset.windows11Grouped.showsLabel)
        XCTAssertTrue(AppIconPresentationPreset.windows11Grouped.showsMultiWindowBadge)
        XCTAssertGreaterThan(AppIconPresentationPreset.windows10Taskbar.maxLabelWidth,
                             AppIconPresentationPreset.windowCards.maxLabelWidth)
    }

    func testDockSpacingConfigClamping() {
        XCTAssertEqual(DockSpacingConfig.default.iconSpacing, 1)
        XCTAssertEqual(DockSpacingConfig.default.sectionSpacing,
                       DockSpacingConfig.sectionSpacingRange.lowerBound,
                       "sections default to the tightest gap (owner 2026-11-25)")
        XCTAssertEqual(DockSpacingConfig.iconSpacingRange, -2...12)
        XCTAssertEqual(DockSpacingConfig.sectionSpacingRange, 3...20)
        XCTAssertTrue(DockSpacingConfig.iconSpacingRange.contains(0))

        let extreme = DockSpacingConfig(iconSpacing: -10, sectionSpacing: 99, dynamicCompressionEnabled: false).clamped()
        XCTAssertEqual(extreme.iconSpacing, DockSpacingConfig.iconSpacingRange.lowerBound)
        XCTAssertEqual(extreme.sectionSpacing, DockSpacingConfig.sectionSpacingRange.upperBound)
        XCTAssertFalse(extreme.dynamicCompressionEnabled)
    }

    func testDockDynamicCompressionRespectsZeroAndNegativeIconSpacing() {
        for userIconSpacing in [-2.0, 0.0] as [CGFloat] {
            let cfg = DockSpacingConfig(iconSpacing: userIconSpacing, sectionSpacing: 8, dynamicCompressionEnabled: true)
            let result = DockDynamicCompressionSolver.solve(
                availableWidth: 680, fixedWidth: 100, labeledChipCount: 4, iconChipCount: 4,
                baseIconWidth: 40, baseLabelWidth: 164, spacing: cfg, sectionGapCount: 2
            )
            XCTAssertGreaterThanOrEqual(result.stage, 2)
            XCTAssertEqual(result.iconSpacing, userIconSpacing, accuracy: 0.001,
                           "Stage 2 compression must not expand user spacing of \(userIconSpacing) pt")
            XCTAssertGreaterThanOrEqual(result.sectionSpacing, DockDynamicCompressionSolver.minSectionSpacing - 0.001)
            XCTAssertLessThanOrEqual(result.sectionSpacing, 8)
        }

        let maxCompressed = DockDynamicCompressionSolver.solve(
            availableWidth: 500, fixedWidth: 100, labeledChipCount: 4, iconChipCount: 2,
            baseIconWidth: 40, baseLabelWidth: 164,
            spacing: DockSpacingConfig(iconSpacing: 4, sectionSpacing: 10, dynamicCompressionEnabled: true),
            sectionGapCount: 2
        )
        XCTAssertEqual(maxCompressed.stage, 3)
        XCTAssertEqual(maxCompressed.iconSpacing, DockDynamicCompressionSolver.minIconSpacing, accuracy: 0.001)
        XCTAssertEqual(maxCompressed.sectionSpacing, DockDynamicCompressionSolver.minSectionSpacing, accuracy: 0.001)
    }

    func testDockDynamicCompressionStagesAndDisabledScrollFallback() {
        let baseSpacing = DockSpacingConfig(iconSpacing: 8, sectionSpacing: 14, dynamicCompressionEnabled: true)

        // Stage 0: fits naturally
        let s0 = DockDynamicCompressionSolver.solve(
            availableWidth: 1200, fixedWidth: 100, labeledChipCount: 4, iconChipCount: 2,
            baseIconWidth: 40, baseLabelWidth: 164, spacing: baseSpacing, sectionGapCount: 2
        )
        XCTAssertEqual(s0.stage, 0)
        XCTAssertEqual(s0.labelWidth, 164)
        XCTAssertEqual(s0.iconScale, 1.0)
        XCTAssertFalse(s0.needsScroll)

        // Stage 1: shrinks labels only (100 + 4*204 + 2*40 + 5*8 + 2*14 = 1064; 944 leaves 120pt -> 30pt/label)
        let s1 = DockDynamicCompressionSolver.solve(
            availableWidth: 944, fixedWidth: 100, labeledChipCount: 4, iconChipCount: 2,
            baseIconWidth: 40, baseLabelWidth: 164, spacing: baseSpacing, sectionGapCount: 2
        )
        XCTAssertEqual(s1.stage, 1)
        XCTAssertEqual(s1.labelWidth, 134, accuracy: 0.5)
        XCTAssertEqual(s1.iconSpacing, 8)
        XCTAssertEqual(s1.iconScale, 1.0)
        XCTAssertFalse(s1.needsScroll)

        // Stage 2: labels floored at 88 (width 760), spacing tightens down (e.g. 730)
        let s2 = DockDynamicCompressionSolver.solve(
            availableWidth: 730, fixedWidth: 100, labeledChipCount: 4, iconChipCount: 2,
            baseIconWidth: 40, baseLabelWidth: 164, spacing: baseSpacing, sectionGapCount: 2
        )
        XCTAssertEqual(s2.stage, 2)
        XCTAssertEqual(s2.labelWidth, 88)
        XCTAssertLessThan(s2.iconSpacing, 8)
        XCTAssertLessThan(s2.sectionSpacing, 14)
        XCTAssertEqual(s2.iconScale, 1.0)
        XCTAssertFalse(s2.needsScroll)

        // Stage 3: scale absorbs moderate overflow without scroll; extreme overflow sets needsScroll
        let s3Fit = DockDynamicCompressionSolver.solve(
            availableWidth: 640, fixedWidth: 100, labeledChipCount: 4, iconChipCount: 2,
            baseIconWidth: 40, baseLabelWidth: 164, spacing: baseSpacing, sectionGapCount: 2
        )
        XCTAssertEqual(s3Fit.stage, 3)
        XCTAssertLessThan(s3Fit.iconScale, 1.0)
        XCTAssertGreaterThanOrEqual(s3Fit.iconScale, DockDynamicCompressionSolver.minIconScale)
        XCTAssertFalse(s3Fit.needsScroll)

        let s3Scroll = DockDynamicCompressionSolver.solve(
            availableWidth: 420, fixedWidth: 100, labeledChipCount: 4, iconChipCount: 2,
            baseIconWidth: 40, baseLabelWidth: 164, spacing: baseSpacing, sectionGapCount: 2
        )
        XCTAssertEqual(s3Scroll.stage, 3)
        XCTAssertEqual(s3Scroll.iconScale, DockDynamicCompressionSolver.minIconScale)
        XCTAssertTrue(s3Scroll.needsScroll)

        // Disabled compression preserves full metrics and flags scroll
        var disabledCfg = baseSpacing
        disabledCfg.dynamicCompressionEnabled = false
        let disabled = DockDynamicCompressionSolver.solve(
            availableWidth: 900, fixedWidth: 100, labeledChipCount: 4, iconChipCount: 2,
            spacing: disabledCfg, sectionGapCount: 2
        )
        XCTAssertEqual(disabled.stage, 0)
        XCTAssertEqual(disabled.labelWidth, 164)
        XCTAssertTrue(disabled.needsScroll)
    }
}
