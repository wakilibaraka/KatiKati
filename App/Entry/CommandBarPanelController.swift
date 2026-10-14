import AppKit
import Combine
import Darwin
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
    private var queryObserver: AnyCancellable?
    private var keyMonitor: Any?
    private var outsideMonitor: Any?

    var isShown: Bool { panel?.isVisible ?? false }

    func toggle() { isShown ? dismiss() : show() }

    func show() {
        guard !isShown else { return }
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        model.query = ""
        model.usage = store.load().usage
        model.running = Self.runningApps()
        model.apps = indexer.apps
        model.custom = CustomCommand.parse(UserDefaults.standard.string(forKey: CustomCommand.key) ?? "")
        model.processes = ProcessLister.list()
        model.clips = Array(ProductivityServices.shared.clipboard.history.displayOrder.prefix(50))
        model.refresh()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let size = NSSize(width: 640, height: 380)
        let f = screen.visibleFrame
        panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height - f.height * 0.12, width: size.width, height: size.height), display: true)
        panel.makeKeyAndOrderFront(nil)
        indexer.start()
        model.focusNonce += 1
        installKeyMonitor()
        installOutsideMonitor()
    }

    func dismiss() {
        panel?.orderOut(nil)
        indexer.stop()
        model.query = ""
        removeMonitors()
    }

    /// ↑/↓ move the selection, ⏎ runs it, Esc closes. A local monitor is the only way to steer the list
    /// without the text field eating the arrow keys.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isShown else { return event }
            switch event.keyCode {
            case 53: self.dismiss(); return nil              // Esc
            case 125: self.model.move(1); return nil         // ↓
            case 126: self.model.move(-1); return nil        // ↑
            case 36, 76:                                     // Return / keypad Enter
                if event.modifierFlags.contains(.command) { self.revealSelected() } else { self.runSelected() }
                return nil
            case 8 where event.modifierFlags.contains(.command):   // ⌘C
                self.copyPathSelected(); return nil
            case 51 where event.modifierFlags.contains(.command):  // ⌘⌫
                self.trashSelected(); return nil
            default: return event
            }
        }
    }

    private func installOutsideMonitor() {
        guard outsideMonitor == nil else { return }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        keyMonitor = nil
        outsideMonitor = nil
    }

    private func runSelected() {
        let index = model.selection
        guard model.results.indices.contains(index) else { return }
        run(model.results[index])
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
        case .forceQuit(let ref):
            dismiss()
            confirmForceQuit(ref)
        case .action(let macro):
            dismiss()
            runMacro(macro)
        case .generator(_, let value):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            dismiss()
        case .custom(let command):
            dismiss()
            switch command.kind {
            case .link:
                if let url = URL(string: command.target) { NSWorkspace.shared.open(url) }
            case .command:
                _ = LauncherRunner.run(.script(command.target))
            }
        case .process(let entry):
            dismiss()
            confirmKill(entry)
        case .script(let payload):
            dismiss()
            _ = LauncherRunner.run(.script(payload))
        case .shortcut(let name):
            dismiss()
            _ = LauncherRunner.run(.shortcut(name))
        case .path(let path):
            dismiss()
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        case .file(let entry):
            dismiss()
            NSWorkspace.shared.open(URL(fileURLWithPath: entry.path))
        case .clip(let entry):
            ProductivityServices.shared.clipboard.copy(entry)
            dismiss()
        case .trash(let action):
            dismiss()
            switch action {
            case .open: TrashStateStore.shared.openTrash()
            case .empty: confirmEmptyTrash()
            case .emptyWithoutConfirmation: TrashStateStore.shared.emptyTrash()
            }
        }
    }

    private func confirmEmptyTrash() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Empty Trash")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Empty Trash"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        if alert.runModal() == .alertFirstButtonReturn { TrashStateStore.shared.emptyTrash() }
    }

    /// File-row extras (Phase 29g): ⌘⏎ reveal, ⌘C copy path, ⌘⌫ trash.
    private func selectedFile() -> FileEntry? {
        guard model.results.indices.contains(model.selection),
              case .file(let entry) = model.results[model.selection] else { return nil }
        return entry
    }

    private func revealSelected() {
        guard let file = selectedFile() else { runSelected(); return }
        dismiss()
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
    }

    private func copyPathSelected() {
        guard let file = selectedFile() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(file.path, forType: .string)
    }

    private func trashSelected() {
        guard let file = selectedFile() else { return }
        NSWorkspace.shared.recycle([URL(fileURLWithPath: file.path)], completionHandler: nil)
        model.files.removeAll { $0.path == file.path }
        model.refresh()
    }

    /// `f `/`img ` run a debounced Spotlight search off the main thread (Phase 29g).
    private func searchFiles(_ query: String) {
        guard case .mode(let mode, let argument)? = CommandKeyword.parse(query), mode == .file || mode == .image else {
            model.files = []
            return
        }
        let fileQuery = FileQuery.parse(argument, imageOnly: mode == .image)
        guard fileQuery.isValid else { model.files = []; model.refresh(); return }
        Task.detached(priority: .userInitiated) { [weak self] in
            let entries = FileSearchService.search(fileQuery)
            await MainActor.run { self?.model.files = entries; self?.model.refresh() }
        }
    }

    private func confirmKill(_ entry: ProcessEntry) {
        let alert = NSAlert()
        alert.messageText = entry.name
        alert.informativeText = "PID \(entry.pid)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Kill"))
        alert.addButton(withTitle: String(localized: "Force Quit"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: kill(entry.pid, SIGTERM)
        case .alertSecondButtonReturn: kill(entry.pid, SIGKILL)
        default: break
        }
    }

    private func confirmQuit(_ ref: RunningAppRef) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Quit App")
        alert.informativeText = ref.name
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Quit"))
        alert.addButton(withTitle: String(localized: "Force Quit"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let app = NSRunningApplication(processIdentifier: ref.pid)
        switch alert.runModal() {
        case .alertFirstButtonReturn: app?.terminate()
        case .alertSecondButtonReturn: app?.forceTerminate()
        default: break
        }
    }

    private func confirmForceQuit(_ ref: RunningAppRef) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Force Quit")
        alert.informativeText = ref.name
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Force Quit"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            NSRunningApplication(processIdentifier: ref.pid)?.forceTerminate()
        }
    }

    private func runMacro(_ macro: BarMacro) {
        if macro.needsConfirm {
            let alert = NSAlert()
            alert.messageText = String(localized: "Are you sure?")
            alert.informativeText = macro.keyword
            alert.alertStyle = .warning
            alert.addButton(withTitle: String(localized: "Continue"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        BarActionService.run(macro)
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
                                                          onClose: { [weak self] in self?.dismiss() },
                                                          onRemove: { app, removal in
                                                              AppRemovalService.confirmAndPerform(bundleID: app.bundleID, name: app.name, appPath: app.path, removal: removal)
                                                          }))
        panel.contentView = host
        appsObserver = indexer.$apps.sink { [weak self] apps in
            self?.model.apps = apps
            self?.model.refresh()
        }
        queryObserver = model.$query
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] query in self?.searchFiles(query) }
        return panel
    }
}
