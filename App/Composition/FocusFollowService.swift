import AppKit
import ApplicationServices
import OSLog

/// 54e — raises the window under the pointer. Off by default and inert without Accessibility: the AX hit
/// test fails without the grant, so the monitor is never even installed and the Settings row says why.
@MainActor
final class FocusFollowService {
    static let shared = FocusFollowService()
    nonisolated static let enabledKey = "com.katikati.windows.focusFollow"

    private let log = Logger(subsystem: "com.katikati.app", category: "focusFollow")
    private var monitor: Any?
    private var policy = FocusFollowPolicy()

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
    }

    private func start() {
        guard monitor == nil, AXIsProcessTrusted() else { return }
        policy.lastRaiseAt = nil
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMove() }
        }
    }

    private func handleMove() {
        guard AXIsProcessTrusted() else { stop(); return }
        let target = Self.windowUnderPointer(Self.pointerInAccessibilitySpace())
        let now = Date()
        guard let target,
              policy.allowsRaise(targetPID: target.pid,
                                 frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                                 ownPID: getpid(),
                                 mouseButtonDown: NSEvent.pressedMouseButtons != 0,
                                 ownPanelIsKey: NSApp.keyWindow != nil,
                                 now: now) else { return }
        policy.lastRaiseAt = now
        NSRunningApplication(processIdentifier: target.pid)?.activate()
        if AXUIElementPerformAction(target.window, kAXRaiseAction as CFString) != .success {
            log.debug("raise failed pid=\(target.pid)")
        }
    }

    /// Cocoa's pointer origin is bottom-left; AX hit-testing is top-left of the primary display.
    nonisolated static func pointerInAccessibilitySpace() -> CGPoint {
        let cocoa = NSEvent.mouseLocation
        return SnapPosition.accessibilityOrigin(of: CGRect(origin: cocoa, size: .zero),
                                                primaryMaxY: NSScreen.screens.first?.frame.maxY ?? 0)
    }

    struct Target {
        var pid: pid_t
        var window: AXUIElement
    }

    /// The AX window under `point`: hit-test the element there, then walk up to its `AXWindow` ancestor.
    nonisolated static func windowUnderPointer(_ point: CGPoint) -> Target? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element) == .success,
              var current = element else { return nil }
        for _ in 0..<12 {
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
