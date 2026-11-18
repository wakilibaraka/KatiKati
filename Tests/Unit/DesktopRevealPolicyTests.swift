import Foundation
import XCTest
@testable import KatiKati

final class DesktopRevealPolicyTests: XCTestCase {
    func testRapidQuickRevealToggleIsSerializedByCooldown() {
        var machine = DesktopRevealStateMachine(toggleCooldown: 0.18)
        XCTAssertEqual(machine.visibility, .desktopLayer)

        XCTAssertTrue(machine.toggleQuickReveal(now: 1.00))
        XCTAssertEqual(machine.visibility, .quickRevealed)

        XCTAssertFalse(machine.toggleQuickReveal(now: 1.05))
        XCTAssertEqual(machine.visibility, .quickRevealed)

        XCTAssertTrue(machine.toggleQuickReveal(now: 1.20))
        XCTAssertEqual(machine.visibility, .desktopLayer)
    }

    func testInteractionLocksDeferQuickRevealDismissUntilUnlocked() {
        var machine = DesktopRevealStateMachine()
        XCTAssertTrue(machine.toggleQuickReveal(now: 1.0))

        machine.acquireLock(.contextMenu)
        machine.acquireLock(.drag)
        XCTAssertFalse(machine.requestDismissQuickReveal(reason: .outsideClick))
        XCTAssertEqual(machine.visibility, .quickRevealed)
        XCTAssertTrue(machine.pendingDismissAfterUnlock)

        XCTAssertFalse(machine.releaseLock(.drag))
        XCTAssertEqual(machine.visibility, .quickRevealed)

        XCTAssertTrue(machine.releaseLock(.contextMenu))
        XCTAssertEqual(machine.visibility, .desktopLayer)
        XCTAssertFalse(machine.pendingDismissAfterUnlock)
    }

    func testHiddenAllCanQuickRevealAndReturnToHiddenAll() {
        var machine = DesktopRevealStateMachine()
        XCTAssertTrue(machine.toggleHiddenAll(now: 1.0))
        XCTAssertEqual(machine.visibility, .hiddenAll)

        XCTAssertTrue(machine.toggleQuickReveal(now: 2.0))
        XCTAssertEqual(machine.visibility, .quickRevealed)

        XCTAssertTrue(machine.requestDismissQuickReveal(reason: .escapeKey))
        XCTAssertEqual(machine.visibility, .hiddenAll)
    }

    func testDesktopShortcutDefaultsAreOffAndIDsUnique() {
        XCTAssertEqual(ShortcutAction.desktopQuickReveal.hotKeyID, 54)
        XCTAssertEqual(ShortcutAction.desktopToggleHidden.hotKeyID, 55)
        XCTAssertEqual(ShortcutAction.desktopQuickReveal.defaultTrigger, .off)
        XCTAssertEqual(ShortcutAction.desktopToggleHidden.defaultTrigger, .off)
        XCTAssertEqual(
            Set(ShortcutAction.allCases.map(\.hotKeyID)).count,
            ShortcutAction.allCases.count
        )
    }

    func testDesktopFeatureGateDefaultsOffAndRespectsDebugSwitch() {
        let suite = "katikati.desktop.gate.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertFalse(DesktopCanvasConfig.isFeatureEnabled(defaults: defaults, environment: [:]))
        XCTAssertTrue(DesktopCanvasConfig.isFeatureEnabled(defaults: defaults, environment: ["DOCK_DESKTOP_CANVAS": "1"]))

        defaults.set(true, forKey: DesktopCanvasConfig.enabledKey)
        XCTAssertTrue(DesktopCanvasConfig.isFeatureEnabled(defaults: defaults, environment: [:]))
    }
}
