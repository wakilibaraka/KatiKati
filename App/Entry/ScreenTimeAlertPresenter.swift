import AppKit
import SwiftUI

/// The small floating card for a limit heads-up or a reached limit (Phase 7B-W3). Non-activating, top-centre, never
/// blocks the app underneath; a heads-up fades on its own, a reached limit waits for Snooze or OK.
@MainActor
final class ScreenTimeAlertPresenter {
    private var panel: NSPanel?
    private var autoClose: Timer?

    func show(bundleID: String, name: String, action: ScreenTimeLimitAction, controller: ScreenTimeController) {
        dismiss()
        let view = ScreenTimeAlertView(name: name, action: action,
                                       onSnooze: { [weak self] in controller.snooze(bundleID); self?.dismiss() },
                                       onDismiss: { [weak self] in
                                           if case .reached = action { controller.dismissForToday(bundleID) }
                                           self?.dismiss()
                                       })
        let host = NSHostingView(rootView: view)
        let size = CGSize(width: 380, height: 92)
        host.frame = CGRect(origin: .zero, size: size)
        guard let screen = NSScreen.main else { return }
        let top = screen.visibleFrame.maxY - size.height - 12
        let frame = CGRect(x: screen.frame.midX - size.width / 2, y: top, width: size.width, height: size.height)
        let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.contentView = host
        p.orderFrontRegardless()
        panel = p
        if case .warn = action {
            autoClose = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss() }
            }
        }
    }

    func dismiss() {
        autoClose?.invalidate()
        autoClose = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }
}

struct ScreenTimeAlertView: View {
    let name: String
    let action: ScreenTimeLimitAction
    let onSnooze: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "hourglass").font(.system(size: 24)).foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                if case .reached = action {
                    HStack {
                        Button("Snooze 5 Minutes", action: onSnooze)
                        Button("OK", action: onDismiss)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 380, height: 92)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial))
    }

    private var title: String {
        switch action {
        case .warn(let m): return String(format: String(localized: "%@: %d min left"), name, m)
        case .reached: return String(format: String(localized: "Time limit reached for %@"), name)
        }
    }
}
