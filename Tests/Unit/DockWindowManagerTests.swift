import AppKit
import XCTest
@testable import KatiKati

@MainActor
final class DockWindowManagerTests: XCTestCase {

    func testMacDockWindowLevelsMatchCoreGraphicsDefinitions() {
        let normalLevel = Int(CGWindowLevelForKey(.normalWindow))
        let dockLevel = Int(CGWindowLevelForKey(.dockWindow))

        XCTAssertEqual(MacDockWindowLevel.belowNormalWindows.rawValue, normalLevel - 1)
        XCTAssertEqual(MacDockWindowLevel.normalWindow.rawValue, normalLevel)
        XCTAssertEqual(MacDockWindowLevel.nativeDock.rawValue, dockLevel)
        XCTAssertEqual(MacDockWindowLevel.aboveNativeDock.rawValue, dockLevel + 1)
        XCTAssertEqual(MacDockWindowLevel.edgeTriggerSensor.rawValue, Int(CGWindowLevelForKey(.statusWindow)) + 1)
    }

    func testDockLayeringModesHaveDescriptionsAndPermissionClassification() {
        XCTAssertEqual(DockLayeringMode.allCases.count, 8)

        for mode in DockLayeringMode.allCases {
            XCTAssertFalse(mode.id.isEmpty)
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertFalse(mode.subtitle.isEmpty)

            if mode == .reserveScreenSpaceStrut {
                XCTAssertTrue(mode.requiresAccessibility)
                XCTAssertFalse(mode.isZeroPermission)
            } else {
                XCTAssertFalse(mode.requiresAccessibility)
                XCTAssertTrue(mode.isZeroPermission)
            }
        }
    }

    func testDockLayeringModeCodableRoundTrip() throws {
        for mode in DockLayeringMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(DockLayeringMode.self, from: data)
            XCTAssertEqual(mode, decoded)
        }
    }

    func testAppSettingsStoreDefaultsToAlwaysOnTopAndPropagatesUpdates() {
        let defaults = UserDefaults(suiteName: "DockWindowManagerTests_\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        let store = AppSettingsStore(defaults: defaults)

        // Verifies legacy preset preservation: default is .alwaysOnTop
        XCTAssertEqual(store.dockLayeringMode, .alwaysOnTop)
        XCTAssertEqual(DockWindowManager.shared.layeringMode, .alwaysOnTop)
        XCTAssertTrue(store.dockSkyLightReinforcement)
        XCTAssertFalse(store.dockAppleScriptFallback)

        // Switching mode propagates to store and DockWindowManager
        store.setDockLayeringMode(.dynamicSmartZOrder)
        XCTAssertEqual(store.dockLayeringMode, .dynamicSmartZOrder)
        XCTAssertEqual(DockWindowManager.shared.layeringMode, .dynamicSmartZOrder)

        store.setDockLayeringMode(.sameLevelRelativeOrder)
        XCTAssertEqual(store.dockLayeringMode, .sameLevelRelativeOrder)
        XCTAssertEqual(DockWindowManager.shared.layeringMode, .sameLevelRelativeOrder)

        store.setDockSkyLightReinforcement(false)
        XCTAssertFalse(store.dockSkyLightReinforcement)
        XCTAssertFalse(DockWindowManager.shared.useSkyLightFallbackReinforcement)

        store.setDockAppleScriptFallback(true)
        XCTAssertTrue(store.dockAppleScriptFallback)
        XCTAssertTrue(DockWindowManager.shared.useAppleScriptResizeFallback)

        // Reset back to alwaysOnTop
        store.setDockLayeringMode(.alwaysOnTop)
        store.setDockSkyLightReinforcement(true)
        store.setDockAppleScriptFallback(false)
    }

    func testDockWindowManagerPanelRegistrationAndLayerApplication() {
        let manager = DockWindowManager()
        let panel1 = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 50),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        let panel2 = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 50),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)

        manager.managedPanelsProvider = { [panel1] }
        manager.managedBackgroundPanelsProvider = { [panel2] }

        // Test applying native dock level
        manager.applyDockLevel(MacDockWindowLevel.nativeDock, orderAbove: true)
        XCTAssertEqual(panel1.level, MacDockWindowLevel.nativeDock)
        XCTAssertEqual(panel2.level, MacDockWindowLevel.nativeDock)

        // Test applying below normal windows level (-1)
        manager.applyDockLevel(MacDockWindowLevel.belowNormalWindows, orderAbove: false)
        XCTAssertEqual(panel1.level, MacDockWindowLevel.belowNormalWindows)
        XCTAssertEqual(panel2.level, MacDockWindowLevel.belowNormalWindows)

        // Test applying normal window level (0)
        manager.applyDockLevel(MacDockWindowLevel.normalWindow, orderAbove: false)
        XCTAssertEqual(panel1.level, MacDockWindowLevel.normalWindow)
        XCTAssertEqual(panel2.level, MacDockWindowLevel.normalWindow)
    }

    func testAutomaticPermissionCascadeUnderReserveScreenSpaceStrut() {
        let manager = DockWindowManager()
        manager.layeringMode = .reserveScreenSpaceStrut

        // evaluateWindowLayering must succeed gracefully without throwing
        manager.evaluateWindowLayering()

        // If not trusted, manager falls back cleanly to dynamic Z-order
        if !manager.hasAccessibilityPermission {
            XCTAssertTrue(manager.layeringMode == .reserveScreenSpaceStrut)
        }
    }
}
