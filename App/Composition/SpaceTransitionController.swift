import AppKit
import CoreGraphics
import ScreenCaptureKit

/// One Space switch the way Spacewalk does it: freeze the picture that is on screen, let the Dock
/// switch underneath that frozen picture, then play the transition to the picture that actually
/// arrived. The menu bar, the Dock and floating panels stay live above the overlay throughout.
///
/// Ported from Spacewalk (MIT, © 2026 InsaneArts) — `Switcher.swift` + `OverlayWindow.swift`, cut down
/// to the two effects this project ships (`instant`, `fade`) and to a single screenshot per side: the
/// continuous ScreenCaptureKit stream, prediction, wallpaper compositing and finger-driven scrubbing
/// of the original are not here.
///
/// Every path that cannot build the overlay still performs the switch through `DockSwipeEventPoster`,
/// which is the same Dock gesture the system posts; the only thing lost is the chosen transition.
@MainActor
final class SpaceTransitionController {
    /// Read from the defaults at the top of every switch (`SpaceTransitionSettings`).
    private(set) var effect: SpaceTransitionEffect = .fade
    private(set) var duration: TimeInterval = SpaceTransitionSettings.defaultDuration
    var wrap = true

    /// The overlay needs the macOS 26 Dock behaviour Spacewalk measured; below that the switch is
    /// posted plain. Screen Recording draws the frozen pictures, Accessibility posts the swipe.
    static var isSupported: Bool {
        if #available(macOS 26.0, *) { return true } else { return false }
    }

    static var canCaptureScreen: Bool { CGPreflightScreenCaptureAccess() }
    static var canPostEvents: Bool { AXIsProcessTrusted() }

    private var overlay: NSPanel?
    private var switching = false

    // MARK: Switching

    func switchSpace(_ direction: SpaceSwitchDirection) {
        Task { await perform(direction) }
    }

    func perform(_ direction: SpaceSwitchDirection) async {
        guard !switching else { return }
        switching = true
        defer { switching = false }

        effect = SpaceTransitionSettings.effect()
        duration = SpaceTransitionSettings.duration()
        let screen = Self.screenUnderPointer() ?? NSScreen.main
        guard let screen,
              let plan = Self.plan(on: screen, direction: direction, wrap: wrap) else { return }

        guard effect == .fade, Self.isSupported, Self.canPostEvents, Self.canCaptureScreen,
              let before = await Self.capture(screen) else {
            DockSwipeEventPoster.post(plan.direction, steps: plan.steps)
            return
        }

        let panel = makeOverlay(on: screen, before: before)
        overlay = panel
        panel.orderFrontRegardless()
        // The frozen picture has to reach the screen before the Dock starts moving underneath it.
        CATransaction.flush()

        let posted = DockSwipeEventPoster.post(plan.direction, steps: plan.steps)
        guard posted, await waitForSpaceChange(on: screen, from: plan.fromIndex, timeout: 1.2) else {
            hideOverlay()
            return
        }

        guard let after = await Self.capture(screen), let imageView = panel.contentView?.subviews.last as? NSImageView else {
            hideOverlay()
            return
        }
        imageView.image = NSImage(cgImage: after, size: screen.frame.size)
        // An explicit context: `animator()` alone runs at AppKit's own 0.25 s, which would ignore the
        // Settings slider entirely.
        let fade = duration
        // The explicit `completionHandler: nil` picks the synchronous overload; the block-only one is
        // the async variant and would need `await`.
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = fade
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            imageView.animator().alphaValue = 1
        }, completionHandler: nil)
        try? await Task.sleep(nanoseconds: UInt64((fade + 0.05) * 1_000_000_000))
        hideOverlay()
    }

    private func hideOverlay() {
        overlay?.orderOut(nil)
        overlay = nil
    }

    // MARK: Overlay

    /// Level 2: above app windows, below the Dock, floating panels and the menu bar (Spacewalk's own
    /// measurement), on every Space, and it never takes a click.
    private func makeOverlay(on screen: NSScreen, before: CGImage) -> NSPanel {
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: 2)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.title = "KatiKati Space Transition"
        panel.setFrame(screen.frame, display: false)

        let host = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        host.wantsLayer = true
        for image in [before] {
            let view = NSImageView(frame: host.bounds)
            view.image = NSImage(cgImage: image, size: host.bounds.size)
            view.imageScaling = .scaleAxesIndependently
            view.autoresizingMask = [.width, .height]
            host.addSubview(view)
        }
        // The incoming picture sits on top at zero alpha; the fade is this one property.
        let incoming = NSImageView(frame: host.bounds)
        incoming.imageScaling = .scaleAxesIndependently
        incoming.autoresizingMask = [.width, .height]
        incoming.alphaValue = 0
        host.addSubview(incoming)
        panel.contentView = host
        return panel
    }

    // MARK: Space bookkeeping

    private static func screenUnderPointer() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
    }

    /// Desktop Spaces only, in Mission Control order, for the display `screen` is on.
    private static func plan(on screen: NSScreen, direction: SpaceSwitchDirection, wrap: Bool) -> SpaceSwitchPlan? {
        guard let uuid = ManagedSpaceLayoutReader.displayUUIDString(for: screen),
              let layout = ManagedSpaceLayoutReader.layout(forDisplayUUID: uuid) else { return nil }
        let desktops = layout.orderedSpaceIDs.filter { !layout.fullscreenSpaceIDs.contains($0) }
        guard let index = desktops.firstIndex(of: layout.currentSpaceID) else { return nil }
        return SpaceSwitchPlan.plan(currentIndex: index, spaceCount: desktops.count, direction: direction, wrap: wrap)
    }

    /// Polls the display's own layout instead of trusting the notification: with several displays the
    /// notification says nothing about which one moved.
    private func waitForSpaceChange(on screen: NSScreen, from index: Int, timeout: TimeInterval) async -> Bool {
        guard let uuid = ManagedSpaceLayoutReader.displayUUIDString(for: screen) else { return false }
        let deadline = CFAbsoluteTimeGetCurrent() + timeout
        while CFAbsoluteTimeGetCurrent() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
            guard let layout = ManagedSpaceLayoutReader.layout(forDisplayUUID: uuid) else { continue }
            let desktops = layout.orderedSpaceIDs.filter { !layout.fullscreenSpaceIDs.contains($0) }
            if let current = desktops.firstIndex(of: layout.currentSpaceID), current != index { return true }
        }
        return false
    }

    // MARK: Capture

    /// The screen as it is, minus this app's own panels — a frozen dock strip in the picture would
    /// then fade from a stale copy of itself.
    private static func capture(_ screen: NSScreen) async -> CGImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
              let display = content.displays.first(where: { $0.displayID == screen.displayID }) else { return nil }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let excluded = content.windows.filter { $0.owningApplication?.processID == ownPID }
        let config = SCStreamConfiguration()
        config.width = Int(screen.frame.width * screen.backingScaleFactor)
        config.height = Int(screen.frame.height * screen.backingScaleFactor)
        config.showsCursor = false
        return try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(display: display, excludingWindows: excluded),
            configuration: config
        )
    }
}
