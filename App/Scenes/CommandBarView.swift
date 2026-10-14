import AppKit
import SwiftUI

struct CommandBarRowItem: Identifiable, Equatable {
    let id: String
    let index: Int
    let result: CommandBarResult
}

/// Phase 27b: the command-bar's state. The controller fills `apps`/`running`/`usage` at summon; the view
/// edits `query` and reads `results`. `selection` is driven by the controller's key monitor.
@MainActor
final class CommandBarModel: ObservableObject {
    @Published var query = ""
    @Published var results: [CommandBarResult] = []
    @Published var rowItems: [CommandBarRowItem] = []
    @Published var selection = 0
    var focusNonce = 0
    var apps: [LauncherApp] = []
    var running: [RunningAppRef] = []
    var usage: [String: LauncherUsage] = [:]
    var custom: [CustomCommand] = []
    var processes: [ProcessEntry] = []
    var files: [FileEntry] = []
    var clips: [ClipEntry] = []
    var bookmarks: [Bookmark] = []
    var events: [EventEntry] = []

    private var cachedWifi: (password: String, date: Date)?
    private var isFetchingWifiPassword = false
    private var lastQuery: String?

    func generateValue(for generator: CommandGenerator) -> String {
        switch generator {
        case .wifiPassword:
            if let cached = cachedWifi, Date().timeIntervalSince(cached.date) < 60 {
                return cached.password
            }
            if !isFetchingWifiPassword {
                isFetchingWifiPassword = true
                Task.detached(priority: .userInitiated) {
                    let pwd = GeneratorService.wifiPassword()
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.isFetchingWifiPassword = false
                        if let pwd, !pwd.isEmpty {
                            self.cachedWifi = (password: pwd, date: Date())
                        }
                        let trimmed = self.query.trimmingCharacters(in: .whitespaces).lowercased()
                        if trimmed == "wifi" {
                            self.refresh()
                        }
                    }
                }
            }
            return ""
        default:
            return GeneratorService.value(for: generator) ?? ""
        }
    }

    func refresh(resetSelection: Bool = false) {
        let shouldReset = resetSelection || (query != lastQuery)
        lastQuery = query
        results = CommandBarResults.build(query: query, apps: apps, usage: usage, running: running,
                                          custom: custom, processes: processes, files: files, clips: clips,
                                          bookmarks: bookmarks, events: events,
                                          generate: { [weak self] in self?.generateValue(for: $0) ?? "" })
        var seen = [String: Int]()
        rowItems = results.enumerated().map { index, result in
            let base = result.id
            let count = seen[base, default: 0]
            seen[base] = count + 1
            let uniqueID = count == 0 ? base : "\(base)#\(count)"
            return CommandBarRowItem(id: uniqueID, index: index, result: result)
        }
        if shouldReset {
            selection = 0
        } else {
            selection = results.isEmpty ? 0 : min(selection, results.count - 1)
        }
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(selection + delta, 0), results.count - 1)
    }
}

/// The compact palette: a search field over one result list. Reuses the Phase 21 answer rows and the
/// launcher index; actions are routed by the controller.
struct CommandBarView: View {
    @ObservedObject var model: CommandBarModel
    let onRun: (CommandBarResult) -> Void
    let onClose: () -> Void
    let onRemove: (LauncherApp, AppRemoval) -> Void
    @FocusState private var focused: Bool
    @AppStorage("com.katikati.commandbar.hints") private var showHints = true

    var body: some View {
        VStack(spacing: 0) {
            TextField("Command Bar", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .focused($focused)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .onChange(of: model.query) { _ in model.refresh() }
                .onSubmit {
                    if model.results.indices.contains(model.selection) {
                        onRun(model.results[model.selection])
                    } else if let first = model.results.first {
                        onRun(first)
                    }
                }
            Divider().opacity(0.25)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(model.rowItems) { item in
                            row(item.result, selected: item.index == model.selection)
                                .id(item.id)
                                .onTapGesture { onRun(item.result) }
                                .contextMenu { rowMenu(item.result) }
                        }
                    }
                    .padding(6)
                }
                .onChange(of: model.selection) { value in
                    let items = model.rowItems
                    if items.indices.contains(value) {
                        let targetID = items[value].id
                        withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(targetID, anchor: .center) }
                    }
                }
                .onChange(of: model.query) { _ in
                    if let firstID = model.rowItems.first?.id {
                        proxy.scrollTo(firstID, anchor: .top)
                    }
                }
            }
            if showHints { footer }
        }
        .frame(width: 640, height: 380)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .onAppear { focused = true }
        .onChange(of: model.focusNonce) { _ in focused = true }
        .accessibilityLabel(Text("Command Bar"))
    }

    @ViewBuilder private func rowMenu(_ result: CommandBarResult) -> some View {
        switch result {
        case .app(let app):
            Button("Uninstall…") { onRemove(app, .uninstall) }
            Button("Delete Data…") { onRemove(app, .deleteData) }
        case .trash(.empty):
            Button("Empty Without Confirmation") { onRun(.trash(.emptyWithoutConfirmation)) }
        default:
            EmptyView()
        }
    }

    /// The removable hints strip (Phase 29i): the major keywords as plain chips, plus a ✕ to hide it.
    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: "return").font(.system(size: 10, weight: .semibold))
            ForEach(["f", "img", "clip", "kill", "fq", "kp", "sc", "ocr", "cs"], id: \.self) { key in
                Text(verbatim: key)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.08)))
            }
            Spacer(minLength: 0)
            Button { showHints = false } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).font(.system(size: 9))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .foregroundColor(.secondary)
    }

    @ViewBuilder private func row(_ result: CommandBarResult, selected: Bool) -> some View {
        HStack(spacing: 10) {
            icon(result)
            switch result {
            case .answer(.math(_, let value)):
                Text(verbatim: value).font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 0)
            case .answer(.web(let query)):
                Text("Search the Web")
                Text(verbatim: query).foregroundColor(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            case .app(let app):
                Text(verbatim: app.name)
                Spacer(minLength: 0)
            case .quit(let running):
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: running.name)
                    Text("Quit").font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            case .forceQuit(let running):
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: running.name)
                    Text("Force Quit").font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            case .action(let macro):
                Text(verbatim: macro.keyword).font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            case .generator(let generator, let value):
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: generator.displayName).font(.system(size: 13, weight: .medium))
                    Text(verbatim: value).font(.system(size: 12, design: .monospaced)).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            case .custom(let command):
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: command.name).font(.system(size: 13, weight: .medium))
                    Text(verbatim: command.target).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            case .process(let entry):
                Text(verbatim: entry.name)
                Text(verbatim: "\(entry.pid)").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                Spacer(minLength: 0)
            case .script(let payload):
                Text("Run Script").font(.system(size: 13, weight: .medium))
                Text(verbatim: payload).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            case .shortcut(let name):
                Text("Shortcuts").font(.system(size: 13, weight: .medium))
                Text(verbatim: name).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            case .path(let path):
                Text(verbatim: (path as NSString).lastPathComponent)
                Text(verbatim: path).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            case .file(let entry):
                Text(verbatim: entry.name)
                Text(verbatim: entry.path).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            case .clip(let entry):
                Text(verbatim: ClipboardHistory.previewLine(entry.text)).lineLimit(1)
                Spacer(minLength: 0)
            case .trash(let action):
                Text(action == .open ? "Open Trash" : "Empty Trash")
                Spacer(minLength: 0)
            case .emoji(let entry):
                Text(verbatim: entry.char).font(.system(size: 18))
                Text(verbatim: entry.name).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            case .bookmark(let bookmark):
                Text(verbatim: bookmark.title).lineLimit(1)
                Text(verbatim: bookmark.url).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            case .event(let event):
                Text(verbatim: event.title).lineLimit(1)
                Text(verbatim: event.start.formatted(date: .abbreviated, time: event.allDay ? .omitted : .shortened))
                    .font(.system(size: 11)).foregroundColor(.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Color.accentColor.opacity(0.22) : Color.clear))
        .contentShape(Rectangle())
    }

    @ViewBuilder private func icon(_ result: CommandBarResult) -> some View {
        switch result {
        case .answer(.math):
            Image(systemName: "equal").font(.system(size: 15, weight: .semibold)).frame(width: 24, height: 24)
        case .answer(.web):
            Image(systemName: "globe").font(.system(size: 15, weight: .semibold)).frame(width: 24, height: 24)
        case .app(let app):
            Image(nsImage: LauncherIconCache.icon(forPath: app.path))
                .resizable().aspectRatio(contentMode: .fit).frame(width: 24, height: 24)
        case .quit(let running):
            Image(nsImage: LauncherIconCache.icon(forPath: running.path))
                .resizable().aspectRatio(contentMode: .fit).frame(width: 24, height: 24)
        case .forceQuit(let running):
            Image(nsImage: LauncherIconCache.icon(forPath: running.path))
                .resizable().aspectRatio(contentMode: .fit).frame(width: 24, height: 24)
        case .action(let macro):
            Image(systemName: macro.symbol).font(.system(size: 15, weight: .semibold)).frame(width: 24, height: 24)
        case .generator:
            Image(systemName: "wand.and.stars").font(.system(size: 15, weight: .semibold)).frame(width: 24, height: 24)
        case .custom(let command):
            Image(systemName: command.kind == .link ? "link" : "terminal").font(.system(size: 15, weight: .semibold)).frame(width: 24, height: 24)
        case .process:
            Image(systemName: "bolt.slash").font(.system(size: 15, weight: .semibold)).frame(width: 24, height: 24)
        case .script:
            Image(systemName: "terminal").font(.system(size: 15, weight: .semibold)).frame(width: 24, height: 24)
        case .shortcut:
            Image(systemName: "bolt.fill").font(.system(size: 15, weight: .semibold)).frame(width: 24, height: 24)
        case .path:
            Image(systemName: "doc").font(.system(size: 15, weight: .semibold)).frame(width: 24, height: 24)
        case .file(let entry):
            Image(nsImage: LauncherIconCache.icon(forPath: entry.path))
                .resizable().aspectRatio(contentMode: .fit).frame(width: 24, height: 24)
        case .clip:
            Image(systemName: "doc.on.clipboard").font(.system(size: 15, weight: .semibold)).frame(width: 24, height: 24)
        case .trash(let action):
            Image(systemName: action.symbol).font(.system(size: 15, weight: .semibold)).frame(width: 24, height: 24)
        case .emoji(let entry):
            Text(verbatim: entry.char).font(.system(size: 20)).frame(width: 24, height: 24)
        case .bookmark:
            Image(systemName: "bookmark").font(.system(size: 15, weight: .semibold)).frame(width: 24, height: 24)
        case .event:
            Image(systemName: "calendar").font(.system(size: 15, weight: .semibold)).frame(width: 24, height: 24)
        }
    }
}
