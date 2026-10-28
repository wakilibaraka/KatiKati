//
//  DockWindowManager.swift
//  KatiKati
//
//  Complete window-layering, screen-edge reveal, AXUIElement strut clamping,
//  and multi-tier hybrid fallback engine (Zero-Permission + With-Permission) for KatiKati.
//

import AppKit
import ApplicationServices
import Combine
import Foundation
import SwiftUI

// MARK: - 0. Private SkyLight / CoreGraphics Fallback Declarations (@_silgen_name)

/// Private WindowServer symbols located in SkyLight.framework / ApplicationServices.
/// Used by SketchyBar, AltTab, and yabai as a direct WindowServer fallback when AppKit
/// caches or restricts `NSWindow.level` transitions.
public typealias CGSConnectionID = UInt32
public typealias CGSWindowOrderingMode = Int32
public let kCGSOrderAbove: CGSWindowOrderingMode = 1
public let kCGSOrderBelow: CGSWindowOrderingMode = -1
public let kCGSOrderOut: CGSWindowOrderingMode = 0

@_silgen_name("CGSMainConnectionID")
public func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSSetWindowLevel")
@discardableResult
public func CGSSetWindowLevel(
    _ cid: CGSConnectionID,
    _ wid: CGWindowID,
    _ level: Int32
) -> CGError

@_silgen_name("CGSOrderWindow")
@discardableResult
public func CGSOrderWindow(
    _ cid: CGSConnectionID,
    _ wid: CGWindowID,
    _ mode: CGSWindowOrderingMode,
    _ relativeToWID: CGWindowID
) -> CGError

// MARK: - 1. Dock Window & Hybrid Fallback Coordinator

@MainActor
public final class DockWindowManager: ObservableObject {

    public static let shared = DockWindowManager()

    // MARK: Published State
    @Published public var layeringMode: DockLayeringMode = .alwaysOnTop {
        didSet {
            guard oldValue != layeringMode else { return }
            handleModeTransition(from: oldValue)
            evaluateWindowLayering()
        }
    }
    @Published public private(set) var isElevatedByHover: Bool = false
    @Published public private(set) var isOverlappedByWindow: Bool = false
    @Published public private(set) var isHiddenOffscreen: Bool = false
    @Published public private(set) var hasAccessibilityPermission: Bool = AXIsProcessTrusted()

    // MARK: Configuration Flags
    /// Enables private SkyLight (`CGSSetWindowLevel` / `CGSOrderWindow`) reinforcement alongside AppKit.
    public var useSkyLightFallbackReinforcement: Bool = true
    /// Enables AppleScript (`System Events`) window-resize fallback when `AXUIElement` fails.
    public var useAppleScriptResizeFallback: Bool = false

    // MARK: Panels & Geometry
    public var dockHeight: CGFloat = 52.0
    public var edgeTriggerHeight: CGFloat = 2.0
    public var edgeDwellDelay: TimeInterval = 0.14

    /// Surface registration for orchestrators managing multiple displays.
    public var managedPanelsProvider: (() -> [NSPanel])?
    public var managedBackgroundPanelsProvider: (() -> [NSPanel])?
    public var managedCapsulePanelsProvider: (() -> [NSPanel])?
    public var onSlideStateChanged: ((Bool) -> Void)?

    /// Writes and restores the native Dock settings the piggyback mode needs. Only the app's shared
    /// instance gets one (`TaskbarScreenOrchestrator`); a manager without it never touches the Dock,
    /// which is what keeps tests and previews off the user's real Dock.
    var nativeDockService: NativeDockPreferencesService?

    // MARK: Stability & Concurrency Primitives
    private let axQueue = DispatchQueue(label: "com.katikati.ax.serial", qos: .userInteractive)
    private var axObservers: [pid_t: AXObserver] = [:]
    private var workspaceCancellables = Set<AnyCancellable>()
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var mousePollingFallbackTimer: Timer?
    private var edgeHoverTimer: Timer?
    private var overlapPollTimer: Timer?
    private var screenReconfigDebounceWorkItem: DispatchWorkItem?
    private var isStarted = false
    /// Panels the ghost mode made click-through and faint, with what they had before, so leaving the
    /// ghost puts back exactly that instead of forcing every surface interactive and opaque.
    private var ghostedPanels: [ObjectIdentifier: (panel: NSPanel, ignoresMouseEvents: Bool, alpha: CGFloat)] = [:]

    public init() {
        self.hasAccessibilityPermission = AXIsProcessTrusted()
    }

    // MARK: - Lifecycle

    public func start() {
        self.hasAccessibilityPermission = AXIsProcessTrusted()
        isStarted = true
        registerSystemNotifications()
        reconcileSensors()
        if layeringMode == .nativeDockVisibleFramePiggyback {
            // Idempotent: writes (and restarts the Dock) only if the Dock drifted from the mode's values.
            _ = try? nativeDockService?.applyPiggyback(height: Int(dockHeight))
        }
        evaluateWindowLayering()
    }

    public func stop() {
        isStarted = false
        workspaceCancellables.removeAll()
        stopEdgeSensor()
        stopOverlapWatch()
        screenReconfigDebounceWorkItem?.cancel()
        screenReconfigDebounceWorkItem = nil
        restoreGhostedPanels()
    }

    private func handleModeTransition(from oldMode: DockLayeringMode) {
        if oldMode == .clickThroughGhostFallback { restoreGhostedPanels() }
        if oldMode == .nativeAutoHideDodge { setDockSlideHidden(false) }
        if oldMode == .nativeDockVisibleFramePiggyback {
            nativeDockService?.restorePiggyback()
        }
        if layeringMode == .nativeDockVisibleFramePiggyback, isStarted {
            _ = try? nativeDockService?.applyPiggyback(height: Int(dockHeight))
        }
        if isElevatedByHover, !layeringMode.watchesScreenEdge { isElevatedByHover = false }
        if isStarted { reconcileSensors() }
    }

    /// Runs only the sensors the current mode reads. In the default `.alwaysOnTop` that is none: the
    /// dock then costs nothing between real events (app activation, Space change, display change).
    private func reconcileSensors() {
        if layeringMode.watchesScreenEdge { startEdgeSensor() } else { stopEdgeSensor() }
        if layeringMode.watchesWindowOverlap { startOverlapWatch() } else { stopOverlapWatch() }
    }

    // MARK: - Core Z-Order, Relative Ordering & Fallback Cascade

    public func evaluateWindowLayering() {
        hasAccessibilityPermission = AXIsProcessTrusted()

        let dockPanels = managedPanelsProvider?() ?? []
        let capsulePanels = managedCapsulePanelsProvider?() ?? []

        var isAnyOverlapping = false
        var topOverlappingWID: CGWindowID?
        var primaryClampingDockFrame: NSRect?
        var primaryClampingScreen: NSScreen?

        // Modes that never read the overlap skip the window-list copy entirely.
        if layeringMode.watchesWindowOverlap {
            for (zone, screen) in dockRestingZones() {
                let result = findOverlappingStandardWindow(dockFrame: zone, on: screen)
                if result.isOverlapping {
                    isAnyOverlapping = true
                    if topOverlappingWID == nil {
                        topOverlappingWID = result.topOverlappingWindowID
                        primaryClampingDockFrame = zone
                        primaryClampingScreen = screen
                    }
                }
            }
        }

        self.isOverlappedByWindow = isAnyOverlapping

        switch layeringMode {
        case .alwaysOnTop:
            setDockSlideHidden(false)
            applyDockLevel(MacDockWindowLevel.nativeDock, orderAbove: true)

        case .alwaysBelowWindowsWithEdgePeek:
            setDockSlideHidden(false)
            if isElevatedByHover {
                applyDockLevel(MacDockWindowLevel.nativeDock, orderAbove: true)
            } else {
                applyDockLevel(MacDockWindowLevel.belowNormalWindows, orderAbove: false)
            }

        case .dynamicSmartZOrder:
            setDockSlideHidden(false)
            if isElevatedByHover {
                applyDockLevel(MacDockWindowLevel.nativeDock, orderAbove: true)
            } else if isAnyOverlapping {
                applyDockLevel(MacDockWindowLevel.belowNormalWindows, orderAbove: false)
            } else {
                applyDockLevel(MacDockWindowLevel.nativeDock, orderAbove: true)
            }

        case .sameLevelRelativeOrder:
            setDockSlideHidden(false)
            if isElevatedByHover {
                applyDockLevel(MacDockWindowLevel.nativeDock, orderAbove: true)
            } else if isAnyOverlapping, let coveringWID = topOverlappingWID {
                applySameLevelOrderBelow(coveringWID: coveringWID)
            } else if isAnyOverlapping {
                applyDockLevel(MacDockWindowLevel.normalWindow, orderAbove: false)
            } else {
                applyDockLevel(MacDockWindowLevel.nativeDock, orderAbove: true)
            }

        case .clickThroughGhostFallback:
            setDockSlideHidden(false)
            if isElevatedByHover || !isAnyOverlapping {
                restoreGhostedPanels()
                applyDockLevel(MacDockWindowLevel.nativeDock, orderAbove: true)
            } else {
                ghost(dockPanels + capsulePanels)
                applyDockLevel(MacDockWindowLevel.belowNormalWindows, orderAbove: false)
            }

        case .nativeDockVisibleFramePiggyback:
            setDockSlideHidden(false)
            applyDockLevel(MacDockWindowLevel.aboveNativeDock, orderAbove: true)

        case .nativeAutoHideDodge:
            applyDockLevel(MacDockWindowLevel.nativeDock, orderAbove: true)
            if isElevatedByHover {
                setDockSlideHidden(false)
            } else {
                setDockSlideHidden(isAnyOverlapping)
            }

        case .reserveScreenSpaceStrut:
            setDockSlideHidden(false)
            if hasAccessibilityPermission || useAppleScriptResizeFallback {
                applyDockLevel(MacDockWindowLevel.nativeDock, orderAbove: true)
                // Clamping shortens a window's height, so it only means something for a bottom bar.
                if let clampingFrame = primaryClampingDockFrame, let clampingScreen = primaryClampingScreen,
                   DockScreenEdge.nearest(to: clampingFrame, in: clampingScreen.frame) == .bottom {
                    if hasAccessibilityPermission {
                        clampFrontmostWindowAboveDock(dockFrame: clampingFrame, on: clampingScreen)
                    } else {
                        clampFrontmostWindowViaAppleScriptFallback(dockFrame: clampingFrame, on: clampingScreen)
                    }
                }
            } else if isElevatedByHover || !isAnyOverlapping {
                // Automatic Zero-Permission Fallback Cascade
                applyDockLevel(MacDockWindowLevel.nativeDock, orderAbove: true)
            } else {
                applyDockLevel(MacDockWindowLevel.belowNormalWindows, orderAbove: false)
            }
        }
    }

    /// Sets the AppKit `NSWindow.Level` and optionally reinforces it via private SkyLight `CGSSetWindowLevel`
    /// so WindowServer immediately updates compositing order without waiting for an AppKit flush.
    ///
    /// Runs on every poll tick and workspace event, so it only acts on a change: a level already in
    /// place is left alone, and nothing is ever ordered in. `orderFrontRegardless()` / `order(_:relativeTo:)`
    /// on a panel that `PanelCoordinator` ordered out (fullscreen, hide, Space switch) puts it back on
    /// screen, which is how the dock used to reappear over fullscreen apps within 0.35 s.
    public func applyDockLevel(_ level: NSWindow.Level, orderAbove: Bool) {
        let dockPanels = managedPanelsProvider?() ?? []
        let bgPanels = managedBackgroundPanelsProvider?() ?? []
        let capsulePanels = managedCapsulePanelsProvider?() ?? []

        let cid = useSkyLightFallbackReinforcement ? CGSMainConnectionID() : 0
        var changed = false

        for panel in bgPanels + dockPanels + capsulePanels where panel.level != level {
            panel.level = level
            changed = true
            if useSkyLightFallbackReinforcement, panel.windowNumber > 0 {
                CGSSetWindowLevel(cid, CGWindowID(panel.windowNumber), Int32(level.rawValue))
            }
        }
        guard changed else { return }

        if orderAbove {
            for panel in dockPanels where panel.isVisible {
                panel.orderFrontRegardless()
            }
        }

        // Maintain relative sub-ordering between glass background and content
        for (bg, dock) in zip(bgPanels, dockPanels) where bg.isVisible && dock.isVisible {
            bg.order(.below, relativeTo: dock.windowNumber)
        }
        for (capsule, dock) in zip(capsulePanels, dockPanels) where capsule.isVisible && dock.isVisible {
            capsule.order(.above, relativeTo: dock.windowNumber)
        }
    }

    /// Visible panels only, for the same reason as `applyDockLevel`: ordering a hidden panel shows it.
    private func applySameLevelOrderBelow(coveringWID: CGWindowID) {
        let dockPanels = managedPanelsProvider?() ?? []
        let bgPanels = managedBackgroundPanelsProvider?() ?? []
        let cid = useSkyLightFallbackReinforcement ? CGSMainConnectionID() : 0

        for panel in dockPanels + bgPanels where panel.isVisible {
            panel.level = MacDockWindowLevel.normalWindow
            panel.order(.below, relativeTo: Int(coveringWID))
            if useSkyLightFallbackReinforcement, panel.windowNumber > 0 {
                let wid = CGWindowID(panel.windowNumber)
                CGSSetWindowLevel(cid, wid, Int32(MacDockWindowLevel.normalWindow.rawValue))
                CGSOrderWindow(cid, wid, kCGSOrderBelow, coveringWID)
            }
        }
    }

    // MARK: - Ghost bookkeeping

    /// Makes `panels` click-through and faint, remembering each one's own state the first time.
    private func ghost(_ panels: [NSPanel]) {
        for panel in panels {
            let id = ObjectIdentifier(panel)
            if ghostedPanels[id] == nil {
                ghostedPanels[id] = (panel: panel, ignoresMouseEvents: panel.ignoresMouseEvents, alpha: panel.alphaValue)
            }
            panel.ignoresMouseEvents = true
            panel.alphaValue = 0.08
        }
    }

    /// Puts back what `ghost(_:)` changed, and touches nothing it did not change.
    private func restoreGhostedPanels() {
        for (_, saved) in ghostedPanels {
            saved.panel.ignoresMouseEvents = saved.ignoresMouseEvents
            saved.panel.alphaValue = saved.alpha
        }
        ghostedPanels.removeAll()
    }

    // MARK: - Dock geometry

    /// Each visible dock panel's resting zone on its own screen: the band its edge would hold it in,
    /// from the panel's real frame (bar or rail, any height, any display).
    private func dockRestingZones() -> [(zone: NSRect, screen: NSScreen)] {
        (managedPanelsProvider?() ?? []).compactMap { panel in
            guard panel.isVisible, let screen = self.screen(for: panel) else { return nil }
            let edge = DockScreenEdge.nearest(to: panel.frame, in: screen.frame)
            return (edge.restingZone(of: panel.frame, in: screen.frame), screen)
        }
    }

    /// `panel.screen` is nil while a dodge slide has the panel off-screen; fall back to the screen
    /// whose edge it slid through.
    private func screen(for panel: NSPanel) -> NSScreen? {
        if let screen = panel.screen { return screen }
        let probe = panel.frame.insetBy(dx: -panel.frame.width, dy: -panel.frame.height)
        return NSScreen.screens.first { $0.frame.intersects(probe) } ?? NSScreen.main
    }

    // MARK: - Zero-Permission Window Overlap Inspection (`CGWindowListCopyWindowInfo`)

    public struct OverlapCheckResult {
        public let isOverlapping: Bool
        public let topOverlappingWindowID: CGWindowID?
    }

    /// Inspects on-screen window bounds and layers using `CGWindowListCopyWindowInfo`.
    /// Reading `kCGWindowBounds`, `kCGWindowLayer`, and `kCGWindowNumber` requires ZERO TCC permissions!
    public func findOverlappingStandardWindow(dockFrame: NSRect, on screen: NSScreen) -> OverlapCheckResult {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return OverlapCheckResult(isOverlapping: false, topOverlappingWindowID: nil)
        }

        let myPID = ProcessInfo.processInfo.processIdentifier
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let cgDockY = primaryScreenHeight - (dockFrame.origin.y + dockFrame.height)
        let cgDockRect = CGRect(
            x: dockFrame.origin.x,
            y: cgDockY,
            width: dockFrame.width,
            height: dockFrame.height
        )

        for info in windowInfoList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != myPID,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let alpha = info[kCGWindowAlpha as String] as? Double,
                  alpha > 0.01,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let w = boundsDict["Width"],
                  let h = boundsDict["Height"],
                  w > 80, h > 80
            else {
                continue
            }

            if let ownerName = info[kCGWindowOwnerName as String] as? String, ownerName == "Dock" {
                continue
            }

            let windowRect = CGRect(x: x, y: y, width: w, height: h)
            if windowRect.intersects(cgDockRect) {
                let wid = info[kCGWindowNumber as String] as? CGWindowID
                return OverlapCheckResult(isOverlapping: true, topOverlappingWindowID: wid)
            }
        }
        return OverlapCheckResult(isOverlapping: false, topOverlappingWindowID: nil)
    }

    private func setDockSlideHidden(_ hidden: Bool) {
        guard isHiddenOffscreen != hidden else { return }
        isHiddenOffscreen = hidden
        onSlideStateChanged?(hidden)
    }

    // MARK: - Screen-Edge Sensor

    /// One mouse source: the global + local mouse-moved monitors, which need no permission. The old
    /// engine also ran a 20 Hz timer and a fifth HID event tap that both called the same handler on
    /// top of the monitors, so the pointer was read up to three times per move and 20 times a second
    /// at rest. The timer survives only as the fallback for a monitor that could not be installed.
    private func startEdgeSensor() {
        guard globalMouseMonitor == nil, mousePollingFallbackTimer == nil else { return }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in self?.handleMouseMoved() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            Task { @MainActor in self?.handleMouseMoved() }
            return event
        }
        if globalMouseMonitor == nil {
            mousePollingFallbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.handleMouseMoved() }
            }
        }
    }

    private func stopEdgeSensor() {
        if let g = globalMouseMonitor { NSEvent.removeMonitor(g); globalMouseMonitor = nil }
        if let l = localMouseMonitor { NSEvent.removeMonitor(l); localMouseMonitor = nil }
        mousePollingFallbackTimer?.invalidate()
        mousePollingFallbackTimer = nil
        edgeHoverTimer?.invalidate()
        edgeHoverTimer = nil
    }

    public func handleMouseMoved() {
        let mouseLoc = NSEvent.mouseLocation

        // The edge each dock panel hugs, on its own screen: a left rail peeks from the left edge, a
        // bar on the second display from that display's bottom.
        let docks: [(edge: DockScreenEdge, screen: NSRect, depth: CGFloat)] =
            (managedPanelsProvider?() ?? []).compactMap { panel in
                guard panel.isVisible, let screen = self.screen(for: panel) else { return nil }
                let edge = DockScreenEdge.nearest(to: panel.frame, in: screen.frame)
                return (edge, screen.frame, edge.depth(of: panel.frame, in: screen.frame))
            }
        let inTriggerZone = docks.contains {
            $0.edge.band(in: $0.screen, depth: edgeTriggerHeight + 2.0).contains(mouseLoc)
        }
        let inFullDockZone = docks.contains {
            $0.edge.band(in: $0.screen, depth: $0.depth + 8.0).contains(mouseLoc)
        }

        if isElevatedByHover {
            if !inFullDockZone {
                edgeHoverTimer?.invalidate()
                edgeHoverTimer = nil
                isElevatedByHover = false
                evaluateWindowLayering()
            }
        } else {
            if inTriggerZone {
                if edgeHoverTimer == nil {
                    edgeHoverTimer = Timer.scheduledTimer(withTimeInterval: edgeDwellDelay, repeats: false) { [weak self] _ in
                        Task { @MainActor in
                            guard let self = self else { return }
                            self.isElevatedByHover = true
                            self.evaluateWindowLayering()
                        }
                    }
                }
            } else {
                edgeHoverTimer?.invalidate()
                edgeHoverTimer = nil
            }
        }
    }

    // MARK: - With-Permission Strut Clamping (AXUIElement + AppleScript Fallback)

    private func clampFrontmostWindowAboveDock(dockFrame: NSRect, on screen: NSScreen) {
        guard AXIsProcessTrusted(),
              let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return
        }

        let pid = frontApp.processIdentifier
        let appName = frontApp.localizedName ?? ""
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let maxAllowedBottomCGY = primaryScreenHeight - (dockFrame.origin.y + dockFrame.height)
        let allowAppleScriptFallback = self.useAppleScriptResizeFallback

        axQueue.async { [weak self] in
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, 0.25)

            var focusedWindowRef: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowRef)
            guard err == .success, let windowElement = focusedWindowRef as! AXUIElement? else { return }
            AXUIElementSetMessagingTimeout(windowElement, 0.25)

            var posRef: CFTypeRef?
            var sizeRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &posRef) == .success,
                  AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeRef) == .success,
                  let posVal = posRef,
                  let sizeVal = sizeRef else { return }

            var position = CGPoint.zero
            var size = CGSize.zero
            AXValueGetValue(posVal as! AXValue, .cgPoint, &position)
            AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)

            let currentBottomY = position.y + size.height
            if currentBottomY > maxAllowedBottomCGY {
                let overflow = currentBottomY - maxAllowedBottomCGY
                let newHeight = max(200.0, size.height - overflow)
                var newSize = CGSize(width: size.width, height: newHeight)
                if let newSizeAX = AXValueCreate(.cgSize, &newSize) {
                    let setErr = AXUIElementSetAttributeValue(windowElement, kAXSizeAttribute as CFString, newSizeAX)
                    if setErr != .success, allowAppleScriptFallback, !appName.isEmpty {
                        self?.executeAppleScriptSizeFallback(
                            appName: appName,
                            width: Int(size.width),
                            height: Int(newHeight)
                        )
                    }
                }
            }
        }
    }

    private func clampFrontmostWindowViaAppleScriptFallback(dockFrame: NSRect, on screen: NSScreen) {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let appName = frontApp.localizedName,
              frontApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }

        let primaryScreenHeight = Int(NSScreen.screens.first?.frame.height ?? screen.frame.height)
        let maxAllowedBottomY = primaryScreenHeight - Int(dockFrame.origin.y + dockFrame.height)

        axQueue.async {
            let scriptSource = """
            tell application "System Events"
                tell process "\(appName)"
                    if (count of windows) > 0 then
                        set winPos to position of front window
                        set winSize to size of front window
                        set winY to item 2 of winPos
                        set winW to item 1 of winSize
                        set winH to item 2 of winSize
                        if (winY + winH) > \(maxAllowedBottomY) then
                            set newH to \(maxAllowedBottomY) - winY
                            if newH > 200 then
                                set size of front window to {winW, newH}
                            end if
                        end if
                    end if
                end tell
            end tell
            """
            if let script = NSAppleScript(source: scriptSource) {
                var errorDict: NSDictionary?
                script.executeAndReturnError(&errorDict)
            }
        }
    }

    private nonisolated func executeAppleScriptSizeFallback(appName: String, width: Int, height: Int) {
        let scriptSource = """
        tell application "System Events"
            tell process "\(appName)"
                if (count of windows) > 0 then
                    set size of front window to {\(width), \(height)}
                end if
            end tell
        end tell
        """
        if let script = NSAppleScript(source: scriptSource) {
            var errorDict: NSDictionary?
            script.executeAndReturnError(&errorDict)
        }
    }

    // MARK: - Stability & Multi-Monitor Lifecycle

    private func registerSystemNotifications() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        let appCenter = NotificationCenter.default

        wsCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] notification in
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    self?.attachAXObserver(for: app.processIdentifier)
                }
                self?.evaluateWindowLayering()
            }
            .store(in: &workspaceCancellables)

        wsCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .sink { [weak self] notification in
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    self?.attachAXObserver(for: app.processIdentifier)
                }
                self?.evaluateWindowLayering()
            }
            .store(in: &workspaceCancellables)

        wsCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .sink { [weak self] notification in
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    self?.removeAXObserver(for: app.processIdentifier)
                }
                self?.evaluateWindowLayering()
            }
            .store(in: &workspaceCancellables)

        wsCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in
                self?.evaluateWindowLayering()
            }
            .store(in: &workspaceCancellables)

        wsCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                self?.evaluateWindowLayering()
            }
            .store(in: &workspaceCancellables)

        appCenter.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.debouncedScreenReconfiguration()
            }
            .store(in: &workspaceCancellables)
    }

    /// The 0.35 s window-list poll plus the per-app AX observers, for the modes that react to a
    /// covering window (`DockLayeringMode.watchesWindowOverlap`).
    private func startOverlapWatch() {
        setupAccessibilityObserversForRunningApps()
        guard overlapPollTimer == nil else { return }
        overlapPollTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateWindowLayering()
            }
        }
    }

    private func stopOverlapWatch() {
        overlapPollTimer?.invalidate()
        overlapPollTimer = nil
        for pid in Array(axObservers.keys) {
            removeAXObserver(for: pid)
        }
    }

    private func debouncedScreenReconfiguration() {
        screenReconfigDebounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.evaluateWindowLayering()
            }
        }
        screenReconfigDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func setupAccessibilityObserversForRunningApps() {
        guard AXIsProcessTrusted() else { return }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            attachAXObserver(for: app.processIdentifier)
        }
    }

    private func attachAXObserver(for pid: pid_t) {
        guard layeringMode.watchesWindowOverlap, AXIsProcessTrusted(),
              pid != ProcessInfo.processInfo.processIdentifier,
              axObservers[pid] == nil else { return }

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon = refcon else { return }
            let manager = Unmanaged<DockWindowManager>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in
                manager.evaluateWindowLayering()
            }
        }

        guard AXObserverCreate(pid, callback, &observer) == .success,
              let axObserver = observer else { return }

        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let notifications = [
            kAXWindowMovedNotification,
            kAXWindowResizedNotification,
            kAXFocusedWindowChangedNotification,
            kAXWindowMiniaturizedNotification,
            kAXWindowDeminiaturizedNotification
        ]

        for notif in notifications {
            AXObserverAddNotification(axObserver, appElement, notif as CFString, selfPtr)
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(axObserver),
            .commonModes
        )
        axObservers[pid] = axObserver
    }

    private func removeAXObserver(for pid: pid_t) {
        guard let axObserver = axObservers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(axObserver),
            .commonModes
        )
    }

    // MARK: - Zero-Permission Native Dock Piggyback & Suppression Utilities

    /// Hides or gives back the native Dock through `NativeDockPreferencesService`, the one path that
    /// records the user's own setting first and can put it back. There is no shell fallback: the
    /// service is unavailable only in a sandbox, where `defaults write com.apple.dock` cannot work
    /// either. `service` is injectable so a test never reaches the real Dock.
    static func suppressNativeMacDock(
        suppress: Bool,
        service: NativeDockPreferencesService? = nil
    ) {
        // Built here rather than as a default argument: the service's init is main-actor isolated
        // and a default argument is evaluated in a nonisolated context.
        let service = service ?? NativeDockPreferencesService()
        guard service.isAvailable else { return }
        if suppress {
            try? service.apply(delay: NativeDockPreferencesService.noWakeDelay)
        } else {
            service.restoreOriginal(forget: true)
        }
    }

    public static func installKeepAliveLaunchAgent(bundleIdentifier: String = "com.katikati.app", executablePath: String) throws {
        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(bundleIdentifier).keepalive</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(executablePath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <dict>
                <key>SuccessfulExit</key>
                <false/>
            </dict>
            <key>ProcessType</key>
            <string>Interactive</string>
            <key>ThrottleInterval</key>
            <integer>1</integer>
        </dict>
        </plist>
        """

        let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
        let plistURL = launchAgentsDir.appendingPathComponent("\(bundleIdentifier).keepalive.plist")
        try plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
    }
}
