import AppKit
import CoreGraphics

/// Peek: shows the Weather and Calendar panels while the bound key is held. A quick tap leaves them open
/// (close them with Esc or the shortcut again). Only panels Peek opened itself are closed on release.
@MainActor
final class PeekController {
    private var timer: Timer?
    private var openedByPeek: [WidgetPanelController] = []

    func pressed() {
        // A second press while Peek's panels are up closes them.
        if timer == nil, !openedByPeek.isEmpty || WidgetPanelController.weather.isVisible && WidgetPanelController.calendar.isVisible {
            closeAll(); return
        }
        guard timer == nil else { return }
        openedByPeek = [WidgetPanelController.weather, WidgetPanelController.calendar].filter { !$0.isVisible }
        openedByPeek.forEach { $0.toggle() }
        guard let code = Self.boundKeyCode() else { return }   // no readable key: behaves as a toggle
        let start = ProcessInfo.processInfo.systemUptime
        let t = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(code)) else { return }
                self.timer?.invalidate(); self.timer = nil
                if PeekHold.outcome(heldFor: ProcessInfo.processInfo.systemUptime - start) == .hide { self.closeAll() }
            }
        }
        timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    private func closeAll() {
        openedByPeek.forEach { if $0.isVisible { $0.close() } }
        openedByPeek = []
    }

    private static func boundKeyCode() -> UInt16? {
        let trigger = ShortcutTrigger.parse(UserDefaults.standard.string(forKey: "com.katikati.shortcut.\(ShortcutAction.peek.rawValue)"))
        switch trigger {
        case .key(let k): return k.keyCode
        case .chord: return 49
        default: return nil
        }
    }
}
