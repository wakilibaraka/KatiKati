import AppKit
import ApplicationServices
import OSLog
import os.lock

/// 54e — raises the window under the pointer. Off by default and inert without Accessibility: the AX hit
/// test fails without the grant, so the monitor is never even installed and the Settings row says why.
@MainActor
final class FocusFollowService {
    static let shared = FocusFollowService()
    nonisolated static let enabledKey = "com.katikati.windows.focusFollow"

    private let log = Logger(subsystem: "com.katikati.app", category: "focusFollow")
    private var monitor: Any?
    private var policy = FocusFollowPolicy()
    private let axQueue = DispatchQueue(label: "com.katikati.focusFollow.ax", qos: .userInteractive)
    private var coalescerLock = os_unfair_lock_s()
    private var coalescer = FocusFollowCoalescer()

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        if on { start() } else { stop() }
    }

    /// Launch: nothing runs unless the switch is on and the grant is there.
    func startIfEnabled() {
        guard isEnabled else { return }
        start()
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        os_unfair_lock_lock(&coalescerLock)
        coalescer.reset()
        os_unfair_lock_unlock(&coalescerLock)
    }

    private func start() {
        guard monitor == nil, AXIsProcessTrusted() else { return }
        policy.lastRaiseAt = nil
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMove() }
        }
    }

    private var lastHoverSampleAt: TimeInterval = 0

    private func handleMove() {
        guard AXIsProcessTrusted() else { stop(); return }
        let nowUptime = ProcessInfo.processInfo.systemUptime
        guard nowUptime - lastHoverSampleAt >= 0.04 else { return }
        lastHoverSampleAt = nowUptime
        let axPoint = Self.pointerInAccessibilitySpace()
        os_unfair_lock_lock(&coalescerLock)
        let firstPoint = coalescer.submit(axPoint)
        os_unfair_lock_unlock(&coalescerLock)
        if let firstPoint { dispatchLookup(at: firstPoint) }
    }

    private func dispatchLookup(at point: CGPoint) {
        axQueue.async { [weak self] in
            guard let self else { return }
            let target = Self.windowUnderPointer(point)
            os_unfair_lock_lock(&self.coalescerLock)
            let nextPoint = self.coalescer.complete()
            os_unfair_lock_unlock(&self.coalescerLock)
            if let target {
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated { self?.applyLookupResult(target) }
                }
            }
            if let nextPoint { self.dispatchLookup(at: nextPoint) }
        }
    }

    private func applyLookupResult(_ target: Target) {
        guard monitor != nil else { return }
        let now = Date()
        guard policy.allowsRaise(targetPID: target.pid,
                                 frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                                 ownPID: getpid(),
                                 mouseButtonDown: NSEvent.pressedMouseButtons != 0,
                                 ownPanelIsKey: NSApp.keyWindow != nil,
                                 ownPopupVisible: Self.hasVisibleOwnPopupWindow(),
                                 now: now) else { return }
        policy.lastRaiseAt = now
        NSRunningApplication(processIdentifier: target.pid)?.activate()
        AXMessagingPolicy.applyTimeout(target.window)
        if AXUIElementPerformAction(target.window, kAXRaiseAction as CFString) != .success {
            log.debug("raise failed pid=\(target.pid)")
        }
    }

    /// True when any of KatiKati's pop-up / flyout / expanded-notch / settings windows is visible on screen
    /// (height > 120 pt distinguishes pop-ups and panels from the always-on dock strip and closed notch).
    private static func hasVisibleOwnPopupWindow() -> Bool {
        NSApp.windows.contains { window in
            window.isVisible && window.alphaValue > 0.01 && window.frame.height > 120 && window.frame.width > 120
        }
    }

    /// Cocoa's pointer origin is bottom-left; AX hit-testing is top-left of the primary display.
    nonisolated static func pointerInAccessibilitySpace() -> CGPoint {
        let cocoa = NSEvent.mouseLocation
        return SnapPosition.accessibilityOrigin(of: CGRect(origin: cocoa, size: .zero),
                                                primaryMaxY: NSScreen.screens.first?.frame.maxY ?? 0)
    }

    struct Target: @unchecked Sendable {
        var pid: pid_t
        var window: AXUIElement
    }

    /// The AX window under `point`: hit-test the element there, then walk up to its `AXWindow` ancestor.
    nonisolated static func windowUnderPointer(_ point: CGPoint) -> Target? {
        var element: AXUIElement?
        let sysWide = AXMessagingPolicy.applyTimeout(AXUIElementCreateSystemWide())
        guard AXUIElementCopyElementAtPosition(sysWide, Float(point.x), Float(point.y), &element) == .success,
              var current = element else { return nil }
        for _ in 0..<12 {
            AXMessagingPolicy.applyTimeout(current)
            var role: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &role) == .success,
               (role as? String) == kAXWindowRole {
                var pid: pid_t = 0
                guard AXUIElementGetPid(current, &pid) == .success else { return nil }
                return Target(pid: pid, window: current)
            }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success,
                  let next = parent else { return nil }
            // AX hands back a CFTypeRef; the attribute only ever holds an element.
            current = unsafeDowncast(next, to: AXUIElement.self)
        }
        return nil
    }
}
