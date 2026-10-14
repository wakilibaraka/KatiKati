import AppKit
import ApplicationServices
import OSLog

/// "AXChildrenChanged" — not exported as a kAX* constant; PingPlace registers the same raw string.
private let notificationChildrenChanged = "AXChildrenChanged" as CFString

/// Phase 25b/25c: notification relocation — one AXObserver on the NotificationCenter process, a
/// bounded walk of each of its windows, and a position write for a recognised banner (the PingPlace
/// technique, reimplemented; same GPL-3.0 lineage, see NOTICE). Off by default, no new permission
/// (Accessibility is already required for window management), fail-closed end to end: an unfamiliar
/// Notification Center UI shape means notifications are left exactly where they are.
@MainActor
final class NotificationMoveService: ObservableObject {
    static let shared = NotificationMoveService()
    static let enabledKey = "com.katikati.notifications.move"
    static let positionKey = "com.katikati.notifications.position"
    private static let notificationCenterBundleID = "com.apple.notificationcenterui"

    @Published private(set) var isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
    /// macOS's own default slot is top-centre.
    @Published private(set) var slot: NotificationSlot = {
        UserDefaults.standard.string(forKey: positionKey).flatMap(NotificationSlot.init(rawValue:)) ?? .topCenter
    }()

    private let log = Logger(subsystem: "com.katikati.app", category: "notifmove")
    private var observer: AXObserver?
    private var appElement: AXUIElement?
    private var observedWindows: Set<AXUIElement> = []
    /// Where each window sat before we moved it, so disabling restores macOS's placement.
    private var baselineOrigins: [AXUIElement: CGPoint] = [:]
    private var moveGuard = NotificationMoveGuard()

    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        refresh()
    }

    func setSlot(_ new: NotificationSlot) {
        guard new != slot else { return }
        slot = new
        UserDefaults.standard.set(new.rawValue, forKey: Self.positionKey)
        if isEnabled { moveAll() }
    }

    func tearDown() { stop() }

    /// Start while on, stop the instant the toggle is off (no observer, no AX traffic, idle cost zero).
    func refresh() {
        if isEnabled, observer == nil { start() } else if !isEnabled, observer != nil { stop() }
    }

    private func start() {
        guard AXIsProcessTrusted() else {
            log.warning("Notification move needs Accessibility; not starting")
            isEnabled = false
            UserDefaults.standard.set(false, forKey: Self.enabledKey)
            return
        }
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == Self.notificationCenterBundleID
        }) else {
            log.warning("NotificationCenter process not running; notifications left alone")
            return
        }
        var newObserver: AXObserver?
        guard AXObserverCreate(app.processIdentifier, Self.axCallback, &newObserver) == .success,
              let newObserver else {
            log.error("Could not create the NotificationCenter AXObserver")
            return
        }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        _ = AXUIElementSetMessagingTimeout(element, 0.5)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .commonModes)
        AXObserverAddNotification(newObserver, element, kAXWindowCreatedNotification as CFString, refcon)
        AXObserverAddNotification(newObserver, element, notificationChildrenChanged, refcon)
        observer = newObserver
        appElement = element
        refreshWindowObservers()
        moveAll()
    }

    private func stop() {
        // Dropping the observer unregisters every notification registered on it (the
        // FrontmostWindowGeometryObserver teardown rule) — no per-element remove IPC.
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil
        appElement = nil
        observedWindows.removeAll()
        restoreAll()
    }

    /// shortcut: the add/remove IPC below runs on the main thread (a banner appearing while
    /// NotificationCenter is busy could stall the dock for a beat); upgrade by moving registration
    /// to a serial queue like `FrontmostWindowGeometryObserver` if anyone feels it.
    private func refreshWindowObservers() {
        guard let observer, let appElement else { return }
        let windows = copyWindows(from: appElement)
        observedWindows.formIntersection(Set(windows))
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for window in windows where observedWindows.insert(window).inserted {
            AXObserverAddNotification(observer, window, notificationChildrenChanged, refcon)
            AXObserverAddNotification(observer, window, kAXUIElementDestroyedNotification as CFString, refcon)
        }
    }

    private func handleAXNotification() {
        refreshWindowObservers()
        moveAll()
    }

    private func moveAll() {
        guard let appElement, moveGuard.shouldMove(now: Date()) else { return }
        let windows = copyWindows(from: appElement)
        guard !windows.isEmpty else { return }
        moveGuard.noteMove(at: Date())
        windows.forEach(move)
    }

    /// One window: bounded walk for a recognised banner, then a single position write. Anything we
    /// do not positively recognise is left alone (and a window we already moved is put back).
    private func move(_ window: AXUIElement) {
        var observed = NotificationUIObservation(
            windowFrameReadable: axFrame(of: window) != nil,
            positionSettable: isSettable(window, attribute: kAXPositionAttribute as CFString)
        )
        var banner: AXUIElement?
        var queue: [AXUIElement] = [window]
        var index = 0
        while index < queue.count, observed.visitedNodes <= NotificationUICapability.maxNodes {
            let element = queue[index]
            index += 1
            observed.visitedNodes += 1
            if banner == nil,
               let subrole = axString(kAXSubroleAttribute as CFString, from: element),
               NotificationUICapability.bannerSubroles.contains(subrole) {
                banner = element
                observed.bannerSubrole = subrole
            }
            queue.append(contentsOf: children(of: element))
        }
        if let banner { observed.bannerFrameReadable = axFrame(of: banner) != nil }

        guard NotificationUICapability.evaluate(observed), let banner else {
            restore(window)
            return
        }
        guard let windowFrame = axFrame(of: window), let bannerFrame = axFrame(of: banner),
              let target = targetOrigin(windowFrame: windowFrame, bannerFrame: bannerFrame) else { return }
        // Already there → don't write, don't burn the cooldown.
        if abs(windowFrame.origin.x - target.x) < 1, abs(windowFrame.origin.y - target.y) < 1 { return }
        if baselineOrigins[window] == nil { baselineOrigins[window] = windowFrame.origin }
        setPosition(target, on: window)
    }

    private func restore(_ window: AXUIElement) {
        guard let origin = baselineOrigins.removeValue(forKey: window) else { return }
        setPosition(origin, on: window)
    }

    private func restoreAll() {
        for (window, origin) in baselineOrigins { setPosition(origin, on: window) }
        baselineOrigins.removeAll()
    }

    /// Keep the banner's offset inside its (usually full-screen) window and move the window instead.
    private func targetOrigin(windowFrame: CGRect, bannerFrame: CGRect) -> CGPoint? {
        guard let screen = screen(containing: windowFrame) else { return nil }
        let target = NotificationPlacement.frame(
            slot: slot, workArea: cgRect(fromAppKit: screen.visibleFrame), banner: bannerFrame
        )
        return CGPoint(
            x: target.minX - (bannerFrame.minX - windowFrame.minX),
            y: target.minY - (bannerFrame.minY - windowFrame.minY)
        )
    }

    private func screen(containing frame: CGRect) -> NSScreen? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { cgRect(fromAppKit: $0.frame).contains(center) } ?? NSScreen.main
    }

    /// NSScreen frames are AppKit (bottom-left origin, y up); AX/CG is top-left origin, y down,
    /// across every display — same conversion as the fullscreen snap path.
    private func cgRect(fromAppKit rect: CGRect) -> CGRect {
        let globalTopY = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        return CGRect(x: rect.minX, y: globalTopY - rect.maxY, width: rect.width, height: rect.height)
    }

    private func setPosition(_ origin: CGPoint, on element: AXUIElement) {
        var point = origin
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        let result = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
        if result == .success {
            log.info("Moved a notification banner to \(self.slot.rawValue, privacy: .public)")
        } else {
            log.warning("Could not move a notification banner (AXError \(result.rawValue, privacy: .public))")
        }
    }

    // MARK: - AX reads (type-checked before every cast: a misbehaving observed app can return
    // any CF type, and an unchecked bitcast is undefined behaviour)

    private func copyWindows(from element: AXUIElement) -> [AXUIElement] {
        guard let value = axCopy(kAXWindowsAttribute as CFString, from: element) else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        let direct = (axCopy(kAXChildrenAttribute as CFString, from: element) as? [AXUIElement]) ?? []
        let ordered = (axCopy("AXOrderedChildren" as CFString, from: element) as? [AXUIElement]) ?? []
        var seen = Set<AXUIElement>()
        return (direct + ordered).filter { seen.insert($0).inserted }
    }

    private func axString(_ attribute: CFString, from element: AXUIElement) -> String? {
        guard let value = axCopy(attribute, from: element), let text = value as? String else { return nil }
        return text
    }

    private func axFrame(of element: AXUIElement) -> CGRect? {
        guard let positionRef = axCopy(kAXPositionAttribute as CFString, from: element),
              let sizeRef = axCopy(kAXSizeAttribute as CFString, from: element),
              CFGetTypeID(positionRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }
        let position = positionRef as! AXValue
        let size = sizeRef as! AXValue
        var point = CGPoint.zero
        var sizeValue = CGSize.zero
        guard AXValueGetType(position) == .cgPoint,
              AXValueGetType(size) == .cgSize,
              AXValueGetValue(position, .cgPoint, &point),
              AXValueGetValue(size, .cgSize, &sizeValue) else { return nil }
        return CGRect(origin: point, size: sizeValue)
    }

    private func isSettable(_ element: AXUIElement, attribute: CFString) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute, &settable) == .success && settable.boolValue
    }

    private func axCopy(_ attribute: CFString, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value
    }

    private static let axCallback: AXObserverCallback = { _, _, _, refcon in
        guard let refcon else { return }
        let service = Unmanaged<NotificationMoveService>.fromOpaque(refcon).takeUnretainedValue()
        MainActor.assumeIsolated { service.handleAXNotification() }
    }
}
