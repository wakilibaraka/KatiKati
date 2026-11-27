import AppKit
import SwiftTerm
import SwiftUI

/// Tabs (the pure `TerminalTabs` model) plus the live sessions behind them.
@MainActor
final class TerminalPanelModel: ObservableObject {
    @Published private(set) var tabs: TerminalTabs
    @Published var theme: TerminalThemePreset
    @Published var plateSize: CGSize
    @Published var isFindPresented = false
    @Published var findQuery = ""
    @Published var findMatches: [TerminalBufferSearch.Match] = []
    @Published var findSelection = 0
    @Published var statusNote: String?
    private var sessions: [UUID: TerminalSession] = [:]

    init() {
        let initialTheme = TerminalThemePreset(
            rawValue: UserDefaults.standard.string(forKey: TerminalThemePreset.storageKey) ?? ""
        ) ?? .katikatiDark
        self.theme = initialTheme
        self.plateSize = TerminalPanelSizeBounds.load()
        let first = TerminalTabs.Tab(id: UUID(), title: "", directory: NSHomeDirectory())
        tabs = TerminalTabs(first: first)
        attach(first.id, directory: first.directory)
    }

    var selectedSession: TerminalSession? { sessions[tabs.selectedID] }

    func newTab() {
        guard let tab = tabs.add() else { return }
        attach(tab.id, directory: tab.directory)
    }

    func close(_ id: UUID) {
        if tabs.close(id) {
            sessions.removeValue(forKey: id)?.terminate()
        } else if tabs.tabs.count == 1, tabs.tabs[0].id == id {
            // The last shell ended: start a fresh one instead of showing a dead view.
            sessions.removeValue(forKey: id)?.terminate()
            attach(id, directory: NSHomeDirectory())
        }
    }

    func select(_ id: UUID) { tabs.select(id) }

    func setTheme(_ newTheme: TerminalThemePreset) {
        theme = newTheme
        UserDefaults.standard.set(newTheme.rawValue, forKey: TerminalThemePreset.storageKey)
        for session in sessions.values {
            session.applyTheme(newTheme)
        }
    }

    func sendSnippet(_ snippet: TerminalSnippet) {
        selectedSession?.sendText(snippet.command + "\n")
    }

    func syncFinderDirectory() {
        Task.detached(priority: .userInitiated) { [weak self] in
            let path = Self.readFrontFinderDirectory()
            await MainActor.run {
                guard let self else { return }
                guard let path,
                      FileManager.default.fileExists(atPath: path),
                      let cmd = TerminalSnippet.shellEscapedCDCommand(for: path) else {
                    self.flashStatus(String(localized: "No Finder folder open"))
                    return
                }
                self.selectedSession?.sendText(cmd)
                self.flashStatus((path as NSString).lastPathComponent)
            }
        }
    }

    func refreshFind() {
        guard let session = selectedSession else { findMatches = []; return }
        let buffer = session.readBufferText()
        findMatches = TerminalBufferSearch.matches(in: buffer, query: findQuery)
        findSelection = findMatches.isEmpty ? 0 : min(findSelection, findMatches.count - 1)
    }

    func stepFind(_ delta: Int) {
        guard !findMatches.isEmpty else { return }
        findSelection = ((findSelection + delta) % findMatches.count + findMatches.count) % findMatches.count
    }

    private func flashStatus(_ text: String) {
        statusNote = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if self?.statusNote == text { self?.statusNote = nil }
        }
    }

    nonisolated private static func readFrontFinderDirectory() -> String? {
        let source = """
        tell application "Finder"
            if (count of windows) > 0 then
                return POSIX path of (target of front window as alias)
            end if
        end tell
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        return result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func attach(_ id: UUID, directory: String?) {
        let session = TerminalSession(id: id, directory: directory, theme: theme)
        session.onTitle = { [weak self] id, title in self?.tabs.setTitle(title, for: id) }
        session.onDirectory = { [weak self] id, dir in self?.tabs.setDirectory(dir, for: id) }
        session.onExit = { [weak self] id in self?.close(id) }
        sessions[id] = session
    }
}

/// Hosts the selected session's SwiftTerm view; switching tabs swaps the subview.
private struct TerminalHost: NSViewRepresentable {
    let session: TerminalSession?

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ container: NSView, context: Context) {
        guard let view = session?.view else { container.subviews.forEach { $0.removeFromSuperview() }; return }
        if view.superview !== container {
            container.subviews.forEach { $0.removeFromSuperview() }
            view.frame = container.bounds
            view.autoresizingMask = [.width, .height]
            container.addSubview(view)
        }
        DispatchQueue.main.async { container.window?.makeFirstResponder(view) }
    }
}

struct TerminalPanelView: View {
    @ObservedObject var model: TerminalPanelModel
    @ObservedObject var arrow: StackPopupArrowModel
    let usesLiquidGlass: Bool
    @Binding var isPinned: Bool
    var onResize: (CGSize) -> Void = { _ in }
    let onClose: () -> Void

    @State private var dragBaseSize: CGSize?

    var body: some View {
        StackUtilityBackdropHost(plateSize: model.plateSize, usesLiquidGlass: usesLiquidGlass, arrow: arrow) {
            VStack(spacing: 0) {
                tabStrip
                if model.isFindPresented {
                    findBar
                }
                Divider().opacity(0.28)
                TerminalHost(session: model.selectedSession)
                    .frame(minHeight: 200)
            }
            .frame(width: model.plateSize.width, height: model.plateSize.height)
            .overlay(alignment: .bottomTrailing) {
                resizeGrip
            }
        }
    }

    private var findBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Find in terminal", text: $model.findQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .onChange(of: model.findQuery) { _, _ in model.refreshFind() }
                .onSubmit { model.refreshFind(); model.stepFind(1) }
            if !model.findMatches.isEmpty {
                let current = model.findMatches[min(model.findSelection, model.findMatches.count - 1)]
                Text(verbatim: "\(model.findSelection + 1)/\(model.findMatches.count) · L\(current.lineIndex + 1)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if !model.findQuery.isEmpty {
                Text("No matches")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Button { model.stepFind(-1) } label: { Image(systemName: "chevron.up").font(.system(size: 10)) }
                .buttonStyle(.plain)
                .disabled(model.findMatches.isEmpty)
            Button { model.stepFind(1) } label: { Image(systemName: "chevron.down").font(.system(size: 10)) }
                .buttonStyle(.plain)
                .disabled(model.findMatches.isEmpty)
            Button {
                model.isFindPresented = false
                model.findQuery = ""
                model.findMatches = []
            } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.06))
    }

    private var resizeGrip: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary.opacity(0.65))
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        let base = dragBaseSize ?? model.plateSize
                        if dragBaseSize == nil { dragBaseSize = base }
                        let target = CGSize(width: base.width + value.translation.width,
                                            height: base.height + value.translation.height)
                        let clamped = TerminalPanelSizeBounds.clamped(target)
                        onResize(clamped)
                    }
                    .onEnded { _ in
                        dragBaseSize = nil
                        TerminalPanelSizeBounds.save(model.plateSize)
                    }
            )
            .help(Text("Resize Terminal"))
            .accessibilityLabel(Text("Resize Terminal"))
    }

    private var tabStrip: some View {
        HStack(spacing: 6) {
            ForEach(model.tabs.tabs) { tab in
                HStack(spacing: 4) {
                    Text(verbatim: tab.displayTitle).lineLimit(1).font(.system(size: 12))
                    if model.tabs.tabs.count > 1 {
                        Button { model.close(tab.id) } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(tab.id == model.tabs.selectedID ? 0.18 : 0.06)))
                .onTapGesture { model.select(tab.id) }
            }
            if model.tabs.canAdd {
                Button { model.newTab() } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("New Tab"))
            }
            Spacer()
            if let note = model.statusNote {
                Text(verbatim: note)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Button { model.syncFinderDirectory() } label: { Image(systemName: "folder.badge.gearshape") }
                .buttonStyle(.plain)
                .help(Text("Sync Finder Folder"))
                .accessibilityLabel(Text("Sync Finder Folder"))
            Menu {
                ForEach(TerminalSnippet.defaultSnippets) { snippet in
                    Button { model.sendSnippet(snippet) } label: { Text(verbatim: snippet.title) }
                }
            } label: {
                Image(systemName: "text.insert")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(Text("Snippets"))
            .accessibilityLabel(Text("Snippets"))
            Menu {
                ForEach(TerminalThemePreset.allCases) { preset in
                    Button { model.setTheme(preset) } label: {
                        HStack {
                            Text(verbatim: preset.title)
                            if model.theme == preset { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                Image(systemName: "paintpalette")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(Text("Theme"))
            .accessibilityLabel(Text("Theme"))
            Button {
                model.isFindPresented.toggle()
                if model.isFindPresented { model.refreshFind() }
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: .command)
            .help(Text("Find"))
            .accessibilityLabel(Text("Find"))
            DockUtilityPinButton(isPinned: $isPinned)
            Button(action: onClose) { Image(systemName: "chevron.down") }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Hide Terminal"))
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }
}
