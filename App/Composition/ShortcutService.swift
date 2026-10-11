import AppKit
import Carbon.HIToolbox
import OSLog

/// Turns the shortcut bindings (Phase 7B-V4) into live triggers: Carbon hot keys for Space chords, and an event
/// monitor for modifier double-taps. The monitors exist only for the bindings that are on; `apply` is idempotent.
@MainActor
final class ShortcutService {
    var onAction: (ShortcutAction) -> Void = { _ in }
    private var hotKeys: [ShortcutAction: GlobalHotKeyMonitor] = [:]
    private var tapActions: [ShortcutTapKey: [ShortcutAction]] = [:]
    private var detector = ModifierDoubleTapDetector()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var applied: [ShortcutAction: ShortcutTrigger]?
    private let log = Logger(subsystem: "com.caye.macosdockcc.v2", category: "hotkey")

    func apply(_ bindings: [ShortcutAction: ShortcutTrigger]) {
        guard bindings != applied else { return }
        applied = bindings
        hotKeys.values.forEach { $0.stop() }
        hotKeys = [:]
        removeEventMonitors()
        tapActions = [:]
        detector.reset()
        for action in ShortcutAction.allCases {
            switch bindings[action] ?? .off {
            case .off: break
            case .chord(let chord):
                let monitor = GlobalHotKeyMonitor(shortcut: Self.shortcut(for: action, chord: chord)) { [weak self] in self?.onAction(action) }
                if monitor.start() == .registered { hotKeys[action] = monitor } else {
                    log.warning("Shortcut \(chord.glyphs, privacy: .public) for \(action.rawValue, privacy: .public) could not be registered")
                }
            case .doubleTap(let key):
                tapActions[key, default: []].append(action)
            }
        }
        if !tapActions.isEmpty { installEventMonitors() }
    }

    func tearDown() {
        hotKeys.values.forEach { $0.stop() }
        hotKeys = [:]
        removeEventMonitors()
        applied = nil
    }

    private static func shortcut(for action: ShortcutAction, chord: ShortcutChord) -> GlobalHotKeyShortcut {
        var mods: UInt32 = 0
        if chord.usesControl { mods |= UInt32(controlKey) }
        if chord.usesOption { mods |= UInt32(optionKey) }
        if chord.usesShift { mods |= UInt32(shiftKey) }
        return GlobalHotKeyShortcut(keyCode: UInt32(kVK_Space), carbonModifiers: mods, displayGlyphs: chord.glyphs,
                                    signature: 0x5467_4567, id: action.hotKeyID)
    }

    private func installEventMonitors() {
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            let kind = event.type, code = event.keyCode, flags = event.modifierFlags, time = event.timestamp
            Task { @MainActor in self?.handle(kind: kind, keyCode: code, flags: flags, time: time) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(kind: event.type, keyCode: event.keyCode, flags: event.modifierFlags, time: event.timestamp)
            return event
        }
    }

    private func removeEventMonitors() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handle(kind: NSEvent.EventType, keyCode: UInt16, flags: NSEvent.ModifierFlags, time: TimeInterval) {
        guard kind == .flagsChanged else { detector.reset(); return }
        guard let key = ShortcutTapKey(keyCode: keyCode) else { detector.reset(); return }
        let family: NSEvent.ModifierFlags = {
            switch key {
            case .leftCommand, .rightCommand: return .command
            case .leftControl, .rightControl: return .control
            case .leftOption, .rightOption: return .option
            }
        }()
        let active = flags.intersection([.command, .control, .option, .shift])
        let isDown = active.contains(family)
        // A chord such as ⌘⇧ is not a tap.
        if isDown, active != family { detector.reset(); return }
        guard let fired = detector.modifierChanged(keyCode: keyCode, isDown: isDown, time: time),
              let actions = tapActions[fired] else { return }
        actions.forEach(onAction)
    }
}
