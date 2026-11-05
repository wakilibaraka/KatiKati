import ApplicationServices
import Carbon.HIToolbox
import OSLog

/// Opt-in: swallows the system ⌘Tab and hands it to the window switcher. A session event tap on the main run
/// loop (same tap kind as `HyperkeyService`); needs Accessibility. Turning it off removes the tap, so the system
/// switcher works again at once.
@MainActor
final class CommandTabTakeover {
    static let enabledKey = "com.katikati.switcher.commandTab"

    /// Called with `reverse` (Shift held) on every ⌘Tab / ⌘⇧Tab press.
    var onPress: ((Bool) -> Void)?
    /// Same, for ⌘` : the switcher limited to the frontmost app's windows.
    var onPressCurrentApp: ((Bool) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let log = Logger(subsystem: "com.caye.macosdockcc.v2", category: "switcher")

    var isRunning: Bool { tap != nil }

    func setEnabled(_ on: Bool) {
        on ? start() : stop()
    }

    private func start() {
        guard tap == nil else { return }
        guard AXIsProcessTrusted() else {
            log.warning("⌘Tab takeover needs Accessibility; leaving the system switcher alone")
            return
        }
        let mask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                           options: .defaultTap, eventsOfInterest: mask,
                                           callback: commandTabCallback, userInfo: refcon) else {
            log.error("Could not create the ⌘Tab event tap")
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        tap = port; self.source = source
    }

    private func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }
}

/// Runs on the main thread (the tap source lives on the main run loop), so assuming MainActor is sound.
private func commandTabCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let service = Unmanaged<CommandTabTakeover>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { service.reenable() }
        return Unmanaged.passUnretained(event)
    }
    let flags = event.flags
    let key = event.getIntegerValueField(.keyboardEventKeycode)
    guard type == .keyDown, key == Int64(kVK_Tab) || key == Int64(kVK_ANSI_Grave),
          flags.contains(.maskCommand),
          !flags.contains(.maskAlternate), !flags.contains(.maskControl) else {
        return Unmanaged.passUnretained(event)
    }
    let reverse = flags.contains(.maskShift)
    MainActor.assumeIsolated {
        if key == Int64(kVK_Tab) { service.onPress?(reverse) } else { service.onPressCurrentApp?(reverse) }
    }
    return nil
}
