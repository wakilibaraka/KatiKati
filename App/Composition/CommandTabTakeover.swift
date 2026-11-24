import ApplicationServices
import Carbon.HIToolbox
import OSLog
import os.lock

/// Opt-in: swallows system ⌘Tab / ⌘` and forwards to the window switcher from a dedicated tap thread.
@MainActor
final class CommandTabTakeover {
    static let enabledKey = "com.katikati.switcher.commandTab"

    var onPress: ((Bool) -> Void)?
    var onPressCurrentApp: ((Bool) -> Void)?

    private var thread: Thread?
    private let shared = CommandTabShared()
    private let log = Logger(subsystem: "com.katikati.app", category: "switcher")

    var isRunning: Bool { thread != nil }

    func setEnabled(_ on: Bool) { on ? start() : stop() }

    private func start() {
        guard thread == nil else { return }
        guard AXIsProcessTrusted() else {
            log.warning("⌘Tab takeover needs Accessibility; leaving the system switcher alone")
            return
        }
        shared.prepare(onTrigger: { [weak self] isCurrentApp, reverse in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if isCurrentApp { self?.onPressCurrentApp?(reverse) } else { self?.onPress?(reverse) }
                }
            }
        })
        let t = Thread { [shared, log] in shared.runTap(log: log) }
        t.name = "com.katikati.commandtab"
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
    }

    private func stop() {
        thread = nil
        shared.stop()
    }
}

private final class CommandTabShared: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var stopping = false
    private let recovery = EventTapRecoveryBox()
    private var onTrigger: (@Sendable (Bool, Bool) -> Void)?

    func prepare(onTrigger: @escaping @Sendable (Bool, Bool) -> Void) {
        os_unfair_lock_lock(&lock)
        stopping = false
        self.onTrigger = onTrigger
        os_unfair_lock_unlock(&lock)
        recovery.reset()
    }

    func runTap(log: Logger) {
        autoreleasepool {
            let mask: CGEventMask = 1 << CGEventType.keyDown.rawValue
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                               options: .defaultTap, eventsOfInterest: mask,
                                               callback: commandTabCallback, userInfo: refcon) else {
                log.error("Could not create the ⌘Tab event tap")
                return
            }
            let loop = CFRunLoopGetCurrent()
            let source = CFMachPortCreateRunLoopSource(nil, port, 0)
            os_unfair_lock_lock(&lock)
            let abort = stopping
            if !abort { tap = port; runLoop = loop }
            os_unfair_lock_unlock(&lock)
            guard !abort else { CFMachPortInvalidate(port); return }
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            CFRunLoopRun()
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
    }

    func stop() {
        os_unfair_lock_lock(&lock)
        stopping = true
        let port = tap, loop = runLoop
        tap = nil; runLoop = nil; onTrigger = nil
        os_unfair_lock_unlock(&lock)
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let loop { CFRunLoopStop(loop); CFRunLoopWakeUp(loop) }
        recovery.reset()
    }

    func handleDisable(log: Logger) {
        let port = withLock { tap }
        if !recovery.handleDisable(port: port) {
            log.fault("commandtab-tap-fused")
        }
    }

    func trigger(isCurrentApp: Bool, reverse: Bool) {
        withLock { onTrigger }?(isCurrentApp, reverse)
    }

    private func withLock<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }; return body()
    }
}

private func commandTabCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let shared = Unmanaged<CommandTabShared>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        shared.handleDisable(log: Logger(subsystem: "com.katikati.app", category: "switcher"))
        return Unmanaged.passUnretained(event)
    }
    let flags = event.flags, key = event.getIntegerValueField(.keyboardEventKeycode)
    guard type == .keyDown, key == Int64(kVK_Tab) || key == Int64(kVK_ANSI_Grave),
          flags.contains(.maskCommand), !flags.contains(.maskAlternate), !flags.contains(.maskControl) else {
        return Unmanaged.passUnretained(event)
    }
    shared.trigger(isCurrentApp: key != Int64(kVK_Tab), reverse: flags.contains(.maskShift))
    return nil
}
