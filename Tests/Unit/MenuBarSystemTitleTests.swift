import XCTest
@testable import KatiKati

final class MenuBarSystemTitleTests: XCTestCase {
    func testTitleShowsCPUAndMemoryPercent() {
        var snapshot = SystemSnapshot()
        snapshot.cpu = 0.124
        snapshot.memory = MemoryUsage(used: 61, total: 100)
        XCTAssertEqual(SystemMonitorFormat.menuBarTitle(snapshot), "CPU 12% · MEM 61%")
    }

    func testEmptySnapshotReadsZero() {
        XCTAssertEqual(SystemMonitorFormat.menuBarTitle(SystemSnapshot()), "CPU 0% · MEM 0%")
    }

    func testStatusMenuRoutesLeftClickToHubAndRightOrControlClickToMenu() {
        XCTAssertEqual(StatusMenuController.clickAction(eventType: .leftMouseUp, modifierFlags: []), .toggleHub)
        XCTAssertEqual(StatusMenuController.clickAction(eventType: nil, modifierFlags: []), .toggleHub)
        XCTAssertEqual(StatusMenuController.clickAction(eventType: .rightMouseDown, modifierFlags: []), .contextMenu)
        XCTAssertEqual(StatusMenuController.clickAction(eventType: .rightMouseUp, modifierFlags: []), .contextMenu)
        XCTAssertEqual(StatusMenuController.clickAction(eventType: .leftMouseUp, modifierFlags: [.control]), .contextMenu)

        let bounds = CGRect(x: 0, y: 0, width: 22, height: 22)
        XCTAssertEqual(StatusMenuController.contextMenuAnchor(buttonBounds: bounds, isFlipped: true), NSPoint(x: 0, y: 26))
        XCTAssertEqual(StatusMenuController.contextMenuAnchor(buttonBounds: bounds, isFlipped: false), NSPoint(x: 0, y: -4))
    }
}
