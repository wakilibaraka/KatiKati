import AppKit
import Combine
import SwiftUI

private final class CommandBarPanel: NonConstrainingPanel {
    override var canBecomeKey: Bool { true }
}

/// Phase 27b: the ⌘Space command bar — a compact non-activating palette over the same app index the
/// full-screen launcher uses (kept separate, on its own shortcut). Summoned by `.commandBar`; results
/// come from the pure `CommandBarResults`; actions (launch / quit / math-copy / web) run here.
@MainActor
final class CommandBarPanelController {
    private var panel: NSPanel?
    private let indexer = LauncherIndexer()
    private let store = LauncherStore(url: LauncherStore.defaultURL)
    private let model = CommandBarModel()
    private var appsObserver: AnyCancellable?

    var isShown: Bool { panel?.isVisible ?? false }

    func toggle() { isShown ? dismiss() : show() }

    func show() {
        guard !isShown else { return }
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        model.query = ""
        model.usage = store.load().usage
        model.running = Self.runningApps()
        model.apps = indexer.apps
        model.refresh()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let size = NSSize(width: 640, height: 380)
        let f = screen.visibleFrame
        panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height - f.height * 0.12, width: size.width, height: size.height), display: true)
        panel.makeKeyAndOrderFront(nil)
        indexer.start()
        model.focusNonce += 1
    }

    func dismiss() {
        panel?.orderOut(nil)
        indexer.stop()
        model.query = ""
    }

    /// Regular (Dock) apps only: background agents and the app itself have no business in the kill list.
    static func runningApps() -> [RunningAppRef] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in
                guard let name = app.localizedName, let url = app.bundleURL else { return nil }
                return RunningAppRef(bundleID: app.bundleIdentifier ?? "", name: name, pid: app.processIdentifier, path: url.path)
            }
    }

    private func run(_ result: CommandBarResult) {
        switch result {
        case .answer(.math(_, let value)):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            dismiss()
        case .answer(.web(let query)):
            dismiss()
            if let q = LauncherQuickAction.resolve(query), case let .webSearch(url) = q { NSWorkspace.shared.open(url) }
            else if let url = URL(string: "https://duckduckgo.com/?q=" + (query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) { NSWorkspace.shared.open(url) }
        case .app(let app):
            dismiss()
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path), configuration: NSWorkspace.OpenConfiguration())
        case .quit(let ref):
            dismiss()
            confirmQuit(ref)
        }
    }

    private func confirmQuit(_ ref: RunningAppRef) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Quit App")
        alert.informativeText = ref.name
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Quit"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            NSRunningApplication(processIdentifier: ref.pid)?.terminate()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = CommandBarPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let host = NSHostingView(rootView: CommandBarView(model: model,
                                                          onRun: { [weak self] in self?.run($0) },
                                                          onClose: { [weak self] in self?.dismiss() }))
        panel.contentView = host
        appsObserver = indexer.$apps.sink { [weak self] apps in
            self?.model.apps = apps
            self?.model.refresh()
        }
        return panel
    }
}
