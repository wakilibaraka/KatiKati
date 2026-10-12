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
}
