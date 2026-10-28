import AppKit
import SwiftUI
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

    func testFirstMouseHostingViewAcceptsFirstMouse() {
        let hostingView = FirstMouseHostingView(rootView: Text("Test"))
        XCTAssertTrue(hostingView.acceptsFirstMouse(for: nil))

        let containerView = FirstMouseContainerView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertTrue(containerView.acceptsFirstMouse(for: nil))
    }

    /// Was a call against the real Dock service: on a developer Mac it could restore the Dock and drop
    /// the saved hide delay, and the shell fallback ran `killall Dock`. Now an injected service only.
    func testDockSuppressionGoesThroughTheInjectedServiceOnly() {
        let defaults = UserDefaults(suiteName: "DockWindowManagerTests_\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.description) }
        var ran: [[String]] = []
        let service = NativeDockPreferencesService(
            sandbox: SandboxEnvironment(isSandboxed: false),
            runner: { _, arguments in ran.append(arguments) },
            autohideReader: { NativeDockAutohideState(enabled: false, delay: nil) },
            defaults: defaults
        )

        // Nothing captured yet: restoring has nothing to put back and runs nothing.
        DockWindowManager.suppressNativeMacDock(suppress: false, service: service)
        XCTAssertTrue(ran.isEmpty)

        DockWindowManager.suppressNativeMacDock(suppress: true, service: service)
        XCTAssertEqual(ran.last, ["Dock"], "hiding ends in one Dock restart")

        let sandboxed = NativeDockPreferencesService(sandbox: SandboxEnvironment(isSandboxed: true),
                                                     runner: { _, arguments in ran.append(arguments) },
                                                     defaults: defaults)
        let before = ran.count
        DockWindowManager.suppressNativeMacDock(suppress: true, service: sandboxed)
        XCTAssertEqual(ran.count, before, "no shell fallback in a sandbox")
    }

    // MARK: - What each mode watches

    func testDefaultModeRunsNoSensors() {
        XCTAssertFalse(DockLayeringMode.alwaysOnTop.watchesWindowOverlap)
        XCTAssertFalse(DockLayeringMode.alwaysOnTop.watchesScreenEdge)
        XCTAssertFalse(DockLayeringMode.nativeDockVisibleFramePiggyback.watchesWindowOverlap)
        XCTAssertFalse(DockLayeringMode.nativeDockVisibleFramePiggyback.watchesScreenEdge)
        // Edge peek raises on hover but never reads the overlap.
        XCTAssertFalse(DockLayeringMode.alwaysBelowWindowsWithEdgePeek.watchesWindowOverlap)
        XCTAssertTrue(DockLayeringMode.alwaysBelowWindowsWithEdgePeek.watchesScreenEdge)
        for mode in [DockLayeringMode.dynamicSmartZOrder, .sameLevelRelativeOrder, .nativeAutoHideDodge,
                     .clickThroughGhostFallback, .reserveScreenSpaceStrut] {
            XCTAssertTrue(mode.watchesWindowOverlap, "\(mode)")
            XCTAssertTrue(mode.watchesScreenEdge, "\(mode)")
        }
    }

    // MARK: - Dock geometry against its edge

    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testNearestEdgeForBarRailsAndASlidOffDock() {
        XCTAssertEqual(DockScreenEdge.nearest(to: CGRect(x: 100, y: 8, width: 1200, height: 90), in: screen), .bottom)
        XCTAssertEqual(DockScreenEdge.nearest(to: CGRect(x: 0, y: 100, width: 90, height: 700), in: screen), .left)
        XCTAssertEqual(DockScreenEdge.nearest(to: CGRect(x: 1350, y: 100, width: 90, height: 700), in: screen), .right)
        // Slid out through the bottom: the centre is below the screen, the edge is still the bottom.
        XCTAssertEqual(DockScreenEdge.nearest(to: CGRect(x: 100, y: -98, width: 1200, height: 90), in: screen), .bottom)
        // A bar on a second display to the right of the first.
        let second = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(DockScreenEdge.nearest(to: CGRect(x: 1600, y: 0, width: 1500, height: 90), in: second), .bottom)
    }

    func testRestingZoneCoversTheFloatingGapAndSurvivesASlide() {
        let floating = CGRect(x: 100, y: 8, width: 1200, height: 90)
        XCTAssertEqual(DockScreenEdge.bottom.restingZone(of: floating, in: screen),
                       CGRect(x: 100, y: 0, width: 1200, height: 98))
        let slidOff = floating.offsetBy(dx: 0, dy: -98)
        XCTAssertEqual(DockScreenEdge.bottom.restingZone(of: slidOff, in: screen),
                       CGRect(x: 100, y: 0, width: 1200, height: 90), "the band it comes back to")
        let rail = CGRect(x: 1350, y: 100, width: 90, height: 700)
        XCTAssertEqual(DockScreenEdge.right.restingZone(of: rail, in: screen),
                       CGRect(x: 1350, y: 100, width: 90, height: 700))
        XCTAssertEqual(DockScreenEdge.left.band(in: screen, depth: 4), CGRect(x: 0, y: 0, width: 4, height: 900))
    }

    // MARK: - Re-levelling never shows a hidden panel

    func testApplyingALevelNeverOrdersInAHiddenPanel() {
        let manager = DockWindowManager()
        let dock = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 50),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let background = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 50),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        manager.managedPanelsProvider = { [dock] }
        manager.managedBackgroundPanelsProvider = { [background] }
        XCTAssertFalse(dock.isVisible)

        manager.applyDockLevel(MacDockWindowLevel.belowNormalWindows, orderAbove: false)
        manager.applyDockLevel(MacDockWindowLevel.nativeDock, orderAbove: true)
        XCTAssertEqual(dock.level, MacDockWindowLevel.nativeDock)
        XCTAssertFalse(dock.isVisible, "a panel the coordinator ordered out (fullscreen, hide) stays out")
        XCTAssertFalse(background.isVisible)
    }

    // MARK: - Piggyback mode: confirm-and-restore

    private func piggybackService(
        current: NativeDockPiggybackKeys?,
        defaults: UserDefaults,
        record: @escaping @MainActor ([String]) -> Void
    ) -> NativeDockPreferencesService {
        NativeDockPreferencesService(
            sandbox: SandboxEnvironment(isSandboxed: false),
            runner: { _, arguments in record(arguments) },
            defaults: defaults,
            piggybackReader: { current }
        )
    }

    func testPiggybackRecordsTheUsersDockAndPutsItBack() throws {
        let defaults = UserDefaults(suiteName: "DockWindowManagerTests_\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.description) }
        var ran: [[String]] = []
        let user = NativeDockPiggybackKeys(orientation: "left", autohide: true, tilesize: 64, magnification: nil)
        let service = piggybackService(current: user, defaults: defaults) { ran.append($0) }

        XCTAssertTrue(try service.applyPiggyback(height: 52))
        XCTAssertTrue(ran.contains(["write", "com.apple.dock", "orientation", "-string", "bottom"]))
        XCTAssertTrue(ran.contains(["write", "com.apple.dock", "tilesize", "-int", "44"]))
        XCTAssertEqual(ran.last, ["Dock"])

        ran.removeAll()
        XCTAssertTrue(service.restorePiggyback())
        XCTAssertTrue(ran.contains(["write", "com.apple.dock", "orientation", "-string", "left"]))
        XCTAssertTrue(ran.contains(["write", "com.apple.dock", "autohide", "-bool", "true"]))
        XCTAssertTrue(ran.contains(["delete", "com.apple.dock", "magnification"]), "an absent key goes back to absent")
        XCTAssertNil(defaults.data(forKey: NativeDockPreferencesService.piggybackOriginalKey))
        XCTAssertFalse(service.restorePiggyback(), "nothing left to restore")
    }

    func testPiggybackDoesNotRestartADockThatAlreadyMatches() throws {
        let defaults = UserDefaults(suiteName: "DockWindowManagerTests_\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.description) }
        var ran: [[String]] = []
        let matching = NativeDockPiggybackKeys(orientation: nil, autohide: nil, tilesize: 44, magnification: false)
        let service = piggybackService(current: matching, defaults: defaults) { ran.append($0) }
        XCTAssertFalse(try service.applyPiggyback(height: 52))
        XCTAssertTrue(ran.isEmpty)
    }

    func testPiggybackNeverChangesADockItCannotRead() throws {
        let defaults = UserDefaults(suiteName: "DockWindowManagerTests_\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.description) }
        var ran: [[String]] = []
        let service = piggybackService(current: nil, defaults: defaults) { ran.append($0) }
        XCTAssertFalse(try service.applyPiggyback(height: 52))
        XCTAssertTrue(ran.isEmpty)
    }

    func testLeavingPiggybackModeRestoresTheDock() {
        let defaults = UserDefaults(suiteName: "DockWindowManagerTests_\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.description) }
        var ran: [[String]] = []
        let original = NativeDockPiggybackKeys(orientation: "right", autohide: false, tilesize: 48, magnification: true)
        defaults.set(try? JSONEncoder().encode(original), forKey: NativeDockPreferencesService.piggybackOriginalKey)
        let manager = DockWindowManager()
        manager.nativeDockService = piggybackService(current: original, defaults: defaults) { ran.append($0) }

        manager.layeringMode = .nativeDockVisibleFramePiggyback
        XCTAssertTrue(ran.isEmpty, "a manager that is not running never writes the Dock")
        manager.layeringMode = .alwaysOnTop
        XCTAssertTrue(ran.contains(["write", "com.apple.dock", "orientation", "-string", "right"]))
        XCTAssertEqual(ran.last, ["Dock"])
    }

    func testPiggybackKeysDecodeLeniently() {
        let keys = NativeDockPiggybackKeys.decode(orientation: "bottom", autohide: kCFBooleanTrue,
                                                  tilesize: NSNumber(value: 47.6), magnification: NSNumber(value: 1))
        XCTAssertEqual(keys, NativeDockPiggybackKeys(orientation: "bottom", autohide: true, tilesize: 48, magnification: nil),
                       "a number is not a boolean")
    }
}
