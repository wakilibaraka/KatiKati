import AppKit
import Foundation

/// RT-6's second half: ⌥ + two-finger scroll steps along the ribbon.
///
/// Opt-in and off by default. It is a passive `NSEvent` monitor, not an event tap: nothing is
/// swallowed, so the app under the pointer keeps scrolling too. That is the cost the plan accepted
/// — taking ⌥+scroll away from every tiled app is a semantic change nobody asked for — and the
/// installed row's note says it. The monitor exists only while the switch is on.
///
/// It only acts when all four of these hold: the switch is on, Option is held, the pointer is over a
/// display drawing the strip, and the window under the pointer is one the strip manages. A floating
/// window, a full-screen app or one of our own panels keeps the event to itself.
@MainActor
final class StripScrollService {
    static let shared = StripScrollService()
    static let enabledKey = "com.katikati.tiling.stripScroll"

    private var monitor: Any?
    private var gesture = StripScrollGesture()

    private init() {
        #if DEBUG
        scheduleCheckIfRequested()
        #endif
    }

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

    /// The one path both the monitor and the live check use. `point` defaults to the pointer, so the
    /// check can stand the gesture over a chosen window without moving the real cursor.
    func handle(_ event: NSEvent, at point: NSPoint = NSEvent.mouseLocation) {
        guard isEnabled else { gesture.reset(); return }
        guard event.modifierFlags.contains(.option) else { gesture.reset(); return }
        guard TilingEngine.shared.ribbonCoversPointer(at: point) else { gesture.reset(); return }
        // A wheel notch carries ~1–3 line units; treating that as points would never reach the
        // step distance. Trackpad / Magic Mouse deltas are already precise points.
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        let step = gesture.feed(
            delta: Double(event.scrollingDeltaY * scale),
            isMomentum: !event.momentumPhase.isEmpty,
            at: ProcessInfo.processInfo.systemUptime
        )
        guard let step else { return }
        TilingEngine.shared.focusStripColumn(step == .next ? 1 : -1)
    }
}

#if DEBUG
// MARK: - Live check (KATIKATI_STRIP_SCROLL_CHECK=1)

extension StripScrollService {
    /// Feeds constructed scroll events through `handle(_:at:)` — the exact method the global monitor
    /// calls — and logs the strip's focused column and camera after each case. Debug builds only,
    /// and only when the environment variable is set; nothing runs otherwise.
    private func scheduleCheckIfRequested() {
        guard ProcessInfo.processInfo.environment["KATIKATI_STRIP_SCROLL_CHECK"] != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.runCheck()
        }
    }

    private func runCheck() {
        let engine = TilingEngine.shared
        engine.setEnabled(true)
        engine.debugPauseFocusPoll = true
        // Earlier runs may have left a floated app behind; the check wants every window tiled.
        engine.setPolicy(TilingPolicy())
        let columnPoint = NSPoint(x: 400, y: 500)
        var report = "strip-scroll check | columns=\(engine.debugStripState.columns)\n"

        /// Lets the main queue run: the engine reconciles on snapshots, and a blocked queue would
        /// leave policy changes and focus polls unprocessed.
        func pause(_ seconds: TimeInterval = 0.4) {
            RunLoop.current.run(until: Date().addingTimeInterval(seconds))
        }

        func describe(_ point: NSPoint, _ label: String) {
            let cg = TilingEngine.frontmostWindowID(at: point)
            report += "point=\(label) cg=\(cg.map(String.init) ?? "nil") managed=\(engine.debugIsManaged(cg))\n"
        }

        func state() -> String { "strip=\(engine.debugStripState.column) camera=\(engine.debugStripState.camera)" }

        func record(_ name: String, expect: String, seen event: NSEvent? = nil) {
            let delta = event.map { " dy=\(String(format: "%.1f", $0.scrollingDeltaY)) precise=\($0.hasPreciseScrollingDeltas)" } ?? ""
            report += "case=\(name) \(state()) expect=\(expect)\(delta)\n"
        }

        /// Two events per swipe (60 pt of travel at 30 pt each), `repeats` swipes with a cooldown gap.
        func swipe(_ name: String, expect: String, option: Bool, dx: Int32, dy: Int32,
                   units: CGScrollEventUnit, at point: NSPoint, repeats: Int = 1) {
            var last: NSEvent?
            for _ in 0..<repeats {
                for _ in 0..<2 {
                    guard let event = Self.makeEvent(option: option, dx: dx, dy: dy, units: units) else { continue }
                    last = event
                    handle(event, at: point)
                    pause(0.05)
                }
                pause(0.32)
            }
            let gate = engine.debugGate(at: point)
            report += "gate=\(name) managed=\(gate.managed) cg=\(gate.cg) preset=\(gate.preset)\n"
            record(name, expect: expect, seen: last)
            pause()
        }

        // The first snapshot has to have tiled the windows before there is a strip to step; asking
        // for the Chain picture is the same public path the Settings grid uses.
        engine.applyQuickLayout(.chain)
        var policyWait = 0.0
        while !engine.debugGate(at: columnPoint).managed, policyWait < 6 {
            pause(0.2)
            policyWait += 0.2
        }
        report += "policy-settled=\(String(format: "%.1f", policyWait))s managed=\(engine.debugGate(at: columnPoint).managed)\n"
        var waited = 0.0
        while engine.debugStripState.columns == 0, waited < 10 {
            pause(0.2)
            waited += 0.2
        }
        report += "wait-for-strip=\(String(format: "%.1f", waited))s columns=\(engine.debugStripState.columns)\n"
        pause(0.5)
        describe(columnPoint, "column")
        record("start", expect: "start")

        swipe("option-down", expect: "start+1", option: true, dx: 0, dy: -30, units: .pixel, at: columnPoint)
        swipe("option-up", expect: "start", option: true, dx: 0, dy: 30, units: .pixel, at: columnPoint)
        swipe("no-option", expect: "start", option: false, dx: 0, dy: -30, units: .pixel, at: columnPoint)
        swipe("horizontal", expect: "start", option: true, dx: -200, dy: 0, units: .pixel, at: columnPoint)
        swipe("small-deltas", expect: "start", option: true, dx: 0, dy: -20, units: .pixel, at: columnPoint)
        swipe("wheel-notch", expect: "start+1", option: true, dx: 0, dy: -3, units: .line, at: columnPoint)
        swipe("advance-five", expect: "camera>0", option: true, dx: 0, dy: -30, units: .pixel,
              at: columnPoint, repeats: 5)
        swipe("option-up-after", expect: "-1", option: true, dx: 0, dy: 30, units: .pixel, at: columnPoint)

        // The switch itself: `setEnabled(false)` stops the monitor and the guard rejects the event.
        setEnabled(false)
        swipe("toggle-off", expect: "same", option: true, dx: 0, dy: -30, units: .pixel, at: columnPoint)
        setEnabled(true)
        pause(0.4)

        swipe("single-large-delta", expect: "+1", option: true, dx: 0, dy: -90, units: .pixel,
              at: columnPoint, repeats: 1)

        // A point with no layer-0 window at all: nothing the strip could manage under the pointer.
        let emptyPoint = NSPoint(x: 400, y: 12)
        describe(emptyPoint, "empty")
        swipe("empty-point", expect: "same", option: true, dx: 0, dy: -30, units: .pixel, at: emptyPoint)

        // The app's own Settings window: layer 0, owned by us, never part of the strip.
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        pause(1.2)
        if let window = NSApp.windows.first(where: { $0.isVisible && $0.level == .normal && $0.frame.width > 400 }) {
            let inside = NSPoint(x: window.frame.midX, y: window.frame.midY)
            describe(inside, "settings-window")
            swipe("settings-window", expect: "same", option: true, dx: 0, dy: -30, units: .pixel, at: inside)
            window.performClose(nil)
            pause(0.6)
        } else {
            report += "point=settings-window window=missing\n"
        }

        record("end", expect: "final")
        engine.debugPauseFocusPoll = false

        let url = URL(fileURLWithPath: "/tmp/strip-scroll-check.log")
        try? Data(report.utf8).write(to: url)
        print(report)
    }

    private static func makeEvent(option: Bool, dx: Int32, dy: Int32, units: CGScrollEventUnit) -> NSEvent? {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let cg = CGEvent(scrollWheelEvent2Source: source, units: units, wheelCount: 2,
                               wheel1: dy, wheel2: dx, wheel3: 0) else { return nil }
        cg.flags = option ? .maskAlternate : []
        return NSEvent(cgEvent: cg)
    }
}
#endif
