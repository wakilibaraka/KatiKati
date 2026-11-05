import AppKit
import SwiftUI

/// Optional accent outline around the focused window: a click-through panel that follows the front app's
/// topmost normal window. Off by default.
// shortcut: 4 Hz poll of the window list instead of AX move/resize events; switch to the geometry observer if the lag shows.
@MainActor
final class WindowBorderController {
    static let enabledKey = "com.katikati.border.enabled"

    private var panel: NSPanel?
    private var timer: Timer?
    private var defaultsObserver: NSObjectProtocol?

    func start() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.apply() }
        }
        apply()
    }

    private func apply() {
        let on = UserDefaults.standard.bool(forKey: Self.enabledKey)
        if on, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        } else if !on {
            timer?.invalidate(); timer = nil
            panel?.orderOut(nil); panel = nil
        }
    }

    private func tick() {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              pid != ProcessInfo.processInfo.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let info = list.first(where: { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid
                  && ($0[kCGWindowLayer as String] as? Int) == 0 }),
              let dict = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: dict),
              bounds.width > 80, bounds.height > 60,
              let primary = NSScreen.screens.first else {
            panel?.orderOut(nil)
            return
        }
        // CG space is top-left origin on the primary display; AppKit is bottom-left.
        let frame = NSRect(x: bounds.minX, y: primary.frame.height - bounds.maxY, width: bounds.width, height: bounds.height)
            .insetBy(dx: -2, dy: -2)
        if let panel {
            if panel.frame != frame { panel.setFrame(frame, display: true) }
            if !panel.isVisible { panel.orderFrontRegardless() }
            return
        }
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = PanelCollectionBehavior.standard
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView:
            RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 3))
        panel.orderFrontRegardless()
        self.panel = panel
    }
}
