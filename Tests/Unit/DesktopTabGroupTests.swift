import CoreGraphics
import XCTest

final class DesktopTabGroupTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    private func makeBox(_ title: String, x: CGFloat, y: CGFloat) -> DesktopWidgetItem {
        DesktopWidgetItem(
            title: title,
            backingPath: "/tmp/\(title)",
            displayUUID: "disp-1",
            frame: CGRect(x: x, y: y, width: 300, height: 260)
        )
    }

    func testMergeTwoBoxesProducesSinglePanelGroupWithSyncedFrame() {
        let a = makeBox("Inbox", x: 100, y: 200)
        let b = makeBox("Work", x: 500, y: 300)

        let merged = DesktopTabGroupEngine.merge(movingID: b.id, into: a.id, in: [a, b])
        let groups = DesktopTabGroupEngine.panelGroups(from: merged)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].tabs.map(\.id), [a.id, b.id])
        XCTAssertEqual(groups[0].activeItem.id, b.id)
        XCTAssertEqual(groups[0].tabs[0].frame, a.frame)
        XCTAssertEqual(groups[0].tabs[1].frame, a.frame)
        XCTAssertNotNil(groups[0].tabs[0].tabGroupID)
        XCTAssertEqual(groups[0].tabs[0].tabGroupID, groups[0].tabs[1].tabGroupID)
    }

    func testSelectAndCycleTabsWrapsForwardAndBackward() {
        let a = makeBox("A", x: 80, y: 80)
        let b = makeBox("B", x: 120, y: 120)
        let c = makeBox("C", x: 160, y: 160)

        var items = DesktopTabGroupEngine.merge(movingID: b.id, into: a.id, in: [a, b, c])
        items = DesktopTabGroupEngine.merge(movingID: c.id, into: a.id, in: items)

        let gid = try! XCTUnwrap(items.first(where: { $0.id == a.id })?.tabGroupID)
        XCTAssertEqual(DesktopTabGroupEngine.panelGroups(from: items)[0].activeItem.id, c.id)

        // Wrap forward: C (idx 2) -> A (idx 0)
        items = DesktopTabGroupEngine.cycleTab(groupID: gid, delta: 1, in: items)
        XCTAssertEqual(DesktopTabGroupEngine.panelGroups(from: items)[0].activeItem.id, a.id)

        // Wrap backward: A (idx 0) -> C (idx 2)
        items = DesktopTabGroupEngine.cycleTab(groupID: gid, delta: -1, in: items)
        XCTAssertEqual(DesktopTabGroupEngine.panelGroups(from: items)[0].activeItem.id, c.id)

        items = DesktopTabGroupEngine.selectTab(id: b.id, in: items)
        XCTAssertEqual(DesktopTabGroupEngine.panelGroups(from: items)[0].activeItem.id, b.id)
    }

    func testDetachTabDissolvesTwoMemberGroupAndKeepsClampedGeometry() {
        let a = makeBox("A", x: 1120, y: 20)
        let b = makeBox("B", x: 200, y: 200)
        let c = makeBox("C", x: 400, y: 200)

        var items = DesktopTabGroupEngine.merge(movingID: b.id, into: a.id, in: [a, b, c])
        items = DesktopTabGroupEngine.merge(movingID: c.id, into: a.id, in: items)

        // Detach C -> A & B remain grouped (2 panels total).
        items = DesktopTabGroupEngine.detachTab(id: c.id, in: items, visibleFrame: screen, edgeMargin: 12)
        XCTAssertEqual(DesktopTabGroupEngine.panelGroups(from: items).count, 2)
        let detachedC = items.first { $0.id == c.id }!
        XCTAssertNil(detachedC.tabGroupID)
        XCTAssertGreaterThanOrEqual(detachedC.frame.minY, 12)
        XCTAssertLessThanOrEqual(detachedC.frame.maxX, screen.maxX - 12)

        // Detach B -> A becomes standalone again (orphan dissolved).
        items = DesktopTabGroupEngine.detachTab(id: b.id, in: items, visibleFrame: screen, edgeMargin: 12)
        let standaloneA = items.first { $0.id == a.id }!
        XCTAssertNil(standaloneA.tabGroupID)
        XCTAssertTrue(standaloneA.isActiveTab)
        XCTAssertEqual(DesktopTabGroupEngine.panelGroups(from: items).count, 3)
    }

    func testReconcileFixesCorruptActiveStatesAndOneMemberOrphan() {
        let gid = UUID()
        var solo = makeBox("Solo", x: 50, y: 50)
        solo.tabGroupID = gid
        solo.tabOrder = 9
        solo.isActiveTab = false

        let otherGid = UUID()
        var m1 = makeBox("M1", x: 100, y: 100)
        var m2 = makeBox("M2", x: 300, y: 300)
        m1.tabGroupID = otherGid; m1.isActiveTab = false; m1.tabOrder = 3
        m2.tabGroupID = otherGid; m2.isActiveTab = false; m2.tabOrder = 5

        let fixed = DesktopTabGroupEngine.reconcile([solo, m1, m2])
        XCTAssertNil(fixed[0].tabGroupID)
        XCTAssertTrue(fixed[0].isActiveTab)
        XCTAssertEqual(fixed[1].tabOrder, 0)
        XCTAssertTrue(fixed[1].isActiveTab)
        XCTAssertEqual(fixed[2].tabOrder, 1)
        XCTAssertFalse(fixed[2].isActiveTab)
        XCTAssertEqual(fixed[2].frame, fixed[1].frame)
    }
}
