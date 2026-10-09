import XCTest
@testable import KatiKati

final class AtomicFullscreenTests: XCTestCase {
    func testSlotKeyDisplayGrouping() {
        let displayA = "display-uuid-alpha"
        let displayB = "display-uuid-beta"

        // 4 slots on display A, 4 slots on display B (split4 mode)
        let slotsA = (0..<4).map { IslandSlotSet.SlotKey(display: displayA, slot: $0) }
        let slotsB = (0..<4).map { IslandSlotSet.SlotKey(display: displayB, slot: $0) }
        let allSlots = slotsA + slotsB

        let filteredA = allSlots.filter { $0.display == displayA }
        let filteredB = allSlots.filter { $0.display == displayB }

        XCTAssertEqual(filteredA.count, 4)
        XCTAssertEqual(filteredB.count, 4)
        XCTAssertEqual(filteredA.map(\.slot), [0, 1, 2, 3])
        XCTAssertEqual(filteredB.map(\.slot), [0, 1, 2, 3])
    }

    func testAtomicFullscreenStateTransitionsPerDisplay() {
        // Simulate visibility states for 4 slots on Display A and 4 slots on Display B
        var displayAStates = (0..<4).map { _ in PanelVisibilityState() }
        let displayBStates = (0..<4).map { _ in PanelVisibilityState() }

        // Initially all are visible (no hide reasons)
        for state in displayAStates + displayBStates {
            XCTAssertTrue(state.isVisible)
            XCTAssertTrue(state.hideReasons.isEmpty)
        }

        // Display A enters fullscreen -> all slots on Display A update atomically
        for i in 0..<displayAStates.count {
            displayAStates[i].setFullscreen(true)
        }

        // All slots on Display A are now hidden for fullscreen
        for (slot, state) in displayAStates.enumerated() {
            XCTAssertFalse(state.isVisible, "Slot \(slot) on Display A must be hidden")
            XCTAssertTrue(state.hideReasons.contains(.fullscreen))
        }

        // Display B slots remain completely unaffected (visible)
        for (slot, state) in displayBStates.enumerated() {
            XCTAssertTrue(state.isVisible, "Slot \(slot) on Display B must remain visible")
            XCTAssertFalse(state.hideReasons.contains(.fullscreen))
        }

        // Display A exits fullscreen -> all slots on Display A restore atomically
        for i in 0..<displayAStates.count {
            displayAStates[i].setFullscreen(false)
        }

        for (slot, state) in displayAStates.enumerated() {
            XCTAssertTrue(state.isVisible, "Slot \(slot) on Display A must be restored")
            XCTAssertFalse(state.hideReasons.contains(.fullscreen))
        }
    }

    func testFullscreenTransitionPendingPreservesEdgeHideReasons() {
        var state = PanelVisibilityState()
        state.setEdgeAutoHidden(true)
        XCTAssertTrue(state.hideReasons.contains(.edgeAutoHide))
        XCTAssertFalse(state.isVisible)

        // Begin fullscreen transition
        state.beginFullscreenTransition(generation: 1)
        XCTAssertTrue(state.hideReasons.contains(.fullscreenTransitionPending))
        XCTAssertTrue(state.hideReasons.contains(.edgeAutoHide))

        // Complete fullscreen transition
        state.confirmFullscreenTransition(generation: 1)
        XCTAssertTrue(state.hideReasons.contains(.fullscreen))
        XCTAssertTrue(state.hideReasons.contains(.edgeAutoHide))
        XCTAssertFalse(state.hideReasons.contains(.fullscreenTransitionPending))

        // Exit fullscreen
        state.setFullscreen(false)
        XCTAssertFalse(state.hideReasons.contains(.fullscreen))
        XCTAssertTrue(state.hideReasons.contains(.edgeAutoHide), "Edge auto-hide reason should be preserved")
    }

    func testCapsuleOwnershipAcrossSlots() {
        // In split4 mode (decision 8b: `.tray` removed → 3 groups):
        // Slot 0: weather -> capsule: false
        // Slot 1: apps    -> capsule: true
        // Slot 2: clock   -> capsule: false
        let sections = BarSection.islands(for: .split4)
        XCTAssertEqual(sections.count, 3)

        let capsuleOwners = sections.map { $0.contains(.apps) }
        XCTAssertEqual(capsuleOwners, [false, true, false])

        // Exactly one slot owns the capsule
        XCTAssertEqual(capsuleOwners.filter { $0 }.count, 1)

        // In windows mode: slot 0 hosts all sections including apps
        let windowsSections = BarSection.islands(for: .windows)
        XCTAssertEqual(windowsSections.count, 1)
        XCTAssertTrue(windowsSections[0].contains(.apps))
    }
}
