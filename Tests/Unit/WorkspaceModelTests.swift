import XCTest
@testable import KatiKati

/// W-1: workspace identity, the registry, ownership, and the switch plan. All pure — no screen, no
/// Accessibility, no window.
final class WorkspaceModelTests: XCTestCase {
    private let display = "display-a"
    private let otherDisplay = "display-b"

    // MARK: - Identity

    func testTokenRoundTrips() {
        XCTAssertEqual(WorkspaceID(token: "1"), .numbered(1))
        XCTAssertEqual(WorkspaceID(token: "10"), .numbered(10))
        XCTAssertEqual(WorkspaceID(token: "d"), .named("D"))
        XCTAssertEqual(WorkspaceID(token: " D "), .named("D"))
        XCTAssertEqual(WorkspaceID.numbered(7).token, "7")
        XCTAssertEqual(WorkspaceID.named("Q").token, "Q")
    }

    func testOutOfRangeAndJunkAreRejected() {
        XCTAssertNil(WorkspaceID(token: "0"))
        XCTAssertNil(WorkspaceID(token: "11"))
        XCTAssertNil(WorkspaceID(token: "AB"))
        XCTAssertNil(WorkspaceID(token: "é"))
        XCTAssertNil(WorkspaceID(token: ""))
    }

    func testNumbersSortBeforeLetters() {
        let ids: [WorkspaceID] = [.named("A"), .numbered(10), .numbered(2), .named("Z")]
        XCTAssertEqual(ids.sorted(), [.numbered(2), .numbered(10), .named("A"), .named("Z")])
    }

    func testNumberRowKeyCodesMapToWorkspaces() {
        XCTAssertEqual(WorkspaceID.numbered(1).shortcutKeyCode, 18)
        XCTAssertEqual(WorkspaceID.numbered(0 + 10).shortcutKeyCode, 29)
        XCTAssertEqual(WorkspaceID.numbered(forKeyCode: 20), .numbered(3))
        XCTAssertEqual(WorkspaceID.numbered(forKeyCode: 29), .numbered(10))
        XCTAssertNil(WorkspaceID.numbered(forKeyCode: 0))
    }

    // MARK: - Registry

    func testDefaultRegistryHasTenNumberedWorkspaces() {
        let registry = WorkspaceRegistry.default
        XCTAssertEqual(registry.workspaces.count, 10)
        XCTAssertTrue(registry.named.isEmpty)
        XCTAssertEqual(registry.workspaces(on: display).count, 10)
    }

    func testNamedWorkspaceIsOptInAndSortsAfterNumbers() {
        var registry = WorkspaceRegistry.default
        registry.enable(.named("D"))
        registry.enable(.named("D"))
        XCTAssertEqual(registry.workspaces.filter { $0.sortIndex >= 1000 }, [.named("D")])
        XCTAssertEqual(registry.workspaces.last, .named("D"))
    }

    func testDisplayAssignmentSplitsTheList() {
        var registry = WorkspaceRegistry.default
        for number in 1...5 { registry.setDisplay(display, for: .numbered(number)) }
        for number in 6...10 { registry.setDisplay(otherDisplay, for: .numbered(number)) }

        XCTAssertEqual(registry.workspaces(on: display), WorkspaceID.allNumbered.prefix(5).map { $0 })
        XCTAssertEqual(registry.workspaces(on: otherDisplay), WorkspaceID.allNumbered.suffix(5).map { $0 })
    }

    func testUnassignedWorkspacesFollowTheDisplayShowingThem() {
        var registry = WorkspaceRegistry.default
        registry.setDisplay(display, for: .numbered(1))
        // 2…10 are unassigned, so they are listed on both displays rather than disappearing.
        XCTAssertEqual(registry.workspaces(on: display).count, 10)
        XCTAssertEqual(registry.workspaces(on: otherDisplay).count, 9)
    }

    func testStepStopsAtEitherEnd() {
        let registry = WorkspaceRegistry.default
        XCTAssertEqual(registry.step(from: .numbered(1), by: 1, on: display), .numbered(2))
        XCTAssertNil(registry.step(from: .numbered(1), by: -1, on: display))
        XCTAssertNil(registry.step(from: .numbered(10), by: 1, on: display))
    }

    func testClearingADisplayAssignment() {
        var registry = WorkspaceRegistry.default
        registry.setDisplay(display, for: .numbered(3))
        registry.setDisplay(nil, for: .numbered(3))
        XCTAssertNil(registry.display(for: .numbered(3)))
    }

    // MARK: - Layout

    func testAssignKeepsJoinOrder() {
        let a = WindowID(rawValue: "a")
        let b = WindowID(rawValue: "b")
        var layout = WorkspaceLayout()
        layout.assign(a, to: display)
        layout.assign(b, to: display)
        layout.assign(a, to: display)
        XCTAssertEqual(layout.windows(on: display), [a, b])
        XCTAssertTrue(layout.contains(a))
    }

    func testRemoveClearsWindowsAndRememberedFocus() {
        let a = WindowID(rawValue: "a")
        var layout = WorkspaceLayout()
        layout.assign(a, to: display)
        layout.setFocus(a, on: display)
        layout.remove(a)
        XCTAssertTrue(layout.windows(on: display).isEmpty)
        XCTAssertNil(layout.focus[display])
    }

    func testFocusFallsBackToTheFirstWindow() {
        let a = WindowID(rawValue: "a")
        let b = WindowID(rawValue: "b")
        var layout = WorkspaceLayout()
        layout.assign(a, to: display)
        layout.assign(b, to: display)
        XCTAssertEqual(layout.focusTarget(on: display), a)
        layout.setFocus(b, on: display)
        XCTAssertEqual(layout.focusTarget(on: display), b)
        layout.remove(b)
        XCTAssertEqual(layout.focusTarget(on: display), a)
    }

    // MARK: - Store

    func testStoreTracksOwnershipAndMoves() {
        let a = WindowID(rawValue: "a")
        var store = WorkspaceStore()
        store.assign(a, to: .numbered(1), on: display)
        XCTAssertEqual(store.workspace(of: a), .numbered(1))

        XCTAssertEqual(store.move(a, to: .numbered(3), on: display), .numbered(1))
        XCTAssertEqual(store.workspace(of: a), .numbered(3))
        XCTAssertTrue(store.windows(in: .numbered(1), on: display).isEmpty)
    }

    func testMovingWithinTheSameWorkspaceIsANoOp() {
        let a = WindowID(rawValue: "a")
        var store = WorkspaceStore()
        store.assign(a, to: .numbered(2), on: display)
        XCTAssertEqual(store.move(a, to: .numbered(2), on: display), .numbered(2))
        XCTAssertEqual(store.windows(in: .numbered(2), on: display), [a])
    }

    func testWindowsOutsideOneWorkspaceAreTheParkSet() {
        let a = WindowID(rawValue: "a")
        let b = WindowID(rawValue: "b")
        var store = WorkspaceStore()
        store.assign(a, to: .numbered(1), on: display)
        store.assign(b, to: .numbered(2), on: display)
        XCTAssertEqual(store.windowsOutside(.numbered(1), on: display), [b])
        XCTAssertEqual(store.windowsOutside(.numbered(2), on: display), [a])
    }

    func testRemoveDropsAnEmptyWorkspace() {
        let a = WindowID(rawValue: "a")
        var store = WorkspaceStore()
        store.assign(a, to: .numbered(4), on: display)
        store.remove(a)
        XCTAssertNil(store.workspace(of: a))
        XCTAssertTrue(store.layouts[.numbered(4)] == nil)
    }

    /// The engine notices a window that moved to the other display through this, and re-assigning is
    /// how it migrates: the window must end up owned on the new display only.
    func testDisplayKeyFollowsTheWindowItOwns() {
        let a = WindowID(rawValue: "a")
        var store = WorkspaceStore()
        store.assign(a, to: .numbered(1), on: "builtin")
        XCTAssertEqual(store.displayKey(of: a), "builtin")
        XCTAssertNil(store.displayKey(of: WindowID(rawValue: "absent")))

        store.assign(a, to: .numbered(1), on: "external")
        XCTAssertEqual(store.displayKey(of: a), "external")
        XCTAssertEqual(store.windows(in: .numbered(1), on: "builtin"), [])
        XCTAssertEqual(store.windows(in: .numbered(1), on: "external"), [a])
    }

    // MARK: - Transition plan

    func testTransitionParksTheOldSetAndRevealsTheNewOne() {
        let old = WindowID(rawValue: "old")
        let new = WindowID(rawValue: "new")
        var store = WorkspaceStore()
        store.assign(old, to: .numbered(1), on: display)
        store.assign(new, to: .numbered(2), on: display)

        let plan = WorkspaceTransitionPlan.plan(
            store: store, leaving: .numbered(1), entering: .numbered(2), displayKey: display
        )
        XCTAssertEqual(plan.park, [old])
        XCTAssertEqual(plan.reveal, [new])
        XCTAssertEqual(plan.focus, new)
        XCTAssertFalse(plan.isEmpty)
    }

    func testSwitchingToTheSameWorkspaceIsNotATransition() {
        var store = WorkspaceStore()
        store.assign(WindowID(rawValue: "old"), to: .numbered(1), on: display)
        let plan = WorkspaceTransitionPlan.plan(
            store: store, leaving: .numbered(1), entering: .numbered(1), displayKey: display
        )
        XCTAssertTrue(plan.isEmpty)
    }

    func testTransitionFocusPrefersTheRememberedWindow() {
        let a = WindowID(rawValue: "a")
        let b = WindowID(rawValue: "b")
        var store = WorkspaceStore()
        store.assign(a, to: .numbered(2), on: display)
        store.assign(b, to: .numbered(2), on: display)
        store.setFocus(b, in: .numbered(2), on: display)
        let plan = WorkspaceTransitionPlan.plan(
            store: store, leaving: .numbered(1), entering: .numbered(2), displayKey: display
        )
        XCTAssertEqual(plan.focus, b)
        XCTAssertEqual(WorkspaceParking.parkingSet(plan), [])
    }
}

/// W-3: the parking geometry and the recovery record a switch and a quit depend on.
final class WorkspaceParkingTests: XCTestCase {
    private let area = CGRect(x: 0, y: 40, width: 1440, height: 860)

    func testSideIsRightUnlessADisplaySitsThere() {
        XCTAssertEqual(WorkspaceParking.side(neighbourOnRight: false), .right)
        XCTAssertEqual(WorkspaceParking.side(neighbourOnRight: true), .bottom)
    }

    func testParkedFrameHangsPastTheRightEdgeByTheGrantedSliver() {
        let frame = CGRect(x: 100, y: 100, width: 600, height: 400)
        let parked = WorkspaceParking.parked(frame, in: area, side: .right)
        XCTAssertEqual(parked.origin.x, area.maxX - StripParking.peek)
        XCTAssertEqual(parked.size, frame.size)
        XCTAssertGreaterThan(parked.minX, area.maxX - 2)
    }

    func testParkedFrameAtTheBottomEdgeKeepsItsWidth() {
        let frame = CGRect(x: 100, y: 100, width: 600, height: 400)
        let parked = WorkspaceParking.parked(frame, in: area, side: .bottom)
        XCTAssertEqual(parked.origin.y, area.minY - frame.height + StripParking.peek)
        XCTAssertEqual(parked.width, frame.width)
    }

    func testRevealFitsARecoveryFrameFromABiggerDisplay() {
        let recovery = CGRect(x: 1200, y: 300, width: 800, height: 600)
        let small = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let revealed = WorkspaceParking.revealFrame(recovery, in: small)
        XCTAssertLessThanOrEqual(revealed.maxX, small.maxX)
        XCTAssertLessThanOrEqual(revealed.maxY, small.maxY)
        XCTAssertEqual(revealed.size, CGSize(width: 800, height: 600))
    }

    func testRecordRoundTripsThroughJSON() throws {
        let record = WorkspaceParking.Record(
            windowID: "cgw-42",
            displayKey: "display-a",
            workspace: "3",
            recoveryFrame: CGRect(x: 10, y: 20, width: 300, height: 200),
            side: .right
        )
        let data = try JSONEncoder().encode([record])
        let decoded = try JSONDecoder().decode([WorkspaceParking.Record].self, from: data)
        XCTAssertEqual(decoded, [record])
        XCTAssertEqual(decoded.first?.parkingSide, .right)
    }

    func testUnknownSideTokenFallsBackToTheRightEdge() {
        let record = WorkspaceParking.Record(
            windowID: "w", displayKey: "d", workspace: "1",
            recoveryFrame: .zero, side: .bottom
        )
        var decoded = record
        decoded.side = "sideways"
        XCTAssertEqual(decoded.parkingSide, .right)
    }
}
