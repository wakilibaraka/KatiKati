import AppKit
import SwiftUI

/// 57c: a small glass orb that floats over other windows, can be dragged anywhere and opens the launcher on a click.
/// Opt-in (Settings → Launcher → Floating Orb, default off), stays where it was dropped, and never takes focus.
@MainActor
final class LauncherOrbController {
    static let positionKey = "com.katikati.launcher.orb.position"

    private var panel: NSPanel?
    private let hit = OrbHitView()
    private var shownStyle: LauncherIconStyle?

    /// The launcher's own toggle, so the orb sums the launcher up instead of becoming a second one.
    var onTap: () -> Void = {}
    /// Read at each show; the orb draws the same glyph as the dock's launcher button.
    var iconStyle: () -> LauncherIconStyle = { .liquidBento }

    var isShown: Bool { panel?.isVisible ?? false }

    func show() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let style = iconStyle()
        if shownStyle != style {
            panel.contentView = makeContent(style: style)
            shownStyle = style
        }
        let origin = LauncherOrbPlacement.clamp(savedOrigin() ?? LauncherOrbPlacement.defaultOrigin(in: screen.visibleFrame),
                                                in: screen.visibleFrame)
        panel.setFrame(NSRect(origin: origin, size: CGSize(width: LauncherOrbPlacement.size, height: LauncherOrbPlacement.size)),
                       display: true)
        panel.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: LauncherOrbPlacement.size, height: LauncherOrbPlacement.size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hit.onTap = { [weak self] in self?.onTap() }
        hit.onDragEnd = { [weak self] in self?.savePosition() }
        return panel
    }

    private func makeContent(style: LauncherIconStyle) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: LauncherOrbPlacement.size, height: LauncherOrbPlacement.size))
        let orb = NSHostingView(rootView: LauncherOrbView(style: style))
        orb.frame = container.bounds
        orb.autoresizingMask = [.width, .height]
        hit.frame = container.bounds
        hit.autoresizingMask = [.width, .height]
        container.addSubview(orb)
        container.addSubview(hit)
        return container
    }

    private func savedOrigin() -> CGPoint? {
        guard let raw = UserDefaults.standard.string(forKey: Self.positionKey) else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return CGPoint(x: parts[0], y: parts[1])
    }

    private func savePosition() {
        guard let origin = panel?.frame.origin else { return }
        UserDefaults.standard.set("\(origin.x),\(origin.y)", forKey: Self.positionKey)
    }
}

/// Drag moves the panel, a press without travel opens the launcher — the same distinction the dock's chips make.
private final class OrbHitView: NSView {
    var onTap: () -> Void = {}
    var onDragEnd: () -> Void = {}

    private var startMouse = NSPoint.zero
    private var startOrigin = NSPoint.zero
    private var dragging = false

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func mouseDown(with event: NSEvent) {
        startMouse = NSEvent.mouseLocation
        startOrigin = window?.frame.origin ?? .zero
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let delta = CGPoint(x: NSEvent.mouseLocation.x - startMouse.x, y: NSEvent.mouseLocation.y - startMouse.y)
        if !dragging, !LauncherOrbPlacement.isClick(travel: delta) { dragging = true }
        guard dragging else { return }
        window.setFrameOrigin(NSPoint(x: startOrigin.x + delta.x, y: startOrigin.y + delta.y))
    }

    override func mouseUp(with event: NSEvent) {
        if dragging { onDragEnd() } else { onTap() }
    }

    // VoiceOver: the orb is one button and has no text of its own.
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { String(localized: "Launcher") }
    override func accessibilityPerformPress() -> Bool { onTap(); return true }
}

private struct LauncherOrbView: View {
    let style: LauncherIconStyle

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().strokeBorder(Color.white.opacity(0.30), lineWidth: 1)
            LauncherIconView(style: style, size: 30)
        }
        .frame(width: LauncherOrbPlacement.size, height: LauncherOrbPlacement.size)
        .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
        .accessibilityHidden(true)
    }
}
