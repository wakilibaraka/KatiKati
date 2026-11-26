import AppKit
import ApplicationServices
import os.lock

enum AXMessagingPolicy {
    static let defaultTimeoutSeconds: Float = 0.15

    @discardableResult
    static func applyTimeout(_ element: AXUIElement, seconds: Float = defaultTimeoutSeconds) -> AXUIElement {
        _ = AXUIElementSetMessagingTimeout(element, seconds)
        return element
    }
}

/// Moves the frontmost other app's focused window into a zone through the Accessibility API. The deck panels are
/// non-activating, so the app the user was working in is still frontmost when a zone button is pressed.
@MainActor
enum WindowSnapService {
    enum Outcome { case moved, needsAccessibility, noWindow }

    /// The solid dock's frame on a screen (nil when hidden/auto-hiding); zones stay clear of it.
    static var dockFrame: (NSScreen) -> CGRect? = { _ in nil }

    static func workArea(of screen: NSScreen) -> CGRect {
        DockReserve.workArea(visible: screen.visibleFrame, screen: screen.frame, dock: dockFrame(screen))
    }

    @discardableResult
    static func apply(_ position: SnapPosition) -> Outcome {
        guard AXIsProcessTrusted() else { return .needsAccessibility }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return .noWindow }
        let appElement = AXMessagingPolicy.applyTimeout(AXUIElementCreateApplication(app.processIdentifier))
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID(),
              let primary = NSScreen.screens.first?.frame else { return .noWindow }
        let window = AXMessagingPolicy.applyTimeout(windowRef as! AXUIElement)
        guard let screen = screenContaining(window, primaryMaxY: primary.maxY) ?? NSScreen.main else { return .noWindow }

        guard isTileable(window) else { return .noWindow }
        let area = workArea(of: screen)
        let target = position.frame(in: area, gaps: SnapGaps.current())
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
        let appElement = AXMessagingPolicy.applyTimeout(AXUIElementCreateApplication(app.processIdentifier))
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return .noWindow }
        let window = AXMessagingPolicy.applyTimeout(ref as! AXUIElement)
        guard isTileable(window), let f = frame(of: window), let from = screenContaining(window, primaryMaxY: primary.maxY),
              let index = screens.firstIndex(of: from) else { return .noWindow }
        let to = screens[DisplayMove.destination(from: index, count: screens.count, step: step)]
        func area(_ s: NSScreen) -> CGRect { workArea(of: s) }
        func quartz(_ r: CGRect) -> CGRect { CGRect(origin: SnapPosition.accessibilityOrigin(of: r, primaryMaxY: primary.maxY), size: r.size) }
        // MD-4: one pure mapping, shared with the throw hot keys and covered by `WindowThrowTests`.
        let target = WindowThrow.relativeFrame(from: f, source: quartz(area(from)), destination: quartz(area(to)))
        place(window, quartzFrame: target, within: quartz(area(to)))
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
        let appElement = AXMessagingPolicy.applyTimeout(AXUIElementCreateApplication(pid))
        _ = AXMessagingPolicy.applyTimeout(window)
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

    nonisolated static func origin(of window: AXUIElement) -> CGPoint? {
        var posRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              let posRef, CFGetTypeID(posRef) == AXValueGetTypeID()
        else { return nil }
        var p = CGPoint.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &p)
        return p
    }

    nonisolated static func frame(of window: AXUIElement) -> CGRect? {
        var sizeRef: CFTypeRef?
        guard let p = origin(of: window),
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let sizeRef, CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }
        var s = CGSize.zero
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
        let appElement = AXMessagingPolicy.applyTimeout(AXUIElementCreateApplication(app.processIdentifier))
        guard AXUIElementCopyAttributeValue(appElement,
                                            kAXFocusedWindowAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID(),
              let primary = NSScreen.screens.first?.frame.maxY,
              let quartz = frame(of: AXMessagingPolicy.applyTimeout(ref as! AXUIElement)) else { return nil }
        return CGRect(x: quartz.minX, y: primary - quartz.maxY, width: quartz.width, height: quartz.height)
    }

    /// Returns the CoreGraphics window ID of the frontmost other app's focused window, if accessible.
    static func frontmostWindowCGID() -> CGWindowID? {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        var ref: CFTypeRef?
        let appElement = AXMessagingPolicy.applyTimeout(AXUIElementCreateApplication(app.processIdentifier))
        guard AXUIElementCopyAttributeValue(appElement,
                                            kAXFocusedWindowAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return AXWindowReader.cgWindowID(for: AXMessagingPolicy.applyTimeout(ref as! AXUIElement))
    }
}

/// Serial background Accessibility reader for `SnapDragMonitor` so drag events never block `@MainActor`.
private final class SnapAXProbe: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.katikati.snap.ax", qos: .userInteractive)
    private var lock = os_unfair_lock_s()
    private var pollInFlight = false
    private var cachedPressID: UInt64 = 0
    private var cachedWindow: AXUIElement?

    func seed(pressID: UInt64,
              pid: pid_t,
              primaryMaxY: CGFloat,
              completion: @escaping @MainActor @Sendable (UInt64, CGRect?, CGPoint?) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            self.cachedPressID = pressID
            self.cachedWindow = nil
            let appElement = AXMessagingPolicy.applyTimeout(AXUIElementCreateApplication(pid))
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &ref) == .success,
                  let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else {
                DispatchQueue.main.async { completion(pressID, nil, nil) }
                return
            }
            let window = AXMessagingPolicy.applyTimeout(ref as! AXUIElement)
            guard let quartz = WindowSnapService.frame(of: window) else {
                DispatchQueue.main.async { completion(pressID, nil, nil) }
                return
            }
            self.cachedWindow = window
            let cocoa = CGRect(x: quartz.minX, y: primaryMaxY - quartz.maxY, width: quartz.width, height: quartz.height)
            DispatchQueue.main.async { completion(pressID, cocoa, quartz.origin) }
        }
    }

    func pollOrigin(pressID: UInt64, completion: @escaping @MainActor @Sendable (UInt64, CGPoint?) -> Void) {
        os_unfair_lock_lock(&lock)
        if pollInFlight {
            os_unfair_lock_unlock(&lock)
            return
        }
        pollInFlight = true
        os_unfair_lock_unlock(&lock)

        queue.async { [weak self] in
            guard let self else { return }
            defer {
                os_unfair_lock_lock(&self.lock)
                self.pollInFlight = false
                os_unfair_lock_unlock(&self.lock)
            }
            guard self.cachedPressID == pressID, let window = self.cachedWindow else { return }
            let origin = WindowSnapService.origin(of: window)
            DispatchQueue.main.async { completion(pressID, origin) }
        }
    }

    func clear() {
        queue.async { [weak self] in
            self?.cachedPressID = 0
            self?.cachedWindow = nil
        }
    }
}

/// Non-intercepting drag-to-edge monitor (G3). It observes mouse drags only while the setting is
/// on, draws a ghost of the planned zone, and applies it after release. `DragController` is untouched.
@MainActor
final class SnapDragMonitor {
    private var monitors: [Any] = []
    private var activeZone: SnapZonePlanner.Zone?
    private var session = SnapDragSession()
    private let axProbe = SnapAXProbe()
    private var style = SnapPreviewStyle.outline
    private var edgeMargin: CGFloat = 12
    private var preview: NSPanel?
    /// MD-2: when the pointer first touched each seam edge group. Its own edge resolves a snap only
    /// once the pointer has rested there for `SnapGaps.seamDwell`; a crossing never does.
    private var seamHold: (key: String, since: Date)?

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
        session.reset()
        axProbe.clear()
        seamHold = nil
        activeZone = nil
        preview?.orderOut(nil)
        preview = nil
    }

    private func dragged() {
        let mouse = NSEvent.mouseLocation
        if session.isIdle {
            let pressID = session.beginPress(at: mouse)
            guard AXIsProcessTrusted(),
                  let app = NSWorkspace.shared.frontmostApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  let primaryMaxY = NSScreen.screens.first?.frame.maxY else {
                session.applySeed(pressID: pressID, windowFrameCocoa: nil, windowOriginQuartz: nil)
                return
            }
            axProbe.seed(pressID: pressID, pid: app.processIdentifier, primaryMaxY: primaryMaxY) { [weak self] id, cocoa, origin in
                self?.session.applySeed(pressID: id, windowFrameCocoa: cocoa, windowOriginQuartz: origin)
            }
            return
        }
        if let pressID = session.seededPressID {
            axProbe.pollOrigin(pressID: pressID) { [weak self] id, currentOrigin in
                guard let self, self.session.observeWindowOrigin(currentOrigin, pressID: id) else { return }
                self.evaluateZone(at: NSEvent.mouseLocation)
            }
            return
        }
        guard session.isTracking else { return }
        evaluateZone(at: mouse)
    }

    private func evaluateZone(at mouse: CGPoint) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) else {
            activeZone = nil
            preview?.orderOut(nil)
            return
        }
        let area = WindowSnapService.workArea(of: screen)
        let gaps = SnapGaps.current()
        let suppressed = suppressedSeamEdges(for: screen, area: area, at: mouse)
        let layout: SnapZonePlanner.Layout = NSEvent.modifierFlags.contains(.option) ? .thirds : .edgesAndCorners
        let previous = layout == .edgesAndCorners ? activeZone.flatMap {
            (![SnapPosition.leftThird, .centerThird, .rightThird].contains($0.position)
             && $0.frame == SnapZonePlanner.previewFrame(for: $0.position, in: area, gaps: gaps)
             && $0.frame.insetBy(dx: -8, dy: -8).contains(mouse)) ? $0 : nil
        } : nil
        guard let zone = previous ?? SnapZonePlanner.resolve(
            at: mouse, in: area, layout: layout, edgeMargin: edgeMargin, gaps: gaps, suppressed: suppressed
        ) else {
            activeZone = nil
            preview?.orderOut(nil)
            return
        }
        activeZone = zone
        show(zone)
    }

    /// MD-2: edges of this display that are seams to a neighbour *and* that the pointer is touching.
    /// Empty while `⌥` is held (the user asked for thirds explicitly) and once the dwell has elapsed,
    /// so deliberately parking the pointer on a seam still snaps.
    private func suppressedSeamEdges(for screen: NSScreen, area: CGRect, at mouse: CGPoint) -> Set<ScreenEdge> {
        guard !NSEvent.modifierFlags.contains(.option),
              let uuid = DisplayIdentity.uuidString(for: screen) else {
            seamHold = nil
            return []
        }
        let displays = DisplayIdentity.topologyDisplays()
        guard displays.count > 1 else { seamHold = nil; return [] }
        let seams = ScreenEdgeTopology.resolve(displays: displays).seamEdges(for: uuid)
        guard !seams.isEmpty else { seamHold = nil; return [] }
        let margin = max(1, edgeMargin)
        var touching: Set<ScreenEdge> = []
        if mouse.x <= area.minX + margin { touching.insert(.left) }
        if mouse.x >= area.maxX - margin { touching.insert(.right) }
        if mouse.y >= area.maxY - margin { touching.insert(.top) }
        if mouse.y <= area.minY + margin { touching.insert(.bottom) }
        let relevant = seams.intersection(touching)
        guard !relevant.isEmpty else {
            seamHold = nil
            return []
        }
        let key = relevant.map(\.rawValue).sorted().joined(separator: ",")
        let since = seamHold?.key == key ? (seamHold?.since ?? Date()) : Date()
        seamHold = (key, since)
        return Date().timeIntervalSince(since) >= SnapGaps.seamDwell ? [] : relevant
    }

    private func released() {
        let zone = session.finishPress(activeZone: activeZone)
        axProbe.clear()
        activeZone = nil
        preview?.orderOut(nil)
        guard let zone else { return }
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
