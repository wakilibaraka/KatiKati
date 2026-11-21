import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Phase 12 + Slice CS-2 — the Tools page's rows: Clipboard (with tag pills), structured Commands &
/// Snippets (with JSON import/export and variable chips), Key Visualizer, and Shortcut
/// Cheat Sheet. Bounded inner scroll lists keep total page height ≤ 1074 pt.
struct UtilitySettingsBlock: View {
    @ObservedObject var store: AppSettingsStore
    @ObservedObject private var keyGuard = KeyGuardService.shared
    @ObservedObject private var cheatSheet = ShortcutCheatSheetService.shared
    @AppStorage(ClipboardMonitor.soundsKey) private var clipboardSounds = true
    @AppStorage(ClipboardMonitor.notchToastKey) private var clipboardToast = true
    @AppStorage(ClipboardToastBadge.dockTileKey) private var dockClipboardTile = false
    @ObservedObject private var tendedero = TendederoClotheslineController.shared
    @AppStorage(ClipboardMonitor.ignorePatternsKey) private var clipboardIgnorePatterns = ""
    @AppStorage(ClipboardMonitor.keepDaysKey) private var clipboardKeepDays = 0
    @AppStorage(CustomCommand.key) private var customCommands = ""
    @AppStorage(CustomCommand.snippetsKey) private var snippets = ""

    @State private var showAddPattern = false
    @State private var newPattern = ""
    @State private var showAddCommand = false
    @State private var editingCommandIndex: Int?
    @State private var draftCommandName = ""
    @State private var draftCommandTarget = ""
    @State private var showSnippetEditor = false
    @State private var draftSnippet = TextSnippetItem(trigger: "", content: "")

    private var ignoreTags: [String] {
        clipboardIgnorePatterns
            .split { $0 == "," || $0 == "\n" }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var parsedCommands: [CustomCommand] {
        CustomCommand.parse(customCommands)
    }

    private var parsedSnippets: [TextSnippetItem] {
        TextSnippetStore.parse(snippets)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
                SettingsCard(Text("Commands & Snippets")) {
                    HStack {
                        Text("Custom Commands").font(.subheadline.weight(.medium))
                        Spacer()
                        Button {
                            editingCommandIndex = nil
                            draftCommandName = ""
                            draftCommandTarget = ""
                            showAddCommand = true
                        } label: {
                            Label("Add", systemImage: "plus").font(.caption)
                        }
                        .buttonStyle(SettingsGelButtonStyle())
                        .popover(isPresented: $showAddCommand, arrowEdge: .bottom) {
                            commandEditorPopover
                        }
                    }
                    if parsedCommands.isEmpty {
                        Text("No custom commands yet.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(Array(parsedCommands.enumerated()), id: \.offset) { idx, cmd in
                                    HStack(spacing: 6) {
                                        Text(verbatim: cmd.name)
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Capsule().fill(Color.accentColor.opacity(0.16)))
                                        Text(verbatim: cmd.target)
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        Spacer(minLength: 4)
                                        Button {
                                            editingCommandIndex = idx
                                            draftCommandName = cmd.name
                                            draftCommandTarget = cmd.target
                                            showAddCommand = true
                                        } label: { Image(systemName: "pencil").font(.caption) }
                                        .buttonStyle(.plain)
                                        Button { deleteCommand(at: idx) } label: {
                                            Image(systemName: "trash").font(.caption).foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                                }
                            }
                        }
                        .frame(maxHeight: 82)
                    }
                    SettingsDivider()
                    HStack(spacing: 6) {
                        Text("Text Snippets").font(.subheadline.weight(.medium))
                        Spacer()
                        Button("Import") { importSnippetsJSON() }
                            .buttonStyle(SettingsGelButtonStyle())
                        Button("Export") { exportSnippetsJSON() }
                            .buttonStyle(SettingsGelButtonStyle())
                        Button {
                            draftSnippet = TextSnippetItem(trigger: ";", content: "")
                            showSnippetEditor = true
                        } label: {
                            Label("Add", systemImage: "plus").font(.caption)
                        }
                        .buttonStyle(SettingsGelButtonStyle())
                        .popover(isPresented: $showSnippetEditor, arrowEdge: .bottom) {
                            snippetEditorPopover
                        }
                    }
                    if parsedSnippets.isEmpty {
                        Text("No snippets yet. Use ;sig, {clipboard}, {date}, or {cursor}.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(parsedSnippets) { item in
                                    HStack(spacing: 6) {
                                        Text(verbatim: item.trigger)
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Capsule().fill(Color.primary.opacity(0.09)))
                                        Text(verbatim: item.content.replacingOccurrences(of: "\n", with: " ↵ "))
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        Spacer(minLength: 4)
                                        Toggle(isOn: Binding(
                                            get: { item.isEnabled },
                                            set: { on in toggleSnippet(item.id, enabled: on) }
                                        )) { EmptyView() }
                                        .labelsHidden()
                                        .controlSize(.small)
                                        Button {
                                            draftSnippet = item
                                            showSnippetEditor = true
                                        } label: { Image(systemName: "pencil").font(.caption) }
                                        .buttonStyle(.plain)
                                        Button { deleteSnippet(item.id) } label: {
                                            Image(systemName: "trash").font(.caption).foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                                }
                            }
                        }
                        .frame(maxHeight: 112)
                    }
                    SettingsDivider()
                    SettingsToggleRow(
                        Text("Expand Snippets Anywhere"),
                        isOn: Binding(
                            get: { KeyGuardService.shared.isSnippetExpansionEnabled },
                            set: { on in
                                if on, !KeyGuardService.hasPermission { KeyGuardService.requestPermission() }
                                KeyGuardService.shared.setSnippetExpansion(on)
                            }
                        ),
                        info: String(localized: "Type a snippet's trigger in any app to paste its text. Supports {clipboard}, {date}, {time}, and {cursor}. Never runs in password fields.")
                    )
                }
            }
            SettingsCard(Text("Shortcut Cheat Sheet")) {
                SettingsPickerRow(
                    Text("Quick Trigger"),
                    selection: Binding(
                        get: { cheatSheet.trigger },
                        set: { cheatSheet.setTrigger($0) }
                    ),
                    note: Text("Floating overlay showing all menu shortcuts for the active app plus your KatiKati shortcuts. Release ⌘ to dismiss, or pin it open.")
                ) {
                    Text("Off").tag(ShortcutCheatSheetTrigger.off)
                    Text("Double-tap & Hold ⌘").tag(ShortcutCheatSheetTrigger.doubleTapCommand)
                    Text("Hold ⌘").tag(ShortcutCheatSheetTrigger.holdCommand)
                }
                SettingsDivider()
                SettingsRow(Text("Cheat Sheet Overlay"), note: Text("Inspect, search, or export the frontmost app's shortcuts as Markdown.")) {
                    Button("Open Cheat Sheet") { cheatSheet.toggle(pinned: true) }
                        .buttonStyle(SettingsGelButtonStyle())
                }
                if !AXIsProcessTrusted() {
                    SettingsDivider()
                    SettingsNote(Text("Accessibility permission is required to read menu bar shortcuts from other apps."))
                }
            }
        }
    }

    private var commandEditorPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(editingCommandIndex == nil ? "New Command" : "Edit Command").font(.headline)
            TextField("Name (e.g. ;build)", text: $draftCommandName)
                .textFieldStyle(.roundedBorder)
            TextField("URL or /path/to/script", text: $draftCommandTarget)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { showAddCommand = false }
                Button("Save") {
                    saveCommand()
                    showAddCommand = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftCommandName.trimmingCharacters(in: .whitespaces).isEmpty
                          || draftCommandTarget.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private var snippetEditorPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Snippet").font(.headline)
            HStack(spacing: 8) {
                TextField("Trigger (e.g. ;sig)", text: $draftSnippet.trigger)
                    .textFieldStyle(.roundedBorder)
                Toggle("Require Space", isOn: $draftSnippet.requireDelimiter)
                    .toggleStyle(.checkbox)
            }
            TextEditor(text: $draftSnippet.content)
                .font(.system(size: 12, design: .monospaced))
                .frame(height: 90)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
            HStack(spacing: 6) {
                ForEach(["{clipboard}", "{date}", "{time}", "{cursor}"], id: \.self) { token in
                    Button(token) { draftSnippet.content += token }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { showSnippetEditor = false }
                Button("Save") {
                    saveSnippet()
                    showSnippetEditor = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftSnippet.trigger.trimmingCharacters(in: .whitespaces).count < 2
                          || draftSnippet.content.isEmpty)
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private func addIgnoreTag(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !ignoreTags.contains(trimmed) else { return }
        clipboardIgnorePatterns = (ignoreTags + [trimmed]).joined(separator: ", ")
    }

    private func removeIgnoreTag(_ tag: String) {
        clipboardIgnorePatterns = ignoreTags.filter { $0 != tag }.joined(separator: ", ")
    }

    private func saveCommand() {
        var list = parsedCommands
        let entry = CustomCommand(
            name: draftCommandName.trimmingCharacters(in: .whitespaces),
            target: draftCommandTarget.trimmingCharacters(in: .whitespaces),
            kind: CustomCommand.kind(of: draftCommandTarget)
        )
        if let idx = editingCommandIndex, list.indices.contains(idx) {
            list[idx] = entry
        } else {
            list.append(entry)
        }
        customCommands = CustomCommand.serialize(list)
    }

    private func deleteCommand(at index: Int) {
        var list = parsedCommands
        guard list.indices.contains(index) else { return }
        list.remove(at: index)
        customCommands = CustomCommand.serialize(list)
    }

    private func saveSnippet() {
        var list = parsedSnippets
        var clean = draftSnippet
        clean.trigger = clean.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        if let idx = list.firstIndex(where: { $0.id == clean.id }) {
            list[idx] = clean
        } else {
            list.append(clean)
        }
        snippets = TextSnippetStore.serialize(list)
        KeyGuardService.shared.refreshSnippetTriggers()
    }

    private func toggleSnippet(_ id: UUID, enabled: Bool) {
        var list = parsedSnippets
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
        list[idx].isEnabled = enabled
        snippets = TextSnippetStore.serialize(list)
        KeyGuardService.shared.refreshSnippetTriggers()
    }

    private func deleteSnippet(_ id: UUID) {
        let list = parsedSnippets.filter { $0.id != id }
        snippets = TextSnippetStore.serialize(list)
        KeyGuardService.shared.refreshSnippetTriggers()
    }

    private func exportSnippetsJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "katikati-snippets.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let json = TextSnippetStore.serialize(parsedSnippets)
        try? json.write(to: url, atomically: true, encoding: .utf8)
    }

    private func importSnippetsJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let raw = try? String(contentsOf: url, encoding: .utf8) else { return }
        let imported = TextSnippetStore.parse(raw)
        guard !imported.isEmpty else { return }
        var merged = parsedSnippets
        for item in imported where !merged.contains(where: { $0.trigger == item.trigger }) {
            merged.append(item)
        }
        snippets = TextSnippetStore.serialize(merged)
        KeyGuardService.shared.refreshSnippetTriggers()
    }
}

/// Dedicated settings pane for the Background Apps Drawer capsule flanking the Dock bar.
struct DrawerSettingsBlock: View {
    @ObservedObject var store: AppSettingsStore

    var body: some View {
        SettingsCard(
            Text("Drawer"),
            note: Text("Places the circular Background Apps Drawer capsule on the left or right flank of the bottom Dock bar (or inside Control Center when docked trailing).")
        ) {
            SettingsToggleRow(
                Text("Drawer"),
                isOn: Binding(get: { store.showDrawer }, set: { store.setShowDrawer($0) }),
                note: Text("Show the Drawer button beside the Dock to list running background apps with no open window.")
            )
            SettingsDivider()
            SettingsPickerRow(
                Text("Drawer Position"),
                selection: Binding(get: { store.drawerPlacement }, set: { store.setDrawerPlacement($0) }),
                note: Text("Left puts the Drawer button before the Dock apps; Right puts it after them.")
            ) {
                Text("Left").tag(DrawerPlacement.left)
                Text("Right").tag(DrawerPlacement.right)
            }
        }
    }
}

/// Dedicated settings pane for the temporary Shelf card stack, Notch File Tray sync, and Space pinning.
struct ShelfSettingsBlock: View {
    @ObservedObject var store: AppSettingsStore
    /// 54d — read from the Dock itself, so a change made in System Settings shows here too.
    @State private var fixedSpaces = false
    @AppStorage(ShelfPolicy.presentationStyleKey) private var presentationStyleRaw = ShelfPresentationStyle.floatingCardStack.rawValue
    @AppStorage(ShelfPolicy.showTextExcerptKey) private var showTextExcerpt = true
    @AppStorage(ShelfPolicy.notchAutoOpenOnDragKey) private var notchAutoOpenOnDrag = true
    @AppStorage(ShelfPolicy.syncNotchTrayKey) private var syncNotchTray = true

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            SettingsCard(Text("Shelf")) {
                SettingsPickerRow(
                    Text("Shelf View Style"),
                    selection: $presentationStyleRaw
                ) {
                    ForEach(ShelfPresentationStyle.allCases) { style in
                        Text(verbatim: style.localizedTitle).tag(style.rawValue)
                    }
                }
                SettingsDivider()
                SettingsRowPair(
                    left: { SettingsToggleRow(Text("Text Excerpt Previews"), isOn: $showTextExcerpt).padding(.trailing, 12) },
                    right: { SettingsToggleRow(Text("Sync Notch Tray & Dock Shelf"), isOn: $syncNotchTray).padding(.leading, 12) }
                )
                SettingsDivider()
                SettingsRowPair(
                    left: { SettingsToggleRow(Text("Notch Auto-Open on Drag"), isOn: $notchAutoOpenOnDrag).padding(.trailing, 12) },
                    right: { SettingsToggleRow(Text("Shake to Shelf"), isOn: Binding(get: { store.shelfShakeEnabled }, set: { store.setShelfShakeEnabled($0) })).padding(.leading, 12) }
                )
                SettingsDivider()
                SettingsToggleRow(
                    Text("Auto-Expire"),
                    isOn: Binding(get: { store.shelfAutoExpire }, set: { store.setShelfAutoExpire($0) })
                )
                if store.shelfAutoExpire {
                    SettingsDivider()
                    SettingsRow(Text("Expire After")) {
                        Picker("Expire After", selection: Binding(get: { store.shelfExpiryDays }, set: { store.setShelfExpiryDays($0) })) {
                            Text("1 day").tag(1)
                            Text("3 days").tag(3)
                            Text("7 days").tag(7)
                        }
                        .labelsHidden().pickerStyle(.menu).fixedSize()
                    }
                }
                SettingsDivider()
                SettingsRow(Text("Storage")) {
                    Picker("Storage", selection: Binding(get: { store.shelfStorage }, set: { store.setShelfStorage($0) })) {
                        Text("References").tag(ShelfStorage.reference)
                        Text("Copies").tag(ShelfStorage.copy)
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
                SettingsDivider()
                SettingsButtonRow(Text("Clear Unpinned")) { confirmShelfClear() }
                SettingsDivider()
                SettingsRow(Text("System Dock")) {
                    Button("Restore Dock") { AppDelegate.shared?.restoreNativeDock() }
                        .buttonStyle(SettingsGelButtonStyle())
                }
                SettingsDivider()
                SettingsToggleRow(
                    Text("Fixed Space Order"),
                    isOn: Binding(get: { fixedSpaces }, set: { confirmFixedSpaces($0) }),
                    note: Text("Stops macOS from rearranging Spaces by most recent use, so they stay in the order you made them. The Dock restarts once. Turning this off puts your earlier setting back.")
                )
            }
            SettingsCard(Text("How to Use Shelf & File Tray")) {
                HStack(alignment: .top, spacing: 10) {
                    howToTile(
                        symbol: "cursorarrow.motionlines",
                        title: Text("Shake Cursor"),
                        detail: Text("Shake mouse while dragging any file or text to summon the Shelf under your cursor")
                    ) {
                        Button("Test Shake Shelf") { triggerTestShakeShelf() }
                            .buttonStyle(SettingsGelButtonStyle())
                            .controlSize(.small)
                    }
                    howToTile(
                        symbol: "tray.and.arrow.down.fill",
                        title: Text("Notch File Tray"),
                        detail: Text("Drag files to the top notch to park, zip, or convert them")
                    ) { EmptyView() }
                    howToTile(
                        symbol: "rectangle.stack.fill",
                        title: Text("Dock Drop & Transform"),
                        detail: Text("Drop files, links, or text onto the Dock Shelf icon to stack rich cards and transform them")
                    ) { EmptyView() }
                }
            }
        }
        .task { fixedSpaces = await AppDelegate.shared?.fixedSpaceOrderState() ?? false }
    }

    private func howToTile<Footer: View>(symbol: String, title: Text, detail: Text, @ViewBuilder footer: () -> Footer) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.accentColor)
                title.font(.system(size: 11.5, weight: .semibold))
            }
            detail.font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            footer()
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    private func triggerTestShakeShelf() {
        let shelf = AppDelegate.shared?.shelfStore ?? ShelfStore()
        shelf.pulseForShake()
        let panel = ShelfDropTargetPanel(shelf: shelf)
        panel.present(near: NSEvent.mouseLocation)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { panel.close() }
    }

    /// 54d: it changes a macOS setting and restarts the Dock, so turning it on asks first. Off only puts
    /// back the value remembered before, so it runs without a prompt.
    private func confirmFixedSpaces(_ on: Bool) {
        guard let delegate = AppDelegate.shared else { return }
        if !on {
            do {
                try delegate.setFixedSpaceOrder(false)
                fixedSpaces = false
            } catch { fixedSpaces = true }
            return
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Keep Spaces in a Fixed Order?")
        alert.informativeText = String(localized: "macOS stops rearranging Spaces by most recent use and the Dock restarts once. Turning this off puts your earlier setting back.")
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "Turn On"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try delegate.setFixedSpaceOrder(true)
            fixedSpaces = true
        } catch { fixedSpaces = false }
    }

    /// 55d: a bulk delete of shelf entries asks first. Single-item remove stays immediate; this one drops
    /// every unpinned entry at once.
    private func confirmShelfClear() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Clear Unpinned Shelf Items?")
        alert.informativeText = String(localized: "Unpinned entries leave the shelf and its own copies are deleted. Pinned items stay.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Clear Unpinned"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { AppDelegate.shared?.shelfStore.clear() }
    }
}

/// 2026-11 Dedicated section for Claude Code hooks, tool approvals, and AI agent tracking.
struct AITrackingSettingsBlock: View {
    @AppStorage(ClaudeHookInstaller.enabledKey) private var claudeHook = false
    @State private var claudeHookFailed = false
    @AppStorage(ClaudeApprovalService.enabledKey) private var claudeApprovals = false
    @State private var claudeApprovalsFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            SettingsCard(Text("Claude Code Status")) {
                SettingsToggleRow(
                    Text("Track Turns with a Claude Hook"),
                    isOn: Binding(
                        get: { claudeHook },
                        set: { on in
                            do {
                                try ClaudeHookInstaller.setEnabled(on)
                                claudeHook = on
                                claudeHookFailed = false
                            } catch {
                                // An unreadable or invalid settings.json is left alone, so the switch stays put.
                                claudeHookFailed = true
                            }
                        }
                    ),
                    note: Text("Adds two hooks to ~/.claude/settings.json: one when a prompt is submitted, one when Claude stops. They append to a local log, so the notch shows ACTIVE while Claude Code works and IDLE as soon as it stops. Your other settings and hooks are kept, and the original file is backed up once. Restart Claude Code after changing this.")
                )
                if claudeHookFailed {
                    SettingsDivider()
                    SettingsNote(Text("Could not update ~/.claude/settings.json. Nothing was changed."))
                }
                SettingsDivider()
                SettingsToggleRow(
                    Text("Approve Claude Code Requests Here"),
                    isOn: Binding(
                        get: { claudeApprovals },
                        set: { on in
                            do {
                                try ClaudeHookInstaller.setApprovalsEnabled(on)
                                claudeApprovals = on
                                claudeApprovalsFailed = false
                                if on { ClaudeApprovalService.shared.start() } else { ClaudeApprovalService.shared.stop() }
                            } catch {
                                claudeApprovalsFailed = true
                            }
                        }
                    ),
                    note: Text("Adds a permission hook to ~/.claude/settings.json. When Claude Code asks before running a tool, a card appears at the top of your screen with Allow and Deny. If KatiKati is closed or you do not answer within a minute, Claude Code asks in the terminal as usual. Your other settings and hooks are kept. Restart Claude Code after changing this.")
                )
                if claudeApprovalsFailed {
                    SettingsDivider()
                    SettingsNote(Text("Could not update ~/.claude/settings.json. Nothing was changed."))
                }
            }
        }
    }

}

/// Phase 44b — the BitTorrent hub's policy: custom engine path, seeding limits and a throttled
/// upload window. Reads the same `com.katikati.torrent.*` keys the engine does, so a change lands
/// without relaunch; policy pushes live via `applyPolicy()`, a path change applies on next start.
struct TorrentSettingsBlock: View {
    @AppStorage(TorrentSettings.enginePathKey) private var enginePath = ""
    @AppStorage(TorrentSettings.seedRatioKey) private var seedRatio = 0.0
    @AppStorage(TorrentSettings.seedTimeMinutesKey) private var seedMinutes = 0
    @AppStorage(TorrentSettings.maxUploadKBpsKey) private var maxUploadKBps = 0
    @AppStorage(TorrentSettings.quietStartHourKey) private var quietStart = 0
    @AppStorage(TorrentSettings.quietEndHourKey) private var quietEnd = 0
    @AppStorage(TorrentSettings.quietUploadKBpsKey) private var quietUploadKBps = 0
    @State private var detectedPath: String? = nil

    var body: some View {
        SettingsCard(Text("BitTorrent")) {
            SettingsRow(Text("Engine Path"), note: Text(statusLine)) {
                HStack(spacing: 8) {
                    TextField("/opt/homebrew/bin/aria2c", text: $enginePath)
                        .textFieldStyle(.roundedBorder).frame(width: 220)
                    if !enginePath.isEmpty {
                        Button("Auto") { enginePath = "" }
                            .buttonStyle(SettingsGelButtonStyle())
                    }
                }
            }
            SettingsDivider()
                                SettingsStepperRow(
                        Text("Seed Ratio"),
                        value: $seedRatio,
                        in: 0...50,
                        step: 0.5,
                        readout: seedRatio == 0 ? "0 (stop)" : String(format: "%.1f", seedRatio)
                    )
            SettingsDivider()
                    SettingsStepperRow(
                        Text("Seed Minutes"),
                        value: Binding(get: { Double(seedMinutes) }, set: { seedMinutes = Int($0) }),
                        in: 0...1440,
                        step: 10,
                        readout: seedMinutes == 0 ? "0 (stop)" : "\(seedMinutes)m"
                    )
            SettingsDivider()
                                SettingsStepperRow(
                        Text("Max Upload"),
                        value: Binding(get: { Double(maxUploadKBps) }, set: { maxUploadKBps = Int($0) }),
                        in: 0...100_000,
                        step: 50,
                        readout: maxUploadKBps == 0 ? "Unlimited" : "\(maxUploadKBps) KB/s"
                    )
            SettingsDivider()
                    SettingsStepperRow(
                        Text("Quiet Upload"),
                        value: Binding(get: { Double(quietUploadKBps) }, set: { quietUploadKBps = Int($0) }),
                        in: 0...100_000,
                        step: 10,
                        readout: quietUploadKBps == 0 ? "Off" : "\(quietUploadKBps) KB/s",
                        note: Text("Equal hours disables the window. 0 stops sharing at completion.")
                    )
            SettingsDivider()
                                SettingsStepperRow(
                        Text("Quiet From"),
                        value: Binding(get: { Double(quietStart) }, set: { quietStart = Int($0) }),
                        in: 0...23,
                        step: 1,
                        readout: "\(quietStart):00"
                    )
            SettingsDivider()
                    SettingsStepperRow(
                        Text("Quiet Until"),
                        value: Binding(get: { Double(quietEnd) }, set: { quietEnd = Int($0) }),
                        in: 0...23,
                        step: 1,
                        readout: "\(quietEnd):00"
                    )
        }
        .onAppear { detectedPath = TorrentEngine.shared.resolvedBinaryPath }
        .onChange(of: seedRatio) { _ in pushPolicy() }
        .onChange(of: seedMinutes) { _ in pushPolicy() }
        .onChange(of: maxUploadKBps) { _ in pushPolicy() }
        .onChange(of: quietStart) { _ in pushPolicy() }
        .onChange(of: quietEnd) { _ in pushPolicy() }
        .onChange(of: quietUploadKBps) { _ in pushPolicy() }
    }

    private var statusLine: String {
        if !enginePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Custom path — applies on next start." }
        return detectedPath ?? "aria2c not found — install aria2 for magnet links."
    }

    private func pushPolicy() { Task { await TorrentEngine.shared.applyPolicy() } }
}

/// Phase 12 (2026-10-15) — the launcher's own rows (script commands, command hints, the file
/// index, the Spotlight hand-off), split out of `UtilitySettingsBlock` when the tools got their own
/// tab. The launcher and the Control Center share the Launcher page; these rows belong to neither
/// the clipboard nor the shelf.
struct LauncherSettingsBlock: View {
    @AppStorage(LauncherRunner.enabledKey) private var launcherScripts = false
    @AppStorage(FileIndexService.enabledKey) private var fastIndex = true

    var body: some View {
        SettingsCard(Text("Launcher")) {
            // Two switches (the command bar's hint switch moved to its own page, 2026-10-20).
            SettingsToggleRow(Text("Script Commands"), isOn: $launcherScripts)
            SettingsDivider()
            SettingsToggleRow(Text("Fast File Index"), isOn: $fastIndex)
            SettingsDivider()
            // Rule 4: the five steps used to be five notes under this button. They are the row's
            // ⓘ now. Each step stays a whole literal (rule 9) — they are joined, never assembled.
            SettingsButtonRow(
                Text("Replace Spotlight"),
                info: SpotlightHandoff.steps().map(spotlightStepText).joined(separator: "\n")
            ) {
                if let url = URL(string: SpotlightHandoff.settingsURL) { NSWorkspace.shared.open(url) }
            }
        }
    }

    private func spotlightStepText(_ step: SpotlightHandoff.Step) -> String {
        switch step {
        case .openKeyboard: return String(localized: "Open System Settings › Keyboard.")
        case .openShortcuts: return String(localized: "Click Keyboard Shortcuts….")
        case .selectSpotlight: return String(localized: "Select Spotlight in the list.")
        case .uncheckShowSearch: return String(localized: "Turn off Show Spotlight search.")
        case .testHere: return String(localized: "Come back and press ⌘Space to test.")
        }
    }

}

/// The command bar's own rows (2026-10-20): split out of `LauncherSettingsBlock` so the command
/// bar has a page of its own instead of riding on the launcher's.
struct CommandBarSettingsBlock: View {
    var tabState: SettingsTabState? = nil
    @AppStorage("com.katikati.commandbar.hints") private var commandHints = true
    @AppStorage(Quicklink.key) private var quicklinks = ""

    var body: some View {
        SettingsCard(Text("Command Bar")) {
            SettingsToggleRow(Text("Show Command Hints"), isOn: $commandHints)
            SettingsDivider()
            SettingsEditorRow(
                Text("Quicklinks"),
                text: $quicklinks,
                placeholder: Text("One per line: gh = https://github.com/search?q={query} (supports {query}, {clipboard}, {date})")
            )
            if let tabState {
                SettingsDivider()
                SettingsRow(Text("Commands & Snippets"), note: Text("Configure custom scripts and text expansions in Tools.")) {
                    Button("Open Tools Settings") {
                        tabState.selected = .tools
                    }
                    .buttonStyle(SettingsGelButtonStyle())
                }
            }
        }
    }

}

/// Phase 12 — the helpers that surface in the notch (indicators, notices, teleprompter page), split
/// out of `UtilitySettingsBlock` so the Notch page owns them.
struct NotchHelpersSettingsBlock: View {
    @AppStorage(DailyHelpersService.hideFromCaptureKey) private var hideFromCapture = false
    @AppStorage(DailyHelpersService.capsLockKey) private var capsLockHUD = false
    @AppStorage(DailyHelpersService.batteryKey) private var batteryNudge = false
    @AppStorage(DailyHelpersService.ejectKey) private var usbEject = false
    @AppStorage(DailyHelpersService.privacyKey) private var privacyDot = false
    @AppStorage(DailyHelpersService.hydrateKey) private var hydrate = false
    @AppStorage(DailyHelpersService.pauseKey) private var pauseReminder = false
    @AppStorage(TeleprompterModel.enabledKey) private var teleprompterPage = true
    @AppStorage(CameraMirrorService.enabledKey) private var cameraMirrorPage = true
    @AppStorage(NotchEdgeStyle.sharpKey) private var sharpEdges = false
    @AppStorage(LyricsTrack.enabledKey) private var syncedLyrics = false

    var body: some View {
        SettingsCard(Text("Daily Helpers")) {
            SettingsRowPair(
                left: { SettingsToggleRow(Text("Hide from Screen Capture"), isOn: $hideFromCapture) },
                right: { SettingsToggleRow(Text("Caps Lock Indicator"), isOn: $capsLockHUD) }
            )
            SettingsDivider()
            SettingsRowPair(
                left: { SettingsToggleRow(Text("Charge Notices"), isOn: $batteryNudge) },
                right: { SettingsToggleRow(Text("Offer to Eject Drives"), isOn: $usbEject) }
            )
            SettingsDivider()
            SettingsToggleRow(Text("Camera and Mic Indicator"), isOn: $privacyDot)
            SettingsDivider()
            SettingsRowPair(
                left: { SettingsToggleRow(Text("Water Reminder"), isOn: $hydrate) },
                right: { SettingsToggleRow(Text("Break Reminder"), isOn: $pauseReminder) }
            )
            SettingsDivider()
            SettingsRow(Text("Teleprompter"), note: Text("Opens from ⌘Space (prompter). The window is hidden from screen recordings and shares.")) {
                Button("Open Teleprompter Window") { TeleprompterWindowController.shared.show() }
                    .buttonStyle(SettingsGelButtonStyle())
            }
            SettingsDivider()
            SettingsRowPair(
                left: { SettingsToggleRow(Text("Teleprompter Notch Page"), isOn: $teleprompterPage) },
                right: { SettingsToggleRow(Text("Camera Mirror Notch Page"), isOn: $cameraMirrorPage) }
            )
            SettingsDivider()
            SettingsToggleRow(Text("Sharp Notch Edges"), isOn: $sharpEdges)
            SettingsDivider()
            SettingsToggleRow(
                Text("Synced Lyrics"),
                isOn: $syncedLyrics,
                info: String(localized: "Looks up synced lyrics from lrclib.net by sending the current song title and artist when the music notch card is open.")
            )
        }
    }

}

/// Slice MC-1 — the Clipboard page, promoted out of Tools. Four cards: behavior, storage & sorting,
/// privacy & ignore types, and appearance & popup. Every switch writes a `ClipboardSettingsKeys` default
/// the monitor and the flyout read, so the page never holds state of its own.
struct ClipboardSettingsPane: View {
    @ObservedObject var store: AppSettingsStore
    @ObservedObject private var monitor = ProductivityServices.shared.clipboard
    @AppStorage(ClipboardMonitor.soundsKey) private var sounds = true
    @AppStorage(ClipboardMonitor.notchToastKey) private var toast = true
    @AppStorage(ClipboardToastBadge.dockTileKey) private var dockTile = false
    @AppStorage(ClipboardMonitor.ignorePatternsKey) private var patterns = ""
    @AppStorage(ClipboardMonitor.keepDaysKey) private var keepDays = 0
    @AppStorage(ClipboardSettingsKeys.pasteAutomatically) private var pasteAutomatically = false
    @AppStorage(ClipboardSettingsKeys.plainTextByDefault) private var plainTextByDefault = false
    @AppStorage(ClipboardSettingsKeys.pollingIntervalMS) private var pollingIntervalMS = 250
    @AppStorage(ClipboardSettingsKeys.historyLimit) private var historyLimit = 100
    @AppStorage(ClipboardSettingsKeys.ignoreConcealed) private var ignoreConcealed = true
    @AppStorage(ClipboardSettingsKeys.ignoreAutoGenerated) private var ignoreAutoGenerated = true
    @AppStorage(ClipboardSettingsKeys.ignoreUniversal) private var ignoreUniversal = false
    @AppStorage(ClipboardSettingsKeys.showFooterShortcuts) private var showFooterShortcuts = true
    @AppStorage(ClipboardSettingsKeys.showPinShortcuts) private var showPinShortcuts = true
    @AppStorage(ClipboardSettingsKeys.popupPosition) private var popupPosition = ClipboardPopupPosition.atCursor.rawValue
    @AppStorage(ClipboardSettingsKeys.sortBy) private var sortBy = ClipboardSortOrder.lastCopied.rawValue
    @ObservedObject private var tendedero = TendederoClotheslineController.shared

    @State private var showAddPattern = false
    @State private var newPattern = ""

    private var ignoreTags: [String] {
        patterns.split { $0 == "," || $0 == "\n" }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        // Two half-width rows: four cards side by side squeeze the labels into wrapped slivers at this
        // window width (MC-1 screenshot check, 2026-11-17).
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            SettingsBentoSplit {
                behaviorCard
            } trailing: {
                storageCard
            }
            SettingsBentoSplit {
                privacyCard
            } trailing: {
                appearanceCard
            }
        }
    }

    private var behaviorCard: some View {
        SettingsCard(Text("Behavior")) {
            SettingsToggleRow(Text("Record Clipboard"),
                              isOn: Binding(get: { monitor.isRecording }, set: { monitor.setRecording($0) }))
            SettingsDivider()
            SettingsToggleRow(Text("Paste Automatically"), isOn: $pasteAutomatically)
            SettingsDivider()
            SettingsToggleRow(Text("Paste Without Formatting by Default"), isOn: $plainTextByDefault)
            SettingsDivider()
            SettingsPickerRow(Text("Polling Interval"), selection: $pollingIntervalMS) {
                Text(verbatim: "100 ms").tag(100)
                Text(verbatim: "250 ms").tag(250)
                Text(verbatim: "500 ms").tag(500)
            }
            SettingsDivider()
            SettingsToggleRow(
                Text("Hang Copied Images & Links on Sidebar"),
                isOn: Binding(
                    get: { tendedero.captureMode == .screenshotsAndAutoClipboard },
                    set: { tendedero.setCaptureMode($0 ? .screenshotsAndAutoClipboard : .screenshotsAndManualClipboard) }
                )
            )
            SettingsDivider()
            HStack(spacing: 8) {
                Button("Ignore Next Copy") { monitor.ignoreNextCopy() }
                    .buttonStyle(SettingsGelButtonStyle())
                if !monitor.isRecording {
                    Text("Paused").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            SettingsNote(Text("History is kept in memory only and is never written to disk."))
        }
    }

    private var storageCard: some View {
        SettingsCard(Text("Storage & Sorting")) {
            SettingsPickerRow(Text("History Limit"), selection: $historyLimit) {
                ForEach([50, 100, 250, 500], id: \.self) { Text(verbatim: "\($0)").tag($0) }
            }
            SettingsDivider()
            SettingsPickerRow(
                Text("Keep Clipboard History"),
                selection: Binding(
                    get: { keepDays },
                    set: { days in
                        keepDays = days
                        ProductivityServices.shared.clipboard.setRetention(days: days)
                    }
                )
            ) {
                Text("24 hours").tag(1)
                Text("7 days").tag(7)
                Text("30 days").tag(30)
                Text("Forever").tag(0)
            }
            SettingsDivider()
            SettingsPickerRow(Text("Sort By"), selection: $sortBy) {
                ForEach(ClipboardSortOrder.allCases) { order in
                    // One literal per branch so the localizer sees all three keys.
                    switch order {
                    case .lastCopied: Text("Last Copied").tag(order.rawValue)
                    case .firstCopied: Text("First Copied").tag(order.rawValue)
                    case .mostUsed: Text("Most Used").tag(order.rawValue)
                    }
                }
            }
            SettingsDivider()
            SettingsNote(Text("Pinned items never expire. History is kept in memory only."))
            SettingsDivider()
            SettingsToggleRow(
                Text("Clean Copied Links"),
                isOn: Binding(get: { store.linkCleanerEnabled }, set: { store.setLinkCleanerEnabled($0) })
            )
            SettingsDivider()
            SettingsToggleRow(Text("Copy & Paste Sounds"), isOn: $sounds)
            SettingsDivider()
            SettingsToggleRow(Text("Copy & Paste Glimpse Notifications"), isOn: $toast)
            SettingsDivider()
            SettingsToggleRow(Text("Show Clipboard Tile on Dock"), isOn: $dockTile)
        }
    }

    private var privacyCard: some View {
        SettingsCard(Text("Privacy & Ignore Types")) {
            SettingsToggleRow(Text("Concealed & Password Managers"), isOn: $ignoreConcealed)
            SettingsDivider()
            SettingsToggleRow(Text("Auto-Generated"), isOn: $ignoreAutoGenerated)
            SettingsDivider()
            SettingsToggleRow(Text("Universal Clipboard"), isOn: $ignoreUniversal)
            SettingsDivider()
            HStack {
                Text("Ignore Patterns").font(.body)
                Spacer()
                Menu {
                    ForEach(NSWorkspace.shared.runningApplications.filter {
                        $0.activationPolicy == .regular && $0.bundleIdentifier != nil
                    }, id: \.processIdentifier) { app in
                        if let bid = app.bundleIdentifier {
                            Button(app.localizedName ?? bid) { addIgnoreTag(bid) }
                        }
                    }
                    Divider()
                    Button("Add Pattern…") { newPattern = ""; showAddPattern = true }
                } label: {
                    Label("Exclude App", systemImage: "plus").font(.caption)
                }
                .menuStyle(.borderlessButton).fixedSize()
                .popover(isPresented: $showAddPattern, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add Ignore Pattern").font(.headline)
                        TextField("Bundle ID or regex", text: $newPattern)
                            .textFieldStyle(.roundedBorder).frame(width: 220)
                        HStack {
                            Spacer()
                            Button("Cancel") { showAddPattern = false }
                            Button("Add") { addIgnoreTag(newPattern); showAddPattern = false }
                                .buttonStyle(.borderedProminent)
                                .disabled(newPattern.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding(12)
                }
            }
            if ignoreTags.isEmpty {
                Text("No ignored apps or patterns.").font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(ignoreTags, id: \.self) { tag in
                            HStack(spacing: 4) {
                                Text(verbatim: tag).font(.caption).lineLimit(1)
                                Button { removeIgnoreTag(tag) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                        }
                    }
                }
            }
        }
    }

    private var appearanceCard: some View {
        SettingsCard(Text("Appearance & Popup")) {
            SettingsToggleRow(Text("Show Footer Shortcuts"), isOn: $showFooterShortcuts)
            SettingsDivider()
            SettingsToggleRow(Text("Show Pin Shortcuts (⌘1–9)"), isOn: $showPinShortcuts)
            SettingsDivider()
            SettingsPickerRow(Text("Popup Position"), selection: $popupPosition) {
                Text("At Cursor").tag(ClipboardPopupPosition.atCursor.rawValue)
                Text("Screen Center").tag(ClipboardPopupPosition.screenCenter.rawValue)
                Text("Under Bar/Notch").tag(ClipboardPopupPosition.underBar.rawValue)
            }
        }
    }

    private func addIgnoreTag(_ raw: String) {
        let tag = raw.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, !ignoreTags.contains(tag) else { return }
        patterns = (ignoreTags + [tag]).joined(separator: "\n")
    }

    private func removeIgnoreTag(_ tag: String) {
        patterns = ignoreTags.filter { $0 != tag }.joined(separator: "\n")
    }
}
