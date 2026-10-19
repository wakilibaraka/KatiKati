import AppKit
import ApplicationServices

/// Moves the frontmost other app's focused window into a zone through the Accessibility API. The deck panels are
/// non-activating, so the app the user was working in is still frontmost when a zone button is pressed.
@MainActor
enum WindowSnapService {
    enum Outcome { case moved, needsAccessibility, noWindow }

    /// The solid dock's frame on a screen (nil when hidden/auto-hiding); zones stay clear of it.
    static var dockFrame: (NSScreen) -> CGRect? = { _ in nil }

    @discardableResult
    static func apply(_ position: SnapPosition) -> Outcome {
        guard AXIsProcessTrusted() else { return .needsAccessibility }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return .noWindow }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID(),
              let primary = NSScreen.screens.first?.frame else { return .noWindow }
        let window = windowRef as! AXUIElement
        guard let screen = screenContaining(window, primaryMaxY: primary.maxY) ?? NSScreen.main else { return .noWindow }

        let target = position.frame(in: DockReserve.workArea(visible: screen.visibleFrame, screen: screen.frame, dock: dockFrame(screen)))
        var point = SnapPosition.accessibilityOrigin(of: target, primaryMaxY: primary.maxY)
        var size = target.size
        guard let pointValue = AXValueCreate(.cgPoint, &point), let sizeValue = AXValueCreate(.cgSize, &size) else { return .noWindow }

        // "Enhanced user interface" (VoiceOver, some launchers) makes the first frame change land wrong; switch it
        // off while laying out and restore it (the approach Hop's snapper uses).
        let enhancedKey = "AXEnhancedUserInterface" as CFString
        var enhancedRef: CFTypeRef?
        let hadEnhanced = AXUIElementCopyAttributeValue(appElement, enhancedKey, &enhancedRef) == .success
            && ((enhancedRef as? NSNumber)?.boolValue ?? false)
        if hadEnhanced { AXUIElementSetAttributeValue(appElement, enhancedKey, kCFBooleanFalse) }
        defer { if hadEnhanced { AXUIElementSetAttributeValue(appElement, enhancedKey, kCFBooleanTrue) } }

        // size → position → size converges for windows that clamp; re-check up to three times.
        for _ in 0..<3 {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pointValue)
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            if frame(of: window).map({ abs($0.origin.x - point.x) <= 1 && abs($0.origin.y - point.y) <= 1
                                        && abs($0.width - size.width) <= 1 && abs($0.height - size.height) <= 1 }) ?? true { break }
        }
        return .moved
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef, CFGetTypeID(posRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &p)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }

    private static func screenContaining(_ window: AXUIElement, primaryMaxY: CGFloat) -> NSScreen? {
        guard let f = frame(of: window) else { return nil }
        let center = CGPoint(x: f.midX, y: primaryMaxY - f.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
    }
}
