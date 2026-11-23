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
    private var isLoadingProcesses = false
    private var isLoadingBookmarks = false
    private var lastProcessListTime: Date?
    private var fileSearchTask: Task<Void, Never>?
    /// Port plan #3: the app whose menus `m ` searches, frozen when the bar opens (the bar is a
    /// non-activating panel, so this is still the user's app). Activation never retargets.
    private var menuTarget: NSRunningApplication?
    private var menuLoadTask: Task<Void, Never>?
    private var menuLoaded = false
    /// Port plan #4: set by AppDelegate; nil until profiles are wired, in which case `profile ` lists nothing.
    var barProfiles: BarProfileService?
    /// `define <word>`: opens the dictionary panel (wired by `AppDelegate`).
    var onDefine: ((String) -> Void)?

    var isShown: Bool { panel?.isVisible ?? false }

    func toggle() { isShown ? dismiss() : show() }

    /// Copies the snippet and, once the bar has handed focus back, sends ⌘V (needs Accessibility; without it
    /// the text is simply on the clipboard).
    private func pasteSnippet(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        guard AXIsProcessTrusted() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard let source = CGEventSource(stateID: .combinedSessionState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return }
            down.flags = .maskCommand; up.flags = .maskCommand
            down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        }
    }

    func show() { show(prefill: "") }

    /// Opens the bar with the query already in the field (used by the Desktop Search pill).
    func show(prefill: String) {
        guard !isShown else {
            if !prefill.isEmpty { model.query = prefill }
            return
        }
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        model.query = ""
        let front = NSWorkspace.shared.frontmostApplication
        menuTarget = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        menuLoaded = false
        model.menuItems = []
        model.usage = store.load().usage
        model.running = Self.runningApps()
        indexer.start()
        model.apps = indexer.apps
        model.custom = CustomCommand.parse(UserDefaults.standard.string(forKey: CustomCommand.key) ?? "")
            + CustomCommand.parseSnippets(UserDefaults.standard.string(forKey: CustomCommand.snippetsKey) ?? "")
        model.quicklinks = Quicklink.parse(UserDefaults.standard.string(forKey: Quicklink.key) ?? "")
        model.clips = Array(ProductivityServices.shared.clipboard.history.displayOrder.prefix(50))
        model.refresh(resetSelection: true)
        FileIndexService.shared.prepare()
        if model.processes.isEmpty {
            loadProcessesAsync()
        }
        if model.bookmarks.isEmpty {
            loadBookmarksAsync()
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let sizePreset = CommandBarSizePreset(rawValue: UserDefaults.standard.string(forKey: "com.katikati.commandbar.size") ?? "") ?? .standard
        let positionPreset = CommandBarPositionPreset(rawValue: UserDefaults.standard.string(forKey: "com.katikati.commandbar.position") ?? "") ?? .upperThird
        let size = NSSize(width: sizePreset.size.width, height: sizePreset.size.height)
        let f = screen.visibleFrame
        let y = positionPreset == .center
            ? f.midY - size.height / 2
            : f.maxY - size.height - f.height * 0.12
        panel.setFrame(NSRect(x: f.midX - size.width / 2, y: y, width: size.width, height: size.height), display: true)
        panel.makeKeyAndOrderFront(nil)
        model.focusNonce += 1
        if !prefill.isEmpty { model.query = prefill }
        installKeyMonitor()
        installOutsideMonitor()
    }

    func dismiss() {
        panel?.orderOut(nil)
        indexer.stop()
        fileSearchTask?.cancel()
        fileSearchTask = nil
        menuLoadTask?.cancel()
        menuLoadTask = nil
        model.query = ""
        removeMonitors()
    }

    /// ↑/↓ move the selection, ⏎ runs it, Esc closes. A local monitor is the only way to steer the list
    /// without the text field eating the arrow keys.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isShown else { return event }

            // ⌘1–⌘9 Quick-Run
            let numberKeyMap: [UInt16: Int] = [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8]
            if event.modifierFlags.contains(.command), let idx = numberKeyMap[event.keyCode], self.model.results.indices.contains(idx) {
                self.run(self.model.results[idx])
                return nil
            }

            switch event.keyCode {
            case 53: // Esc
                if self.model.isActionPanelPresented {
                    self.model.isActionPanelPresented = false
                    return nil
                }
                self.dismiss()
                return nil
            case 40 where event.modifierFlags.contains(.command): // ⌘K Action Panel Toggle
                self.model.isActionPanelPresented.toggle()
                self.model.actionSelection = 0
                return nil
            case 16 where event.modifierFlags.contains(.command): // ⌘Y Quick Look
                return self.quickLookSelected() ? nil : event
            case 125: // ↓
                if self.model.isActionPanelPresented {
                    let count = self.model.currentActions.count
                    if count > 0 { self.model.actionSelection = (self.model.actionSelection + 1) % count }
                    return nil
                }
                self.model.move(1)
                return nil
            case 126: // ↑
                if self.model.isActionPanelPresented {
                    let count = self.model.currentActions.count
                    if count > 0 { self.model.actionSelection = (self.model.actionSelection - 1 + count) % count }
                    return nil
                }
                self.model.move(-1)
                return nil
            case 36, 76: // Return / keypad Enter
                if self.model.isActionPanelPresented {
                    let actions = self.model.currentActions
                    if actions.indices.contains(self.model.actionSelection) {
                        self.performAction(actions[self.model.actionSelection])
                    }
                    return nil
                }
                if event.modifierFlags.contains(.command) { self.revealSelected() } else { self.runSelected() }
                return nil
            case 8 where event.modifierFlags.contains(.command): // ⌘C Universal Copy
                self.universalCopySelected()
                return nil
            case 51 where event.modifierFlags.contains(.command): // ⌘⌫ Trash
                self.trashSelected()
                return nil
            case 48: // Tab Mode Expansion
                self.tabExpandMode()
                return nil
            default:
                return event
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
            var state = store.load()
            LauncherAppIndex.recordLaunch(&state.usage, bundleID: app.bundleID, at: Date())
            try? store.save(state)
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
            case .snippet:
                pasteSnippet(command.target)
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
        case .emoji(let entry):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.char, forType: .string)
            dismiss()
        case .bookmark(let bookmark):
            dismiss()
            if let url = URL(string: bookmark.url) { NSWorkspace.shared.open(url) }
        case .event:
            dismiss()
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
        case .profile(let summary):
            dismiss()
            barProfiles?.apply(id: summary.id)
        case .define(let word):
            dismiss()
            onDefine?(word)
        case .saveProfile(let name):
            dismiss()
            barProfiles?.saveCurrent(named: name)
        case .menuItem(let entry):
            let pid = menuTarget?.processIdentifier
            dismiss()
            guard let pid, entry.isEnabled else { NSSound.beep(); return }
            // After the panel is gone, so the item's own window or sheet opens over the app, not under the bar.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if !AppMenuSearchReader.press(path: entry.path, pid: pid) { NSSound.beep() }
            }
        case .quicklink(let link, let argument):
            let clip = NSPasteboard.general.string(forType: .string) ?? ""
            let values = QuicklinkValues(query: argument, clipboard: clip, selection: "", date: Date())
            dismiss()
            if let url = QuicklinkTemplate.url(link.template, values: values) {
                if let bundleID = link.openWith,
                   let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
                } else {
                    NSWorkspace.shared.open(url)
                }
            }
        case .searchFilesFallback(let term):
            model.query = "f \(term)"
        case .askAI(let term):
            dismiss()
            if let url = URL(string: "https://duckduckgo.com/?q=" + (("! " + term).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) {
                NSWorkspace.shared.open(url)
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
        let index = model.selection
        guard model.results.indices.contains(index) else { runSelected(); return }
        let path: String?
        switch model.results[index] {
        case .file(let entry): path = entry.path
        case .app(let app): path = app.path
        default: path = nil
        }
        if let path {
            dismiss()
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } else {
            runSelected()
        }
    }

    private func universalCopySelected() {
        let index = model.selection
        guard model.results.indices.contains(index) else { return }
        let result = model.results[index]
        let str: String?
        switch result {
        case .file(let entry): str = entry.path
        case .app(let app): str = app.path
        case .clip(let entry): str = entry.text
        case .answer(let answer):
            switch answer {
            case .math(_, let value): str = value
            case .web(let query): str = query
            }
        case .generator(_, let value): str = value
        case .custom(let cmd): str = cmd.target
        case .script(let p): str = p
        case .shortcut(let s): str = s
        case .path(let p): str = p
        case .bookmark(let b): str = b.url
        default: str = nil
        }
        if let str, !str.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(str, forType: .string)
        }
    }

    private func tabExpandMode() {
        let q = model.query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return }
        if q == "g" || q == "calc" {
            model.query = q + " "
        } else if let mode = CommandBarMode.allCases.first(where: { $0.keywords.contains(q) }) {
            model.query = mode.keywords[0] + " "
        }
    }

    private func performAction(_ action: CommandBarActionItem) {
        model.isActionPanelPresented = false
        let index = model.selection
        guard model.results.indices.contains(index) else { return }
        let result = model.results[index]

        switch action.kind {
        case .open, .runAction:
            run(result)
        case .revealInFinder:
            revealSelected()
        case .quickLook:
            _ = quickLookSelected()
        case .copyPath, .copyValue:
            universalCopySelected()
        case .copyBundleID:
            if case .app(let app) = result {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(app.bundleID, forType: .string)
            }
        case .uninstallApp:
            if case .app(let app) = result {
                dismiss()
                AppRemovalService.confirmAndPerform(bundleID: app.bundleID, name: app.name, appPath: app.path, removal: .uninstall)
            }
        case .deleteAppData:
            if case .app(let app) = result {
                dismiss()
                AppRemovalService.confirmAndPerform(bundleID: app.bundleID, name: app.name, appPath: app.path, removal: .deleteData)
            }
        case .moveToTrash, .deleteEntry:
            trashSelected()
        case .pasteDirectly:
            if case .clip(let entry) = result {
                dismiss()
                pasteSnippet(entry.text)
            }
        case .killProcess:
            if case .process(let entry) = result {
                dismiss()
                confirmKill(entry)
            }
        case .forceKillProcess:
            if case .process(let entry) = result {
                dismiss()
                kill(pid_t(entry.pid), SIGKILL)
            }
        }
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

    /// Space → Quick Look. `qlmanage -p` shows the panel out-of-process, so it works even though the bar
    /// is a non-activating panel (a `QLPreviewPanel` here could not be key).
    private func quickLookSelected() -> Bool {
        guard let file = selectedFile() else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        process.arguments = ["-p", file.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        return true
    }

    /// `f `/`img `/`ev ` run a debounced search off the main thread (Phase 29g / 30i).
    private func searchFiles(_ query: String) {
        guard case .mode(let mode, let argument)? = CommandKeyword.parse(query) else {
            fileSearchTask?.cancel()
            fileSearchTask = nil
            model.files = []; model.events = []
            return
        }
        switch mode {
        case .event:
            fileSearchTask?.cancel()
            fileSearchTask = nil
            model.files = []
            model.events = ProductivityServices.shared.calendar.searchEvents(argument)
            model.refresh()
        case .file, .image:
            model.events = []
            let fileQuery = FileQuery.parse(argument, imageOnly: mode == .image)
            guard fileQuery.isValid else {
                fileSearchTask?.cancel()
                fileSearchTask = nil
                model.files = []
                model.refresh()
                return
            }
            if let indexed = FileIndexService.shared.search(terms: fileQuery.terms, extensions: fileQuery.extensions,
                                                            imageOnly: fileQuery.imageOnly) {
                fileSearchTask?.cancel()
                fileSearchTask = nil
                model.files = indexed
                model.refresh()
                return
            }
            fileSearchTask?.cancel()
            fileSearchTask = Task { [weak self] in
                let entries = FileSearchService.search(fileQuery)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, !Task.isCancelled else { return }
                    self.model.files = entries
                    self.model.refresh()
                }
            }
        case .bookmark:
            fileSearchTask?.cancel()
            fileSearchTask = nil
            model.files = []; model.events = []
            if model.bookmarks.isEmpty {
                loadBookmarksAsync()
            }
        case .profile:
            fileSearchTask?.cancel()
            fileSearchTask = nil
            model.files = []; model.events = []
            model.profiles = barProfiles?.summaries() ?? []
            model.refresh()
        case .menu:
            fileSearchTask?.cancel()
            fileSearchTask = nil
            model.files = []; model.events = []
            loadMenuItemsOnce()
        default:
            fileSearchTask?.cancel()
            fileSearchTask = nil
            model.files = []; model.events = []
        }
    }

    /// One AX walk per summon, off the main thread; typing after it only re-ranks in memory.
    private func loadMenuItemsOnce() {
        guard !menuLoaded, let pid = menuTarget?.processIdentifier else { return }
        menuLoaded = true
        menuLoadTask = Task { [weak self] in
            let entries = await Task.detached(priority: .userInitiated) { AppMenuSearchReader.entries(pid: pid) }.value
            guard !Task.isCancelled, let self else { return }
            self.model.menuItems = entries
            self.model.refresh()
        }
    }

    private func handleQueryChange(_ query: String) {
        if query.hasPrefix("!") || query.hasPrefix("kp ") {
            loadProcessesAsync()
        }
        if query.hasPrefix("bm ") && model.bookmarks.isEmpty {
            loadBookmarksAsync()
        }
        searchFiles(query)
    }

    private func loadProcessesAsync() {
        if let last = lastProcessListTime, Date().timeIntervalSince(last) < 5, !model.processes.isEmpty {
            return
        }
        guard !isLoadingProcesses else { return }
        isLoadingProcesses = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let procs = ProcessLister.list()
            await MainActor.run {
                guard let self else { return }
                self.isLoadingProcesses = false
                self.lastProcessListTime = Date()
                self.model.processes = procs
                let q = self.model.query
                if q.hasPrefix("!") || q.hasPrefix("kp ") {
                    self.model.refresh()
                }
            }
        }
    }

    private func loadBookmarksAsync() {
        guard !isLoadingBookmarks else { return }
        isLoadingBookmarks = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let marks = BookmarkService.load()
            await MainActor.run {
                guard let self else { return }
                self.isLoadingBookmarks = false
                self.model.bookmarks = marks
                if self.model.query.hasPrefix("bm ") {
                    self.model.refresh()
                }
            }
        }
    }

    private func confirmKill(_ entry: ProcessEntry) {
        // Phase 48d: the one shared flow (Top Apps tile uses it too) — same buttons, same signals.
        ProcessKillConfirm.confirm(name: entry.name, pid: entry.pid)
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
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let host = NSHostingView(rootView: CommandBarView(model: model,
                                                          onRun: { [weak self] in self?.run($0) },
                                                          onClose: { [weak self] in self?.dismiss() },
                                                          onRemove: { app, removal in
                                                              AppRemovalService.confirmAndPerform(bundleID: app.bundleID, name: app.name, appPath: app.path, removal: removal)
                                                          },
                                                          onAction: { [weak self] action in self?.performAction(action) }))
        panel.contentView = host
        appsObserver = indexer.$apps.sink { [weak self] apps in
            self?.model.apps = apps
            self?.model.refresh()
        }
        queryObserver = model.$query
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] query in self?.handleQueryChange(query) }
        return panel
    }
}
