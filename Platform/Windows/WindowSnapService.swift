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

        guard isTileable(window) else { return .noWindow }
        let area = DockReserve.workArea(visible: screen.visibleFrame, screen: screen.frame, dock: dockFrame(screen))
        let target = position.frame(in: area)
        let point = SnapPosition.accessibilityOrigin(of: target, primaryMaxY: primary.maxY)
        let quartzTarget = CGRect(origin: point, size: target.size)
        let quartzArea = CGRect(origin: SnapPosition.accessibilityOrigin(of: area, primaryMaxY: primary.maxY), size: area.size)

        // Maximize is a toggle: pressing it on an already-maximized window puts the old frame back.
        let key = Int(bitPattern: CFHash(window))
        let current = frame(of: window)
        if position == .maximize, let current, let saved = previousFrames[key],
           abs(current.width - quartzTarget.width) <= 2, abs(current.height - quartzTarget.height) <= 2 {
            previousFrames[key] = nil
            place(window, quartzFrame: saved, within: nil)
            return .moved
        }
        if let current, !(position == .maximize && previousFrames[key] != nil) { previousFrames[key] = current }
        place(window, quartzFrame: quartzTarget, within: quartzArea)
        if let cgID = AXWindowReader.cgWindowID(for: window) {
            TilingEngine.shared.releaseWindow(cgWindowID: cgID)
        }
        return .moved
    }

    /// Moves the focused window to the next display, keeping its relative position and size in the work area.
    @discardableResult
    static func moveToNextDisplay() -> Outcome { moveToDisplay(step: 1) }

    /// Same move, `step` displays along and wrapping around, so a gesture can send a window back too.
    @discardableResult
    static func moveToDisplay(step: Int) -> Outcome {
        guard AXIsProcessTrusted() else { return .needsAccessibility }
        let screens = NSScreen.screens
        guard screens.count > 1, let primary = screens.first?.frame,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return .noWindow }
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return .noWindow }
        let window = ref as! AXUIElement
        guard isTileable(window), let f = frame(of: window), let from = screenContaining(window, primaryMaxY: primary.maxY),
              let index = screens.firstIndex(of: from) else { return .noWindow }
        let to = screens[DisplayMove.destination(from: index, count: screens.count, step: step)]
        func area(_ s: NSScreen) -> CGRect { DockReserve.workArea(visible: s.visibleFrame, screen: s.frame, dock: dockFrame(s)) }
        func quartz(_ r: CGRect) -> CGRect { CGRect(origin: SnapPosition.accessibilityOrigin(of: r, primaryMaxY: primary.maxY), size: r.size) }
        let a = quartz(area(from)), b = quartz(area(to))
        let w = min(f.width, b.width), h = min(f.height, b.height)
        let target = CGRect(x: b.minX + (f.minX - a.minX) / max(a.width, 1) * b.width,
                            y: b.minY + (f.minY - a.minY) / max(a.height, 1) * b.height, width: w, height: h)
        place(window, quartzFrame: WindowFit.shifted(target, into: b), within: b)
        return .moved
    }

    /// Frames to return to after a maximize, keyed by the AX element's hash (shortcut: in memory, lost on relaunch).
    private static var previousFrames: [Int: CGRect] = [:]

    /// A window layout may touch: not native-fullscreen, not minimized, a standard resizable window.
    static func isTileable(_ window: AXUIElement) -> Bool {
        func flag(_ name: String) -> Bool {
            var ref: CFTypeRef?
            return AXUIElementCopyAttributeValue(window, name as CFString, &ref) == .success && (ref as? Bool) == true
        }
        if flag("AXFullScreen") || flag(kAXMinimizedAttribute as String) { return false }
        var sub: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &sub) == .success,
           let sub = sub as? String, sub != kAXStandardWindowSubrole as String { return false }
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &settable) == .success, !settable.boolValue { return false }
        return true
    }

    /// Writes a Quartz frame, reads back what the app really took, and shifts it inside `area` if it clamped past the edge.
    /// Returns the frame the window ended up with.
    @discardableResult
    static func place(_ window: AXUIElement, quartzFrame: CGRect, within area: CGRect?) -> CGRect? {
        var point = quartzFrame.origin
        var size = quartzFrame.size
        guard let pointValue = AXValueCreate(.cgPoint, &point), let sizeValue = AXValueCreate(.cgSize, &size) else { return nil }

        // "Enhanced user interface" (VoiceOver, some launchers) makes the first frame change land wrong; switch it
        // off while laying out and restore it (the snapper cited in NOTICE §9).
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        let appElement = AXUIElementCreateApplication(pid)
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
        guard var actual = frame(of: window) else { return quartzFrame }
        if let area {
            let fixed = WindowFit.shifted(actual, into: area)
            if fixed.origin != actual.origin {
                var p = fixed.origin
                if let v = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v) }
                actual = frame(of: window) ?? fixed
            }
        }
        return actual
    }

    static func frame(of window: AXUIElement) -> CGRect? {
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

    /// The focused window's AppKit (bottom-left origin) frame, for drag tracking only.
    static func frontmostWindowFrameCocoa() -> CGRect? {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier),
                                            kAXFocusedWindowAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID(),
              let primary = NSScreen.screens.first?.frame.maxY,
              let quartz = frame(of: ref as! AXUIElement) else { return nil }
        return CGRect(x: quartz.minX, y: primary - quartz.maxY, width: quartz.width, height: quartz.height)
    }
}

/// Non-intercepting drag-to-edge monitor (G3). It observes mouse drags only while the setting is
/// on, draws a ghost of the planned zone, and applies it after release. `DragController` is untouched.
@MainActor
final class SnapDragMonitor {
    private var monitors: [Any] = []
    private var activeZone: SnapZonePlanner.Zone?
    private var tracking = false
    private var style = SnapPreviewStyle.outline
    private var edgeMargin: CGFloat = 12
    private var preview: NSPanel?

    func setEnabled(_ enabled: Bool, style: SnapPreviewStyle, edgeMargin: CGFloat = 12) {
        self.style = style
        self.edgeMargin = edgeMargin
        if enabled { start() } else { stop() }
    }

    private func start() {
        guard monitors.isEmpty else { return }
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dragged() }
        })
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            MainActor.assumeIsolated { self?.released() }
        })
    }

    private func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        tracking = false
        activeZone = nil
        preview?.orderOut(nil)
        preview = nil
    }

    private func dragged() {
        let mouse = NSEvent.mouseLocation
        if !tracking {
            guard let frame = WindowSnapService.frontmostWindowFrameCocoa(),
                  frame.insetBy(dx: -2, dy: -2).contains(mouse) else { return }
            tracking = true
        }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) else {
            activeZone = nil
            preview?.orderOut(nil)
            return
        }
        let area = DockReserve.workArea(visible: screen.visibleFrame, screen: screen.frame,
                                        dock: WindowSnapService.dockFrame(screen))
        let layout: SnapZonePlanner.Layout = NSEvent.modifierFlags.contains(.option) ? .thirds : .edgesAndCorners
        let previous = layout == .edgesAndCorners ? activeZone.flatMap {
            (![SnapPosition.leftThird, .centerThird, .rightThird].contains($0.position)
             && $0.frame.insetBy(dx: -8, dy: -8).contains(mouse)) ? $0 : nil
        } : nil
        guard let zone = previous ?? SnapZonePlanner.resolve(at: mouse, in: area, layout: layout, edgeMargin: edgeMargin) else {
            activeZone = nil
            preview?.orderOut(nil)
            return
        }
        activeZone = zone
        show(zone)
    }

    private func released() {
        defer {
            tracking = false
            activeZone = nil
            preview?.orderOut(nil)
        }
        guard let zone = activeZone else { return }
        WindowSnapService.apply(zone.position)
    }

    private func show(_ zone: SnapZonePlanner.Zone) {
        guard style.drawsPreview else {
            preview?.orderOut(nil)
            return
        }
        let panel: NSPanel
        if let preview {
            panel = preview
        } else {
            let created = NSPanel(contentRect: zone.frame, styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
            created.level = .floating
            created.isOpaque = false
            created.backgroundColor = .clear
            created.hasShadow = false
            created.ignoresMouseEvents = true
            created.isReleasedWhenClosed = false
            created.contentView = SnapPreviewView(style: style)
            preview = created
            panel = created
        }
        (panel.contentView as? SnapPreviewView)?.apply(style)
        panel.setFrame(zone.frame, display: true)
        panel.orderFrontRegardless()
    }
}

private final class SnapPreviewView: NSView {
    init(style: SnapPreviewStyle) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        apply(style)
    }
    required init?(coder: NSCoder) { nil }

    func apply(_ style: SnapPreviewStyle) {
        layer?.backgroundColor = style == .filled
            ? NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor : NSColor.clear.cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
