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
            configureModeSideEffects()
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

    // MARK: Stability & Concurrency Primitives
    private let axQueue = DispatchQueue(label: "com.katikati.ax.serial", qos: .userInteractive)
    private var axObservers: [pid_t: AXObserver] = [:]
    private var workspaceCancellables = Set<AnyCancellable>()
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var mousePollingFallbackTimer: Timer?
    private var edgeHoverTimer: Timer?
    private var overlapPollTimer: Timer?
    private var passiveEventTap: CFMachPort?
    private var passiveEventTapRunLoopSource: CFRunLoopSource?
    private var screenReconfigDebounceWorkItem: DispatchWorkItem?

    public init() {
        self.hasAccessibilityPermission = AXIsProcessTrusted()
    }

    // MARK: - Lifecycle

    public func start() {
        self.hasAccessibilityPermission = AXIsProcessTrusted()
        registerSystemNotifications()
        startMouseEdgeMonitoringWithZeroPermissionFallback()
        startWindowOverlapPolling()
        setupAccessibilityObserversForRunningApps()
        setupOptionalPassiveHIDEventTap()
        evaluateWindowLayering()
    }

    public func stop() {
        workspaceCancellables.removeAll()
        if let g = globalMouseMonitor { NSEvent.removeMonitor(g); globalMouseMonitor = nil }
        if let l = localMouseMonitor { NSEvent.removeMonitor(l); localMouseMonitor = nil }
        mousePollingFallbackTimer?.invalidate()
        mousePollingFallbackTimer = nil
        edgeHoverTimer?.invalidate()
        edgeHoverTimer = nil
        overlapPollTimer?.invalidate()
        overlapPollTimer = nil
        screenReconfigDebounceWorkItem?.cancel()
        screenReconfigDebounceWorkItem = nil

        if let tap = passiveEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            passiveEventTap = nil
        }
        if let source = passiveEventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            passiveEventTapRunLoopSource = nil
        }
        for (pid, _) in axObservers {
            removeAXObserver(for: pid)
        }
    }

    private func configureModeSideEffects() {
        if layeringMode == .nativeDockVisibleFramePiggyback {
            Self.configureNativeDockForVisibleFramePiggyback(height: Int(dockHeight))
        }
    }

    // MARK: - Core Z-Order, Relative Ordering & Fallback Cascade

    public func evaluateWindowLayering() {
        hasAccessibilityPermission = AXIsProcessTrusted()

        let dockPanels = managedPanelsProvider?() ?? []
        let bgPanels = managedBackgroundPanelsProvider?() ?? []
        let capsulePanels = managedCapsulePanelsProvider?() ?? []

        let targetScreens: [NSScreen]
        if !dockPanels.isEmpty {
            targetScreens = Array(Set(dockPanels.compactMap { $0.screen }))
        } else {
            targetScreens = [NSScreen.main ?? NSScreen.screens.first].compactMap { $0 }
        }

        var isAnyOverlapping = false
        var topOverlappingWID: CGWindowID?
        var primaryClampingDockFrame: NSRect?
        var primaryClampingScreen: NSScreen?

        for screen in targetScreens {
            let visibleDockFrame = NSRect(
                x: screen.frame.origin.x,
                y: screen.frame.origin.y,
                width: screen.frame.width,
                height: dockHeight
            )
            let result = findOverlappingStandardWindow(dockFrame: visibleDockFrame, on: screen)
            if result.isOverlapping {
                isAnyOverlapping = true
                if topOverlappingWID == nil {
                    topOverlappingWID = result.topOverlappingWindowID
                    primaryClampingDockFrame = visibleDockFrame
                    primaryClampingScreen = screen
                }
            }
        }

        if primaryClampingDockFrame == nil, let firstScreen = targetScreens.first {
            primaryClampingDockFrame = NSRect(
                x: firstScreen.frame.origin.x,
                y: firstScreen.frame.origin.y,
                width: firstScreen.frame.width,
                height: dockHeight
            )
            primaryClampingScreen = firstScreen
        }

        self.isOverlappedByWindow = isAnyOverlapping

        // Reset click-through & alpha unless in `.clickThroughGhostFallback`
        if layeringMode != .clickThroughGhostFallback {
            for panel in dockPanels + bgPanels + capsulePanels {
                panel.ignoresMouseEvents = false
                panel.alphaValue = 1.0
            }
        }

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
                for panel in dockPanels + capsulePanels {
                    panel.ignoresMouseEvents = false
                    panel.alphaValue = 1.0
                }
                applyDockLevel(MacDockWindowLevel.nativeDock, orderAbove: true)
            } else {
                for panel in dockPanels + capsulePanels {
                    panel.ignoresMouseEvents = true
                    panel.alphaValue = 0.08
                }
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
            if let clampingFrame = primaryClampingDockFrame, let clampingScreen = primaryClampingScreen {
                if hasAccessibilityPermission {
                    applyDockLevel(MacDockWindowLevel.nativeDock, orderAbove: true)
                    clampFrontmostWindowAboveDock(dockFrame: clampingFrame, on: clampingScreen)
                } else if useAppleScriptResizeFallback {
                    applyDockLevel(MacDockWindowLevel.nativeDock, orderAbove: true)
                    clampFrontmostWindowViaAppleScriptFallback(dockFrame: clampingFrame, on: clampingScreen)
                } else {
                    // Automatic Zero-Permission Fallback Cascade
                    if isElevatedByHover || !isAnyOverlapping {
                        applyDockLevel(MacDockWindowLevel.nativeDock, orderAbove: true)
                    } else {
                        applyDockLevel(MacDockWindowLevel.belowNormalWindows, orderAbove: false)
                    }
                }
            }
        }
    }

    /// Sets the AppKit `NSWindow.Level` and optionally reinforces it via private SkyLight `CGSSetWindowLevel`
    /// so WindowServer immediately updates compositing order without waiting for an AppKit flush.
    public func applyDockLevel(_ level: NSWindow.Level, orderAbove: Bool) {
        let dockPanels = managedPanelsProvider?() ?? []
        let bgPanels = managedBackgroundPanelsProvider?() ?? []
        let capsulePanels = managedCapsulePanelsProvider?() ?? []

        let cid = useSkyLightFallbackReinforcement ? CGSMainConnectionID() : 0

        for panel in bgPanels {
            panel.level = level
            if useSkyLightFallbackReinforcement, panel.windowNumber > 0 {
                CGSSetWindowLevel(cid, CGWindowID(panel.windowNumber), Int32(level.rawValue))
            }
        }

        for panel in dockPanels {
            panel.level = level
            if orderAbove {
                panel.orderFrontRegardless()
            }
            if useSkyLightFallbackReinforcement, panel.windowNumber > 0 {
                CGSSetWindowLevel(cid, CGWindowID(panel.windowNumber), Int32(level.rawValue))
            }
        }

        for panel in capsulePanels {
            panel.level = level
            if useSkyLightFallbackReinforcement, panel.windowNumber > 0 {
                CGSSetWindowLevel(cid, CGWindowID(panel.windowNumber), Int32(level.rawValue))
            }
        }

        // Maintain relative sub-ordering between glass background and content
        for (bg, dock) in zip(bgPanels, dockPanels) {
            bg.order(.below, relativeTo: dock.windowNumber)
        }
        for (capsule, dock) in zip(capsulePanels, dockPanels) {
            if capsule.isVisible {
                capsule.order(.above, relativeTo: dock.windowNumber)
            }
        }
    }

    private func applySameLevelOrderBelow(coveringWID: CGWindowID) {
        let dockPanels = managedPanelsProvider?() ?? []
        let bgPanels = managedBackgroundPanelsProvider?() ?? []
        let cid = useSkyLightFallbackReinforcement ? CGSMainConnectionID() : 0

        for panel in dockPanels + bgPanels {
            panel.level = MacDockWindowLevel.normalWindow
            panel.order(.below, relativeTo: Int(coveringWID))
            if useSkyLightFallbackReinforcement, panel.windowNumber > 0 {
                let wid = CGWindowID(panel.windowNumber)
                CGSSetWindowLevel(cid, wid, Int32(MacDockWindowLevel.normalWindow.rawValue))
                CGSOrderWindow(cid, wid, kCGSOrderBelow, coveringWID)
            }
        }
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

    // MARK: - Screen-Edge Sensor + Zero-Permission 20 FPS Mouse Polling Fallback

    private func startMouseEdgeMonitoringWithZeroPermissionFallback() {
        let handler: (NSEvent?) -> Void = { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseMoved()
            }
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: handler)
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { event in
            handler(event)
            return event
        }

        // Zero-permission fallback timer: `NSEvent.mouseLocation` is always readable without TCC permissions.
        mousePollingFallbackTimer?.invalidate()
        mousePollingFallbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseMoved()
            }
        }
    }

    /// Optional With-Permission Fallback: Passive `CGEventTap` on `.cghidEventTap` (`listenOnly`)
    private func setupOptionalPassiveHIDEventTap() {
        guard AXIsProcessTrusted(), passiveEventTap == nil else { return }

        let mask = (1 << CGEventType.mouseMoved.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<DockWindowManager>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = manager.passiveEventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }
            Task { @MainActor in
                manager.handleMouseMoved()
            }
            return Unmanaged.passUnretained(event)
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        if let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: selfPtr
        ) {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            self.passiveEventTap = tap
            self.passiveEventTapRunLoopSource = source
        }
    }

    public func handleMouseMoved() {
        let mouseLoc = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLoc) }) ?? NSScreen.main ?? NSScreen.screens.first else { return }

        let dockPanels = managedPanelsProvider?() ?? []
        let dockScreens = dockPanels.compactMap { $0.screen }
        let isScreenHostingDock = dockScreens.isEmpty || dockScreens.contains(screen)

        let edgeTriggerZone = NSRect(
            x: screen.frame.origin.x,
            y: screen.frame.origin.y,
            width: screen.frame.width,
            height: edgeTriggerHeight + 2.0
        )

        let fullDockZone = NSRect(
            x: screen.frame.origin.x,
            y: screen.frame.origin.y,
            width: screen.frame.width,
            height: dockHeight + 8.0
        )

        if isElevatedByHover {
            if !fullDockZone.contains(mouseLoc) {
                edgeHoverTimer?.invalidate()
                edgeHoverTimer = nil
                isElevatedByHover = false
                evaluateWindowLayering()
            }
        } else {
            if isScreenHostingDock && edgeTriggerZone.contains(mouseLoc) {
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

    private func startWindowOverlapPolling() {
        overlapPollTimer?.invalidate()
        overlapPollTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateWindowLayering()
            }
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
        guard AXIsProcessTrusted(),
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

    public static func configureNativeDockForVisibleFramePiggyback(height: Int = 48) {
        let clampedTileSize = max(16, min(128, height - 8))
        let task = Process()
        task.launchPath = "/bin/zsh"
        task.arguments = [
            "-c",
            "defaults write com.apple.dock orientation -string bottom && defaults write com.apple.dock autohide -bool false && defaults write com.apple.dock tilesize -int \(clampedTileSize) && defaults write com.apple.dock magnification -bool false && killall Dock"
        ]
        try? task.run()
    }

    public static func suppressNativeMacDock(suppress: Bool) {
        let service = NativeDockPreferencesService()
        if service.isAvailable {
            if suppress {
                try? service.apply(delay: NativeDockPreferencesService.noWakeDelay)
            } else {
                service.restoreOriginal(forget: true)
            }
            return
        }

        let task = Process()
        task.launchPath = "/bin/zsh"
        if suppress {
            task.arguments = [
                "-c",
                "defaults write com.apple.dock autohide -bool true && defaults write com.apple.dock autohide-delay -float 1000 && defaults write com.apple.dock no-bouncing -bool true && killall Dock"
            ]
        } else {
            task.arguments = [
                "-c",
                "defaults delete com.apple.dock autohide-delay; defaults write com.apple.dock autohide -bool false && killall Dock"
            ]
        }
        try? task.run()
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
