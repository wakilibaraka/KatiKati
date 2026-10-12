import AppKit
import Combine
import SwiftUI

// Phase 8b-4B — the Live Island's in-app event feed ("something just happened" toast).
//
// `LiveEventDetector` (Core, pure) decides *what* changed; this app-layer file decides *how* to tell
// the user. The owner split 8b-4's feed into two permission tiers — an in-app toast (no permission,
// default ON) and OS Notification Center banners (a TCC surface, opt-in, default OFF). This file is
// the first tier; the second lands in `LiveEventBannerPoster.swift` (8b-4C).
//
// Two design decisions worth the ink:
//
//  - **One centre for the whole app** (owned by `AppDelegate`). Each island keeps its own rendering
//    feed (8b-3), and on a multi-display setup there are N of those — so per-island event detection
//    would fire the same toast N times. The centre owns its own feed and runs the detector exactly
//    once, app-wide.
//  - **Event-driven, not polling.** It subscribes to the source controllers' `objectWillChange`
//    (`LiveActivityFeed.sourceChanges()`) rather than running a timer, so the feed costs zero idle
//    CPU (§4 idle-CPU gate). `objectWillChange` is *will*-change, so the value is read one run-loop
//    turn later via `.receive(on: DispatchQueue.main)`.
//
// The toast itself reuses the established `ShortcutToastPresenter` shape: a borderless,
// non-activating, click-through `NSPanel` that fades out on its own. `DOCK_LIVE_EVENTS=0` is the
// field rollback path and silences the toast without touching the island's own rendering.

/// Somewhere an event can be shown (8b-5). The dock registers the bottom toast; the notch registers
/// its own expansion in 8b-7. The centre never knows which concrete surface it is talking to.
@MainActor
protocol LiveEventSink: AnyObject {
    func show(_ event: LiveEvent)
}

extension LiveEventToastPresenter: LiveEventSink {}

@MainActor
final class LiveEventCenter {
    private let feed: LiveActivityFeed
    private let toast = LiveEventToastPresenter()

    /// Registered surfaces. A surface with no sink is simply not usable (e.g. the notch before it exists).
    private var sinks: [LiveSurface: LiveEventSink] = [:]
    /// Per-surface "is this switched on right now" and the user's route, read at event time so a
    /// Settings change takes effect immediately. Defaults keep the pre-8b-5 behaviour (dock only).
    var isSurfaceEnabled: (LiveSurface) -> Bool = { $0 == .dock }
    var route: () -> LiveEventRoute = { .automatic }
    /// Opt-in OS banner tier (8b-4c). Default off; the poster also asks for permission lazily.
    var osBannersEnabled: () -> Bool = { false }
    private let banners = LiveEventBannerPoster()
    private var dispatcher = LiveEventDispatcher()

    /// The last snapshot, so the next change can be diffed against it. Seeded at `start()` with the
    /// *current* state, so the first event is the user's first action — not a burst of "events" for
    /// whatever happened to be running when the app launched.
    private var previous = LiveActivitySources.idle
    private var cancellables = Set<AnyCancellable>()

    /// `feed` is injected for tests. It is constructed **inside** the initializer rather than as a
    /// default argument: a default argument is evaluated in a nonisolated context, and
    /// `LiveActivityFeed` is `@MainActor`.
    init(feed: LiveActivityFeed? = nil) {
        self.feed = feed ?? LiveActivityFeed.shared
        sinks[.dock] = toast
    }

    /// Register (or replace) the sink for a surface. Used by the notch in 8b-7.
    func register(sink: LiveEventSink, for surface: LiveSurface) {
        sinks[surface] = sink
    }

    /// Begin observing. Idempotent (a second call is a no-op), so it is safe to call from launch.
    func start() {
        guard cancellables.isEmpty else { return }
        previous = feed.sources(at: Date())
        feed.sourceChanges()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.evaluate() }
            .store(in: &cancellables)
    }

    /// Diff the current sources against the last snapshot and surface what changed. Split out from
    /// `start()` so it can be driven directly (tests / a forced refresh).
    func evaluate() {
        let current = feed.sources(at: Date())
        let events = LiveEventDetector.events(from: previous, to: current)
        previous = current

        // The detector returns events most-alert-worthy first; the toast shows the top one only —
        // a second toast landing on top of the first is worse than dropping it.
        guard let event = events.first else { return }
        guard DebugSwitch.liveEvents.isEnabled() else { return }
        deliver(event, now: Date())
    }

    /// Route one event to the user's chosen surface(s): usable = registered + enabled, then
    /// `LiveSurfaceRouting` picks the target(s) (exactly one unless the user chose Both), and the
    /// deduper drops a repeat inside the cooldown. The OS banner (8b-4c) will hang off the same
    /// `shownOn` set.
    @discardableResult
    func deliver(_ event: LiveEvent, now: Date) -> Set<LiveSurface> {
        let usable = Set(sinks.keys.filter { isSurfaceEnabled($0) })
        let plan = dispatcher.plan(for: event, route: route(), usable: usable, bannersEnabled: osBannersEnabled(), now: now)
        for surface in plan.surfaces { sinks[surface]?.show(event) }
        // Banner only as a fallback for "no in-app surface can show it" — never doubles a toast, and a
        // cooldown-dropped repeat of a shown event is not re-bannered.
        if plan.postBanner { banners.post(event) }
        return plan.surfaces
    }
}

// MARK: - The toast

/// A small capsule near the bottom of the active screen: click-through, non-activating, gone after a
/// couple of seconds — the same shape as `ShortcutToastPresenter`, so the two feel like one family.
@MainActor
final class LiveEventToastPresenter {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ event: LiveEvent) {
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main
        guard let screen else { return }
        let host = NSHostingView(rootView: LiveEventToastView(presentation: LiveEventPresentation(event)))
        let size = host.fittingSize
        let panel = self.panel ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            p.level = .statusBar
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.ignoresMouseEvents = true
            p.isReleasedWhenClosed = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            return p
        }()
        self.panel = panel
        panel.contentView = host
        let f = screen.visibleFrame
        panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.minY + f.height * 0.16, width: size.width, height: size.height), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak panel] in
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel?.animator().alphaValue = 0 }, completionHandler: { panel?.orderOut(nil) })
        }
        hideWork = work
        // A beat longer than the shortcut toast: these carry a headline plus a reading.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: work)
    }
}

private struct LiveEventToastView: View {
    let presentation: LiveEventPresentation

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: presentation.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: presentation.headline)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if let detail = presentation.detail, !detail.isEmpty {
                    Text(verbatim: detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .foregroundStyle(.white)
        .background(Capsule().fill(Color.black.opacity(0.8)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        .padding(12)
    }
}
