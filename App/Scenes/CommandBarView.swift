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
    @Published var sections: [CommandBarSectionGroup] = []
    @Published var activeToken: CommandQueryToken?
    @Published var selection = 0
    @Published var isActionPanelPresented: Bool = false
    @Published var actionSelection = 0

    var currentActions: [CommandBarActionItem] {
        guard results.indices.contains(selection) else { return [] }
        return CommandBarActionResolver.actions(for: results[selection])
    }
    var focusNonce = 0
    var apps: [LauncherApp] = []
    var running: [RunningAppRef] = []
    var usage: [String: LauncherUsage] = [:]
    var custom: [CustomCommand] = []
    var quicklinks: [Quicklink] = []
    var processes: [ProcessEntry] = []
    var files: [FileEntry] = []
    var clips: [ClipEntry] = []
    var bookmarks: [Bookmark] = []
    var events: [EventEntry] = []
    var menuItems: [MenuSearchEntry] = []
    var profiles: [BarProfileSummary] = []

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
        activeToken = CommandBarQueryParser.parse(query, quicklinks: quicklinks).token
        let built = CommandBarResults.build(query: query, apps: apps, usage: usage, running: running,
                                            custom: custom, quicklinks: quicklinks, processes: processes, files: files, clips: clips,
                                            bookmarks: bookmarks, events: events, menuItems: menuItems, profiles: profiles,
                                            generate: { [weak self] in self?.generateValue(for: $0) ?? "" })
        let isEmptyQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let grouped = CommandBarSectionStore.group(built, isEmptyQuery: isEmptyQuery)
        sections = grouped
        let orderedItems = grouped.flatMap(\.items)
        results = orderedItems.map(\.result)
        rowItems = orderedItems.map { CommandBarRowItem(id: $0.id, index: $0.flatIndex, result: $0.result) }
        if shouldReset {
            selection = 0
        } else {
            selection = results.isEmpty ? 0 : min(selection, results.count - 1)
        }
    }

    func clearActiveToken() {
        guard let token = activeToken else { return }
        query = token.remainingQuery
        refresh(resetSelection: true)
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
    var onAction: ((CommandBarActionItem) -> Void)? = nil
    @FocusState private var focused: Bool
    @AppStorage("com.katikati.commandbar.hints") private var showHints = true
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dockThemeStyle) private var dockThemeStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: DockThemeTokens { .resolved(for: colorScheme, style: dockThemeStyle) }

    private var primaryActionLabel: String {
        guard model.results.indices.contains(model.selection) else { return String(localized: "Open") }
        switch model.results[model.selection] {
        case .answer(.math), .generator, .clip, .emoji:
            return String(localized: "Copy")
        case .action, .quit, .forceQuit, .process, .script, .shortcut, .trash, .saveProfile:
            return String(localized: "Run")
        case .define:
            return String(localized: "Define")
        case .menuItem:
            return String(localized: "Select")
        default:
            return String(localized: "Open")
        }
    }

    private func sectionTitle(for kind: CommandBarSectionKind) -> String {
        switch kind {
        case .suggestions: return String(localized: "Suggestions")
        case .commands: return String(localized: "Commands")
        case .applications: return String(localized: "Applications")
        case .files: return String(localized: "Files")
        }
    }

    private func badgeTitle(for badge: CommandBarResultBadge) -> String {
        switch badge {
        case .quicklink: return String(localized: "Quicklink")
        case .application: return String(localized: "Application")
        case .command: return String(localized: "Command")
        case .file: return String(localized: "File")
        }
    }

    private func tokenTitle(for token: CommandQueryToken) -> String {
        switch token.scope {
        case .googleSearch: return String(localized: "Search Google")
        case .calculator: return String(localized: "Calculator")
        case .applications: return String(localized: "Applications")
        case .files: return String(localized: "Files")
        case .mode(let mode): return mode.displayName
        case .quicklink(let link): return link.name
        }
    }

    private func tokenBadgeTitle(for token: CommandQueryToken) -> String {
        switch token.scope {
        case .googleSearch, .files, .quicklink: return String(localized: "Query")
        case .calculator: return String(localized: "Expression")
        case .applications, .mode: return String(localized: "Filter")
        }
    }

    private var canQuickLook: Bool {
        guard model.results.indices.contains(model.selection) else { return false }
        switch model.results[model.selection] {
        case .file, .path: return true
        default: return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            Divider().opacity(0.22)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(model.sections.enumerated()), id: \.element.id) { sectionIdx, section in
                            Text(verbatim: sectionTitle(for: section.kind))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary.opacity(0.85))
                                .padding(.horizontal, 10)
                                .padding(.top, sectionIdx == 0 ? 4 : 10)
                                .padding(.bottom, 3)

                            ForEach(section.items) { item in
                                row(item.result, badge: item.metadata.badge, index: item.flatIndex, selected: item.flatIndex == model.selection)
                                    .id(item.id)
                                    .onTapGesture { onRun(item.result) }
                                    .contextMenu { rowMenu(item.result) }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .onChange(of: model.selection) { value in
                    let items = model.rowItems
                    if items.indices.contains(value) {
                        let targetID = items[value].id
                        if reduceMotion {
                            proxy.scrollTo(targetID, anchor: .center)
                        } else {
                            withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(targetID, anchor: .center) }
                        }
                    }
                }
                .onChange(of: model.query) { _ in
                    if let firstID = model.rowItems.first?.id {
                        proxy.scrollTo(firstID, anchor: .top)
                    }
                }
            }
            Divider().opacity(0.22)
            footer
        }
        .frame(width: 640, height: 380)
        .background(DockPanelBackdrop(theme: theme, cornerRadius: 16, usesLiquidGlass: false))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .dockPanelRim(cornerRadius: 16, style: theme.panelRimStyle, lineWidth: theme.panelRimLineWidth, usesLiquidGlass: false)
        .overlay(alignment: .bottomTrailing) {
            if model.isActionPanelPresented && !model.currentActions.isEmpty {
                CommandBarActionPanelView(
                    actions: model.currentActions,
                    selection: model.actionSelection,
                    onSelect: { action in
                        model.isActionPanelPresented = false
                        onAction?(action)
                    }
                )
                .padding(.trailing, 12)
                .padding(.bottom, 40)
                .transition(reduceMotion
                            ? .opacity
                            : .asymmetric(insertion: .scale(scale: 0.96, anchor: .bottomTrailing).combined(with: .opacity),
                                          removal: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.86), value: model.isActionPanelPresented)
        .onAppear { focused = true }
        .onChange(of: model.focusNonce) { _ in focused = true }
        .accessibilityLabel(Text("Command Bar"))
    }

    private var searchHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: model.activeToken?.symbol ?? "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(model.activeToken == nil ? .secondary : .accentColor)

            TextField("Command Bar", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($focused)
                .onChange(of: model.query) { _ in model.refresh() }
                .onSubmit {
                    if model.results.indices.contains(model.selection) {
                        onRun(model.results[model.selection])
                    } else if let first = model.results.first {
                        onRun(first)
                    }
                }

            if let token = model.activeToken {
                HStack(spacing: 5) {
                    Text(verbatim: tokenTitle(for: token))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.85))
                    Text(verbatim: tokenBadgeTitle(for: token))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.10)))
                    Button {
                        model.clearActiveToken()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))
            }

            if !model.query.isEmpty {
                Button {
                    model.query = ""
                    model.refresh(resetSelection: true)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary.opacity(0.6))
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
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

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: "command.square.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary.opacity(0.75))

            if showHints {
                HStack(spacing: 4) {
                    ForEach(["g", "calc", "app", "file", "clip"], id: \.self) { key in
                        Text(verbatim: key)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.85))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.06)))
                    }
                }
            }

            Spacer(minLength: 0)

            Button {
                if model.results.indices.contains(model.selection) {
                    onRun(model.results[model.selection])
                }
            } label: {
                HStack(spacing: 6) {
                    Text(verbatim: primaryActionLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                    footerKeycap(systemImage: "return")
                }
            }
            .buttonStyle(.plain)

            if canQuickLook {
                footerDivider
                HStack(spacing: 5) {
                    Text("Quick Look")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    footerKeycap("⌘")
                    footerKeycap("Y")
                }
            }

            footerDivider

            Button {
                model.isActionPanelPresented.toggle()
                model.actionSelection = 0
            } label: {
                HStack(spacing: 5) {
                    Text("Actions")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    footerKeycap("⌘")
                    footerKeycap("K")
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var footerDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.14))
            .frame(width: 1, height: 13)
    }

    private func footerKeycap(_ text: String? = nil, systemImage: String? = nil) -> some View {
        Group {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
            } else if let text {
                Text(verbatim: text)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
        }
        .foregroundColor(.secondary)
        .frame(minWidth: 20, minHeight: 20)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(0.08))
        )
    }

    @ViewBuilder private func row(_ result: CommandBarResult, badge: CommandBarResultBadge, index: Int, selected: Bool) -> some View {
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
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: macro.title).font(.system(size: 13, weight: .medium))
                    Text(verbatim: macro.subtitle).font(.system(size: 11)).foregroundColor(.secondary)
                }
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
            case .profile(let summary):
                Text(verbatim: summary.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text("Bar profile").font(.system(size: 11)).foregroundColor(.secondary)
                Spacer(minLength: 0)
            case .define(let word):
                Text(verbatim: word).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text("Define in Dictionary").font(.system(size: 11)).foregroundColor(.secondary)
                Spacer(minLength: 0)
            case .saveProfile(let name):
                Text("Save current bar as profile").font(.system(size: 13, weight: .medium))
                Text(verbatim: name).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            case .menuItem(let entry):
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: entry.title).lineLimit(1)
                    Text(verbatim: entry.breadcrumb).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                }
                .opacity(entry.isEnabled ? 1 : 0.45)
                Spacer(minLength: 0)
                if let shortcut = entry.shortcut {
                    Text(verbatim: shortcut).font(.system(size: 12, design: .rounded)).foregroundColor(.secondary)
                }
            case .quicklink(let link, let argument):
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: link.name).font(.system(size: 13, weight: .medium))
                    Text(verbatim: argument.isEmpty ? link.template : QuicklinkTemplate.expand(link.template, values: QuicklinkValues(query: argument)))
                        .font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            case .searchFilesFallback(let term):
                Text("Search Files")
                Text(verbatim: term).foregroundColor(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            case .askAI(let term):
                Text("Ask AI")
                Text(verbatim: term).foregroundColor(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Text(verbatim: badgeTitle(for: badge))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary.opacity(selected ? 0.95 : 0.78))

                if showHints && index < 9 {
                    Text(verbatim: "⌘\(index + 1)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.06)))
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.09) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(selected ? Color.primary.opacity(0.08) : Color.clear, lineWidth: 0.5)
        )
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
            Image(systemName: command.kind == .link ? "link" : (command.kind == .snippet ? "text.append" : "terminal")).font(.system(size: 15, weight: .semibold)).frame(width: 24, height: 24)
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
        case .profile, .saveProfile:
            Image(systemName: "rectangle.3.group").font(.system(size: 15, weight: .semibold)).frame(width: 24, height: 24)
        case .define:
            Image(systemName: "character.book.closed").font(.system(size: 15, weight: .semibold)).frame(width: 24, height: 24)
        case .menuItem:
            Image(systemName: "filemenu.and.selection").font(.system(size: 15, weight: .semibold)).frame(width: 24, height: 24)
        case .quicklink:
            Image(systemName: "link").font(.system(size: 15, weight: .semibold)).frame(width: 24, height: 24)
        case .searchFilesFallback:
            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 15, weight: .semibold)).frame(width: 24, height: 24)
        case .askAI:
            Image(systemName: "sparkles").font(.system(size: 15, weight: .semibold)).frame(width: 24, height: 24)
        }
    }
}

/// ⌘K action panel popover for the Command Bar (Slice 1.3).
struct CommandBarActionPanelView: View {
    let actions: [CommandBarActionItem]
    let selection: Int
    let onSelect: (CommandBarActionItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: "ACTIONS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                Text(verbatim: "Esc")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 2)

            Divider().opacity(0.2)

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(actions.enumerated()), id: \.offset) { idx, action in
                        CommandBarActionRow(action: action, isSelected: idx == selection) {
                            onSelect(action)
                        }
                    }
                }
                .padding(4)
            }
            .frame(maxHeight: 200)
        }
        .frame(width: 250)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.28), radius: 12, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14))
        )
    }
}

private struct CommandBarActionRow: View {
    let action: CommandBarActionItem
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(action.title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundColor(action.isDestructive ? Color.red : Color.primary)
            Spacer(minLength: 8)
            if let shortcut = action.shortcutHint {
                Text(shortcut)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.06)))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}
