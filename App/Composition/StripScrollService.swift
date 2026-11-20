import AppKit
import Foundation

/// RT-6's second half: ⌥ + two-finger scroll steps along the ribbon.
///
/// Opt-in and off by default. It is a passive `NSEvent` monitor, not an event tap: nothing is
/// swallowed, so the app under the pointer keeps scrolling too. That is the cost the plan accepted
/// — taking ⌥+scroll away from every tiled app is a semantic change nobody asked for — and the
/// installed row's note says it. The monitor exists only while the switch is on.
@MainActor
final class StripScrollService {
    static let shared = StripScrollService()
    static let enabledKey = "com.katikati.tiling.stripScroll"

    private var monitor: Any?
    private var gesture = StripScrollGesture()

    private init() {}

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    /// Called once at launch: the switch's own row handles every change after that.
    func startIfEnabled() {
        guard isEnabled else { return }
        start()
    }

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        on ? start() : stop()
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        gesture.reset()
    }

    private func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
    }

    private func handle(_ event: NSEvent) {
        guard event.modifierFlags.contains(.option) else { gesture.reset(); return }
        // Only over a display that is actually drawing the strip: elsewhere the gesture stays inert
        // instead of scrolling a strip the pointer cannot see.
        guard TilingEngine.shared.ribbonCoversPointer else { gesture.reset(); return }
        let step = gesture.feed(
            horizontal: event.scrollingDeltaX,
            vertical: event.scrollingDeltaY,
            isMomentum: !event.momentumPhase.isEmpty,
            at: event.timestamp
        )
        guard let step else { return }
        TilingEngine.shared.focusStripColumn(step == .next ? 1 : -1)
    }
}
