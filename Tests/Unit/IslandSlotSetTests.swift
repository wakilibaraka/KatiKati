import XCTest
@testable import KatiKati

final class IslandSlotSetTests: XCTestCase {
    func testSlotKeyDescription() {
        XCTAssertEqual(IslandSlotSet.SlotKey(display: nil, slot: 0).description, "follow#0")
        XCTAssertEqual(IslandSlotSet.SlotKey(display: "DISPLAY-1", slot: 2).description, "DISPLAY-1#2")
    }

    func testDiffKeepsCurrentOrderForAddedAndKept() {
        let prev = [
            IslandSlotSet.SlotKey(display: "A", slot: 0),
            IslandSlotSet.SlotKey(display: "A", slot: 1),
            IslandSlotSet.SlotKey(display: "B", slot: 0),
        ]
        let curr = [
            IslandSlotSet.SlotKey(display: "B", slot: 0),
            IslandSlotSet.SlotKey(display: "C", slot: 0),
            IslandSlotSet.SlotKey(display: "A", slot: 0),
        ]
        let diff = IslandSlotSet.diff(previous: prev, current: curr)
        XCTAssertEqual(diff.added, [IslandSlotSet.SlotKey(display: "C", slot: 0)])
        XCTAssertEqual(diff.removed, [IslandSlotSet.SlotKey(display: "A", slot: 1)])
        XCTAssertEqual(diff.kept, [
            IslandSlotSet.SlotKey(display: "B", slot: 0),
            IslandSlotSet.SlotKey(display: "A", slot: 0),
        ])
    }

    func testDiffEmptyToSomething() {
        let slot = IslandSlotSet.SlotKey(display: nil, slot: 0)
        let diff = IslandSlotSet.diff(previous: [], current: [slot])
        XCTAssertEqual(diff, IslandSlotSet.Diff(added: [slot], removed: [], kept: []))
    }

    func testDesiredSlotsSingleDisplayModes() {
        let connected = ["A", "B"]
        // In followMouse mode, display is nil (single unit placement)
        let windows = IslandSlotSet.desiredSlots(placement: .followMouse, connectedKeys: connected, mode: .windows)
        XCTAssertEqual(windows, [IslandSlotSet.SlotKey(display: nil, slot: 0)])

        let centered = IslandSlotSet.desiredSlots(placement: .followMouse, connectedKeys: connected, mode: .centered)
        XCTAssertEqual(centered, [IslandSlotSet.SlotKey(display: nil, slot: 0)])

        let split3 = IslandSlotSet.desiredSlots(placement: .followMouse, connectedKeys: connected, mode: .split3)
        XCTAssertEqual(split3, [
            IslandSlotSet.SlotKey(display: nil, slot: 0),
            IslandSlotSet.SlotKey(display: nil, slot: 1),
            IslandSlotSet.SlotKey(display: nil, slot: 2),
        ])

        let split4 = IslandSlotSet.desiredSlots(placement: .followMouse, connectedKeys: connected, mode: .split4)
        XCTAssertEqual(split4, [
            IslandSlotSet.SlotKey(display: nil, slot: 0),
            IslandSlotSet.SlotKey(display: nil, slot: 1),
            IslandSlotSet.SlotKey(display: nil, slot: 2),
            IslandSlotSet.SlotKey(display: nil, slot: 3),
        ])
    }

    func testDesiredSlotsPinnedDisplay() {
        let pinned = TaskbarScreenPlacement.pinned(PinnedScreenSelection(uuid: "B", name: "LG"))
        let slots = IslandSlotSet.desiredSlots(placement: pinned, connectedKeys: ["A", "B"], mode: .split3)
        XCTAssertEqual(slots, [
            IslandSlotSet.SlotKey(display: nil, slot: 0),
            IslandSlotSet.SlotKey(display: nil, slot: 1),
            IslandSlotSet.SlotKey(display: nil, slot: 2),
        ])
    }

    func testDesiredSlotsAllScreensExpandsEachDisplay() {
        let slots = IslandSlotSet.desiredSlots(placement: .allScreens, connectedKeys: ["A", "B"], mode: .split3)
        XCTAssertEqual(slots, [
            IslandSlotSet.SlotKey(display: "A", slot: 0),
            IslandSlotSet.SlotKey(display: "A", slot: 1),
            IslandSlotSet.SlotKey(display: "A", slot: 2),
            IslandSlotSet.SlotKey(display: "B", slot: 0),
            IslandSlotSet.SlotKey(display: "B", slot: 1),
            IslandSlotSet.SlotKey(display: "B", slot: 2),
        ])
    }

    func testDesiredSlotsEmptyConnectedKeysFallsBackToDefaultDisplay() {
        let slots = IslandSlotSet.desiredSlots(placement: .allScreens, connectedKeys: [], mode: .split3)
        XCTAssertEqual(slots, [
            IslandSlotSet.SlotKey(display: nil, slot: 0),
            IslandSlotSet.SlotKey(display: nil, slot: 1),
            IslandSlotSet.SlotKey(display: nil, slot: 2),
        ])
    }

    func testSurvivorReuseOnModeTransition() {
        let windows = IslandSlotSet.desiredSlots(placement: .followMouse, connectedKeys: ["A"], mode: .windows)
        let split3 = IslandSlotSet.desiredSlots(placement: .followMouse, connectedKeys: ["A"], mode: .split3)
        let split4 = IslandSlotSet.desiredSlots(placement: .followMouse, connectedKeys: ["A"], mode: .split4)

        // windows -> split3: slot 0 kept, slots 1 & 2 added
        let diffExpand = IslandSlotSet.diff(previous: windows, current: split3)
        XCTAssertEqual(diffExpand.kept, [IslandSlotSet.SlotKey(display: nil, slot: 0)])
        XCTAssertEqual(diffExpand.added, [
            IslandSlotSet.SlotKey(display: nil, slot: 1),
            IslandSlotSet.SlotKey(display: nil, slot: 2),
        ])
        XCTAssertEqual(diffExpand.removed, [])

        // split3 -> split4: slots 0, 1, 2 kept, slot 3 added
        let diffSplit4 = IslandSlotSet.diff(previous: split3, current: split4)
        XCTAssertEqual(diffSplit4.kept, [
            IslandSlotSet.SlotKey(display: nil, slot: 0),
            IslandSlotSet.SlotKey(display: nil, slot: 1),
            IslandSlotSet.SlotKey(display: nil, slot: 2),
        ])
        XCTAssertEqual(diffSplit4.added, [IslandSlotSet.SlotKey(display: nil, slot: 3)])
        XCTAssertEqual(diffSplit4.removed, [])

        // split4 -> windows: slot 0 kept, slots 1, 2, 3 removed
        let diffCollapse = IslandSlotSet.diff(previous: split4, current: windows)
        XCTAssertEqual(diffCollapse.kept, [IslandSlotSet.SlotKey(display: nil, slot: 0)])
        XCTAssertEqual(diffCollapse.added, [])
        XCTAssertEqual(diffCollapse.removed, [
            IslandSlotSet.SlotKey(display: nil, slot: 1),
            IslandSlotSet.SlotKey(display: nil, slot: 2),
            IslandSlotSet.SlotKey(display: nil, slot: 3),
        ])
    }
}
