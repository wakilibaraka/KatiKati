import AppKit
import SwiftUI

/// W-7: shows the workspace capsule for a moment after a switch, on the display that switched.
///
/// Same panel discipline as the chip panel: a borderless non-activating panel that joins every
/// Space, ignores the mouse and never takes focus — a status readout must not interrupt the switch
/// it is reporting. It exists only while it is shown, so it costs nothing when idle.
@MainActor
final class WorkspaceHUDController {
    static let shared = WorkspaceHUDController()

    /// On by default, like the rest of the app's readouts; turned off in Settings › Tiling.
    static let enabledKey = "com.katikati.workspace.hud"
    /// Long enough to read a number, short enough not to sit in front of anything.
    private static let visibleDuration: TimeInterval = 1.1

    private var panel: NSPanel?
    private var hosting: NSHostingView<WorkspaceHUDView>?
    private var hideWork: DispatchWorkItem?

    private init() {}

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// Announces `active` on `screen`. Called from the engine after a switch settles.
    func show(workspaces: [WorkspaceID], active: WorkspaceID, on screen: NSScreen) {
        guard isEnabled, !workspaces.isEmpty else { return }
        guard let panel = ensurePanel() else { return }

        guard let hosting else { return }
        hosting.rootView = WorkspaceHUDView(workspaces: workspaces, active: active)
        panel.setContentSize(hosting.fittingSize)

        let size = panel.frame.size
        let visible = screen.visibleFrame
        // Bottom-centre, clear of the Dock: the same corner the bar reads from, without covering a
        // window's title bar.
        let origin = CGPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + 24
        )
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleDuration, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> NSPanel? {
        if let panel { return panel }
        let view = WorkspaceHUDView(workspaces: [], active: .numbered(1))
        let hosting = NSHostingView(rootView: view)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        self.panel = panel
        self.hosting = hosting
        return panel
    }
}
