import AppKit
import Combine
import SwiftUI

/// Phase 8b-7 — owns the notch panel. KatiKati's adapter around boring.notch's vendored
/// `BoringNotchWindow` (Vendor/boring.notch): window recipe is upstream's, everything else is ours.
///
/// Lifecycle: built only when the notch island is switched on, torn down when it goes off (so a user
/// who never enables it pays nothing). While shown it holds the shared `LiveActivityFeed` tick and is a
/// `LiveEventSink`, so the event router can send events here. Fullscreen: the panel deliberately drops
/// `.fullScreenAuxiliary`, so it does not appear over a fullscreen app's space.
@MainActor
final class NotchPanelController: LiveEventSink {
    private var panel: BoringNotchWindow?
    private let model = NotchModel()
    private var cancellables = Set<AnyCancellable>()
    private var eventWork: DispatchWorkItem?
    private var metrics = NotchMetrics(closedSize: CGSize(width: NotchGeometry.fallbackNotchWidth, height: NotchGeometry.fallbackHeight), hasHardwareNotch: false)
    private var holdsFeed = false
    var theme: () -> NowPlayingTheme = { .auto }

    /// Whether the panel exists and is on screen — the router's "usable" test for the notch.
    var isUsable: Bool { panel?.isVisible ?? false }

    // MARK: lifecycle

    func setEnabled(_ enabled: Bool) {
        enabled ? show() : hide()
    }

    private func show() {
        guard panel == nil, let screen = targetScreen() else { return }
        metrics = Self.metrics(for: screen)
        let window = BoringNotchWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.collectionBehavior.remove(.fullScreenAuxiliary)
        window.contentView = Self.container(for: NotchIslandView(model: model, metrics: metrics, theme: theme()))
        panel = window
        LiveActivityFeed.shared.retain()
        holdsFeed = true
        applyFrame(on: screen, animated: false)
        window.orderFrontRegardless()

        model.$isHovering.removeDuplicates().sink { [weak self] _ in self?.reframe() }.store(in: &cancellables)
        model.$event.map { $0 != nil }.removeDuplicates().sink { [weak self] _ in self?.reframe() }.store(in: &cancellables)
        LiveActivityFeed.shared.$activity.map(\.kind).removeDuplicates().sink { [weak self] _ in self?.reframe() }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.screensChanged() }.store(in: &cancellables)
    }

    private func hide() {
        cancellables.removeAll()
        eventWork?.cancel(); eventWork = nil
        model.event = nil; model.isHovering = false
        panel?.orderOut(nil)
        panel = nil
        if holdsFeed { LiveActivityFeed.shared.release(); holdsFeed = false }
    }

    // MARK: LiveEventSink

    func show(_ event: LiveEvent) {
        guard panel != nil else { return }
        model.event = LiveEventPresentation(event)
        eventWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.model.event = nil }
        eventWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    // MARK: geometry

    private func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    private static func metrics(for screen: NSScreen) -> NotchMetrics {
        NotchGeometry.metrics(
            screenWidth: screen.frame.width,
            safeAreaTop: screen.safeAreaInsets.top,
            auxLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxRightWidth: screen.auxiliaryTopRightArea?.width,
            menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY)
    }

    private func screensChanged() {
        guard panel != nil, let screen = targetScreen() else { return }
        metrics = Self.metrics(for: screen)
        panel?.contentView = Self.container(for: NotchIslandView(model: model, metrics: metrics, theme: theme()))
        applyFrame(on: screen, animated: false)
    }

    /// The hosting view lives inside a plain autoresizing container so SwiftUI's intrinsic size can never
    /// drive the panel (that fed back into window sizing during an update-constraints pass and crashed).
    private static func container<V: View>(for view: V) -> NSView {
        let container = NSView(frame: .zero)
        let host = NSHostingView(rootView: view)
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        return container
    }

    /// Deferred one turn: the triggers (hover, event, activity change) fire from inside SwiftUI's own
    /// update pass, and resizing the window re-entrantly from there is what AppKit objects to.
    private func reframe() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel != nil, let screen = self.targetScreen() else { return }
            self.applyFrame(on: screen, animated: true)
        }
    }

    private func applyFrame(on screen: NSScreen, animated: Bool) {
        let showsActivity = LiveActivityFeed.shared.activity.kind != .clock
        let size = model.isExpanded ? NotchGeometry.openSize : NotchGeometry.closedCapsuleSize(metrics, showsActivity: showsActivity)
        panel?.setFrame(NotchGeometry.panelFrame(size: size, in: screen.frame), display: true, animate: animated)
    }
}
