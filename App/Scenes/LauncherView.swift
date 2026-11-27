import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Icons are cached by path; the system already memoises file icons, this just avoids re-sizing per redraw.
enum LauncherIconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(forPath path: String) -> NSImage {
        if let hit = cache.object(forKey: path as NSString) { return hit }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 128, height: 128)
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}

/// One recent file or Finder folder item surfaced in Recommended & search results.
struct LauncherRecentItem: Equatable, Identifiable, Sendable {
    var id: String { path }
    let name: String
    let path: String
    let subtitle: String
}

/// What the user can do to an app from the launcher (right-click menu, drag to reorder).
struct LauncherActions {
    let launch: (LauncherApp) -> Void
    let togglePin: (LauncherApp) -> Void
    let toggleHidden: (LauncherApp) -> Void
    let reveal: (LauncherApp) -> Void
    let copyPath: (LauncherApp) -> Void
    /// Moves the app in front of `target` in All Apps (nil = to the very start).
    let move: (_ bundleID: String, _ target: LauncherApp?) -> Void
    let close: () -> Void
    /// Saves `model.state` (hide presets, etc.) after the gear popover edits it.
    let persist: () -> Void
    /// Return with no matching app: open the URL or search the web.
    let quickAction: (LauncherQuickAction) -> Void
    /// Edit mode: `dragged` dropped on `target` makes a folder (or joins the target folder).
    let dropOnto: (_ dragged: String, _ target: LauncherApp) -> Void
    /// Menu: start a folder holding just this app.
    let newFolder: (LauncherApp) -> Void
    /// Move the app bundle to the Trash (confirmed).
    let uninstall: (LauncherApp) -> Void
    /// Move the app's support files to the Trash (confirmed).
    let deleteData: (LauncherApp) -> Void
    let runMacro: (BarMacro) -> Void
    let quitApp: (LauncherApp) -> Void
    let isKeptInDock: (String) -> Bool
    let toggleKeepInDock: (LauncherApp) -> Void
    let openPlace: (URL) -> Void
    let openSettings: () -> Void
}

/// The launcher surface: multi-preset app launcher (`Windows Start`, `Linux Menu`, `Drawer`, `Centered`, `Fullscreen`).
struct LauncherView: View {
    @ObservedObject var indexer: LauncherIndexer
    @ObservedObject var model: LauncherModel
    let actions: LauncherActions
    @ObservedObject private var monitor = SystemMonitorController.shared

    private static let gap = 12.0
    private static let rowSpacing = 20.0
    /// Height of the caption + divider slot above each section (page 1 and later pages reserve the same one).
    private static let slotHeight = 30.0
    private static let dotsHeight = 36.0
    @State private var dragX: CGFloat = 0
    @State private var showGear = false
    @State private var holdsTelemetry = false
    @State private var hoverCategoryTask: Task<Void, Never>?
    @AppStorage("com.katikati.launcher.drawerStyle") private var drawerStyleRaw: String = LauncherDrawerViewStyle.grid.rawValue
    @AppStorage("com.katikati.theme.followDockTheme") private var followDockTheme = true
    @AppStorage("com.katikati.theme.material") private var dockThemeToken = DockThemeStyle.auto.token
    @Environment(\.colorScheme) private var colorScheme

    private var activeDockTheme: DockThemeStyle {
        followDockTheme ? (DockThemeStyle(token: dockThemeToken) ?? .auto) : .auto
    }

    private enum LauncherDrawerViewStyle: String { case grid, list }
    private var drawerStyle: LauncherDrawerViewStyle {
        LauncherDrawerViewStyle(rawValue: drawerStyleRaw) ?? .grid
    }

    private var matches: [LauncherApp] {
        guard model.prefs.searchScope.apps else { return [] }
        return LauncherSearch.search(model.query, in: indexer.apps, usage: model.state.usage)
    }

    private var matchingActions: [BarMacro] {
        guard model.prefs.searchScope.systemActions, !model.query.isEmpty else { return [] }
        return LauncherActionSearch.matching(model.query, limit: 4)
    }

    private var matchingFolders: [LauncherFolder] {
        guard model.prefs.searchScope.appGroups, !model.query.isEmpty else { return [] }
        return model.state.folders.filter { LauncherMatch.score(query: model.query, name: $0.name) != nil }
    }

    private var matchingFiles: [LauncherRecentItem] {
        guard model.prefs.searchScope.recentFiles, !model.query.isEmpty else { return [] }
        let q = model.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        var out = model.recentFiles.filter { LauncherMatch.score(query: q, name: $0.name) != nil }
        var seen = Set(out.map(\.path))
        let terms = q.split(separator: " ").map(String.init)
        for f in FileIndexService.shared.search(terms: terms, extensions: [], imageOnly: false, limit: 4) ?? [] where !seen.contains(f.path) {
            seen.insert(f.path)
            out.append(LauncherRecentItem(name: f.name, path: f.path, subtitle: URL(fileURLWithPath: f.path).deletingLastPathComponent().lastPathComponent))
            if out.count >= 4 { break }
        }
        return Array(out.prefix(4))
    }

    private var hasAnySearchResult: Bool {
        !matches.isEmpty || !answers.isEmpty || isRunnable || !matchingActions.isEmpty || !matchingFolders.isEmpty || !matchingFiles.isEmpty
    }

    /// Phase 21b: math/web answer rows for a routed query (`=2+2`, `@swift news`).
    private var routed: LauncherQuery { LauncherCommandParser.parse(model.query) }
    private var answers: [LauncherAnswer] { LauncherAnswers.answers(for: routed) }
    /// Phase 21c: the query is a runnable script/shortcut and the user has scripts switched on.
    private var isRunnable: Bool {
        guard LauncherRunner.isEnabled else { return false }
        switch routed { case .script, .shortcut: return true; default: return false }
    }

    var body: some View {
        Group {
            switch model.presentation {
            case .windowsStart:
                windowsStartBody
            case .linuxMenu:
                linuxMenuBody
            case .drawer:
                drawerBody
            default:
                classicBody
            }
        }
        .background(pageShortcuts)
        .onAppear { syncTelemetrySampling(model.prefs.showFooterTelemetry) }
        .onChange(of: model.prefs.showFooterTelemetry) { syncTelemetrySampling($0) }
        .onDisappear {
            hoverCategoryTask?.cancel()
            hoverCategoryTask = nil
            syncTelemetrySampling(false)
        }
        .background {
            if followDockTheme, activeDockTheme.tintsPlate {
                let tokens = DockThemeTokens.resolved(for: colorScheme, style: activeDockTheme)
                tokens.styleTokens.baseTint.color.opacity(colorScheme == .dark ? 0.22 : 0.14)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .environment(\.dockThemeStyle, activeDockTheme)
        .accessibilityLabel(Text("Launcher"))
    }

    @ViewBuilder private var classicBody: some View {
        let inset = model.searchPosition.reservedInsets(sheetSide: .right, sheetWidth: 0)
        ZStack {
            Color.black.opacity(0.001).onTapGesture(perform: actions.close)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    if model.searchPosition == .top {
                        Spacer(minLength: 0)
                        searchFieldCluster
                        Spacer(minLength: 0)
                    } else {
                        Spacer(minLength: 0)
                    }
                    toolbar
                }
                .padding(.top, 14 + model.screenInsets.top)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)

                content
                    .padding(.bottom, (model.searchPosition == .bottom ? inset.bottom : 0) + model.screenInsets.bottom)
                    .padding(.leading, (model.searchPosition == .left ? inset.leading : 0) + model.screenInsets.leading)
                    .padding(.trailing, (model.searchPosition == .right ? inset.trailing : 0) + model.screenInsets.trailing)
            }
            if model.searchPosition != .top {
                searchField
                    .padding(.top, model.screenInsets.top).padding(.bottom, model.screenInsets.bottom)
                    .padding(.leading, model.screenInsets.leading).padding(.trailing, model.screenInsets.trailing)
            }
            if let folder = openFolder { folderOverlay(folder) }
        }
    }

    private func syncTelemetrySampling(_ active: Bool) {
        if active, !holdsTelemetry {
            holdsTelemetry = true
            monitor.acquire()
        } else if !active, holdsTelemetry {
            holdsTelemetry = false
            monitor.release()
        }
    }

    /// ⌘1–⌘9 jump to a page (invisible buttons; only the key equivalents matter).
    private var pageShortcuts: some View {
        ZStack {
            ForEach(1...9, id: \.self) { n in
                Button { if model.query.isEmpty { model.pageJumps.send(n - 1) } } label: { Text(verbatim: "") }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
                    .opacity(0).frame(width: 0, height: 0)
            }
        }
    }

    private var openFolder: LauncherFolder? {
        model.openFolderID.flatMap { id in model.state.folders.first { $0.id == id } }
    }

    private var searchFieldCluster: some View {
        HStack(spacing: 8) {
            LauncherSearchField(text: $model.query, focusNonce: model.focusNonce,
                                onSubmit: {
                                    if let id = model.focusedID, let item = model.layoutItems[id] { activate(item) }
                                    else if let answer = answers.first { run(answer) }
                                    else if isRunnable { _ = LauncherRunner.run(routed) }
                                    else if let macro = matchingActions.first, matches.isEmpty { actions.runMacro(macro) }
                                    else if let first = matches.first { actions.launch(first) }
                                    else if let folder = matchingFolders.first { model.openFolderID = folder.id }
                                    else if let file = matchingFiles.first { actions.openPlace(URL(fileURLWithPath: file.path)) }
                                    else if let q = LauncherQuickAction.resolve(model.query) { actions.quickAction(q) }
                                },
                                onCommandSubmit: {
                                    if let target = keyboardTargetApp { actions.reveal(target) }
                                },
                                onOptionSubmit: {
                                    if let target = keyboardTargetApp, model.runningIDs.contains(target.bundleID) {
                                        actions.quitApp(target)
                                    }
                                },
                                onCancel: {
                                    if model.openFolderID != nil { model.openFolderID = nil }
                                    else if model.showingAllApps { model.showingAllApps = false }
                                    else if model.editing { model.editing = false }
                                    else if !model.query.isEmpty { model.query = "" }
                                    else { actions.close() }
                                },
                                onTab: { delta in handleTab(delta) },
                                onArrow: { arrow(dx: $0, dy: $1) })
                .frame(maxWidth: model.presentation == .windowsStart || model.presentation == .linuxMenu ? .infinity : model.searchPosition.fieldWidth)
                .frame(height: 28)
            Button {
                actions.quickAction(.askAI(model.query))
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.accentColor.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .help(Text("Ask AI"))
            .accessibilityLabel(Text("Ask AI"))
            Button {
                DictationController.shared.toggle()
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DictationController.shared.isRecording ? .red : .secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help(Text("Voice Dictation"))
            .accessibilityLabel(Text("Voice Dictation"))
        }
    }

    private var searchField: some View {
        let p = model.searchPosition
        return searchFieldCluster
            .padding(p == .top ? .top : p == .bottom ? .bottom : p == .left ? .leading : .trailing, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(p))
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button { model.editing.toggle(); model.openFolderID = nil } label: {
                Group { if model.editing { Text("Done") } else { Text("Edit") } }
                    .font(.system(size: 12, weight: .semibold)).padding(.horizontal, 12).frame(height: 30)
                    .background(Capsule().fill(model.editing ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.12)))
            }
            .buttonStyle(.plain)
            Menu {
                Picker("Sort By", selection: $model.prefs.sort) {
                    Text("Custom Order").tag(LauncherSortMode.custom)
                    Text("Name").tag(LauncherSortMode.name)
                    Text("Most Used").tag(LauncherSortMode.mostUsed)
                    Text("Recently Added").tag(LauncherSortMode.recentlyAdded)
                    Text("Category").tag(LauncherSortMode.category)
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30).background(Circle().fill(Color.primary.opacity(0.12)))
            }
            .menuStyle(.borderlessButton).fixedSize()
            .help(Text("Sort By"))
            .accessibilityLabel(Text("Sort By"))
            Button { showGear.toggle() } label: {
                Image(systemName: "gearshape.fill").font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30).background(Circle().fill(Color.primary.opacity(0.12)))
            }
            .buttonStyle(.plain).help(Text("Launcher Settings"))
            .accessibilityLabel(Text("Launcher Settings"))
            .popover(isPresented: $showGear, arrowEdge: .bottom) { LauncherGearPopover(model: model, actions: actions) }
            Button(action: actions.close) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30).background(Circle().fill(Color.primary.opacity(0.12)))
            }
            .buttonStyle(.plain).help(Text("Close"))
            .accessibilityLabel(Text("Close"))
        }
    }

    private func alignment(_ p: LauncherSearchPosition) -> Alignment {
        switch p {
        case .top: return .top
        case .bottom: return .bottom
        case .left: return .leading
        case .right: return .trailing
        }
    }

    /// Grid metrics shared by every layout: 8 columns (fewer on a narrow screen), icons sized to the cell.
    private struct Metrics {
        let columns: Int
        let icon: CGFloat
        let rowHeight: Double
        let width: Double
    }

    private func metrics(width available: Double) -> Metrics {
        let width = min(available - 112, 1500)
        let fit = LauncherGrid.columns(forWidth: width, minCell: 84, gap: Self.gap)
        let columns = model.prefs.columns > 0 ? min(model.prefs.columns, max(1, fit)) : min(8, fit)
        let cellWidth = (width - Double(columns - 1) * Self.gap) / Double(columns)
        let icon = CGFloat(min(max(cellWidth * 0.68, 56), 150) * model.prefs.iconScale)
        // icon + gap + one line of label + the space between rows
        return Metrics(columns: columns, icon: icon, rowHeight: Double(icon) + 8 + 18 + Self.rowSpacing, width: width)
    }

    @ViewBuilder private var content: some View {
        GeometryReader { proxy in
            let m = metrics(width: Double(proxy.size.width))
            if model.query.isEmpty {
                let page = LauncherAppIndex.page(apps: indexer.apps, usage: model.state.usage,
                                                 pinned: model.pinnedRow ? model.state.pinned : [],
                                                 columns: m.columns, now: Date(),
                                                 hidden: Set(model.state.hidden), order: model.state.order,
                                                 keptIDs: model.pinnedRow ? model.keptIDs : [], separatePinned: true,
                                                 sort: model.prefs.sort, groupByCategory: model.prefs.groupByCategory,
                                                 folders: model.state.folders)
                if model.scrollDirection == .horizontal {
                    pager(page, m, size: proxy.size)
                } else {
                    let _ = recordLayout(LauncherPaging.paginateRows(page, columns: m.columns, rowsPerPage: 10_000), columns: m.columns)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            ForEach(LauncherPaging.paginateRows(page, columns: m.columns, rowsPerPage: 10_000)
                                        .flatMap { $0 }, id: \.kind) { section in
                                sectionView(section, m, slot: true)
                            }
                        }
                        .padding(.horizontal, 56).padding(.bottom, 80)
                        .frame(maxWidth: 1612)
                        .frame(maxWidth: .infinity)
                    }
                }
            } else if !hasAnySearchResult {
                noResults
            } else {
                let _ = recordSearchLayout(matches, columns: m.columns)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if !answers.isEmpty { answerSection }
                        commandSection
                        unifiedSearchExtras
                        if !matches.isEmpty { grid(matches, m, reorderable: false) }
                    }
                    .padding(.horizontal, 56).padding(.bottom, 80)
                    .frame(maxWidth: 1612).frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder private var noResults: some View {
        VStack(spacing: 12) {
            Text("No Apps Found").foregroundColor(.secondary)
            if let q = LauncherQuickAction.resolve(model.query) {
                Button { actions.quickAction(q) } label: {
                    switch q {
                    case .open: Text("Open in Browser")
                    case .webSearch: Text("Search the Web")
                    case .askAI: Text("Ask AI")
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 40)
    }

    // MARK: Answer rows (Phase 21b)

    @ViewBuilder private var answerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(answers.enumerated()), id: \.offset) { _, answer in
                Button { run(answer) } label: { answerLabel(answer) }
                    .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func answerLabel(_ answer: LauncherAnswer) -> some View {
        HStack(spacing: 12) {
            Image(systemName: answerSymbol(answer)).font(.system(size: 17, weight: .semibold)).frame(width: 26)
            switch answer {
            case .math(let expression, let value):
                Text(verbatim: value).font(.system(size: 20, weight: .semibold))
                Text(verbatim: expression).font(.system(size: 14)).foregroundColor(.secondary)
            case .web(let query):
                Text("Search the Web").font(.system(size: 15, weight: .medium))
                Text(verbatim: query).font(.system(size: 14)).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: 640, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.08)))
        .contentShape(Rectangle())
    }

    private func answerSymbol(_ answer: LauncherAnswer) -> String {
        switch answer {
        case .math: return "equal"
        case .web: return "globe"
        }
    }

    /// Math copies the result; web opens the search. Both close the launcher.
    private func run(_ answer: LauncherAnswer) {
        switch answer {
        case .math(_, let value):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            actions.close()
        case .web(let query):
            if let q = LauncherQuickAction.resolve(query) { actions.quickAction(q) }
        }
    }

    // MARK: Command rows (Phase 21c)

    @ViewBuilder private var commandSection: some View {
        if LauncherRunner.isEnabled {
            switch routed {
            case .script(let payload):
                commandRow("terminal", title: "Run Script", detail: payload) { _ = LauncherRunner.run(routed) }
            case .shortcut(let name):
                commandRow("bolt.fill", title: "Shortcuts", detail: name) { _ = LauncherRunner.run(routed) }
            default:
                EmptyView()
            }
        }
    }

    private func commandRow(_ symbol: String, title: LocalizedStringKey, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).frame(width: 26)
                Text(title).font(.system(size: 15, weight: .medium))
                Text(verbatim: detail).font(.system(size: 14)).foregroundColor(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: 640, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Sliding pages

    private func pager(_ page: LauncherPage, _ m: Metrics, size: CGSize) -> some View {
        let avail = Double(size.height) - Self.dotsHeight - 8
        let autoRows = max(2, min(8, Int((avail - 3 * Self.slotHeight) / m.rowHeight)))
        let rows = model.prefs.rows > 0 ? model.prefs.rows : autoRows
        let pages = LauncherPaging.paginateRows(page, columns: m.columns, rowsPerPage: rows)
        let blockHeight = Double(rows) * m.rowHeight + 3 * Self.slotHeight
        let count = max(1, pages.count)
        let index = min(model.pageIndex, count - 1)
        recordLayout(pages, columns: m.columns)
        return ZStack(alignment: .bottom) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(pages.enumerated()), id: \.offset) { pageNumber, sections in
                    if abs(pageNumber - index) > 1 {
                        // Far pages stay empty: with hundreds of apps, building every page's icons at once is the cost.
                        Color.clear.frame(width: size.width, height: size.height - Self.dotsHeight)
                    } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                            sectionView(section, m, slot: true).padding(.bottom, 4)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: CGFloat(m.width), height: CGFloat(blockHeight), alignment: .topLeading)
                    .frame(width: size.width, height: size.height - Self.dotsHeight, alignment: .center)
                    }
                }
            }
            .frame(width: size.width, alignment: .leading)
            .offset(x: -CGFloat(index) * size.width + dragX)
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: index)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
            if count > 1 { dots(count: count, index: index) }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 24)
            .onChanged { dragX = $0.translation.width }
            .onEnded { value in
                let step = value.translation.width < -size.width * 0.12 ? 1 : value.translation.width > size.width * 0.12 ? -1 : 0
                withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                    dragX = 0
                    model.pageIndex = max(0, min(count - 1, index + step))
                }
            })
        .onReceive(model.pageTurns) { delta in
            model.pageIndex = max(0, min(count - 1, min(model.pageIndex, count - 1) + delta))
        }
        .onReceive(model.pageJumps) { n in
            model.pageIndex = max(0, min(count - 1, n))
        }
    }

    private func dots(count: Int, index: Int) -> some View {
        HStack(spacing: 10) {
            ForEach(0..<count, id: \.self) { i in
                Circle().fill(Color.primary.opacity(i == index ? 0.85 : 0.25)).frame(width: 8, height: 8)
                    .contentShape(Rectangle().inset(by: -6))
                    .onTapGesture { withAnimation { model.pageIndex = i } }
            }
        }
        .frame(height: Self.dotsHeight)
    }

    // MARK: Sections and cells

    /// A caption with a hairline divider (the slot is reserved even when a continued block has no caption, so the
    /// first row sits at the same height on every page).
    @ViewBuilder private func sectionView(_ section: LauncherPageSection, _ m: Metrics, slot: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if slot {
                VStack(alignment: .leading, spacing: 5) {
                    Spacer(minLength: 0)
                    if section.showsHeader {
                        sectionTitle(section.kind)
                        Rectangle().fill(Color.primary.opacity(0.14)).frame(height: 1)
                    }
                }
                .frame(height: Self.slotHeight, alignment: .bottomLeading)
            }
            grid(section.apps, m, reorderable: section.kind == .allApps)
        }
    }

    @ViewBuilder private func sectionTitle(_ kind: LauncherSectionKind) -> some View {
        switch kind {
        case .pinned: Text("Pinned").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
        case .mostUsed: Text("Most Used").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
        case .recentlyInstalled: Text("Recently Installed").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
        case .allApps: Text("All Apps").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
        case .category(let name): Text(verbatim: name).font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
        }
    }

    private func grid(_ apps: [LauncherApp], _ m: Metrics, reorderable: Bool) -> some View {
        let items = Array(repeating: GridItem(.flexible(minimum: 60, maximum: 200), spacing: Self.gap, alignment: .top), count: max(1, m.columns))
        return LazyVGrid(columns: items, spacing: Self.rowSpacing) {
            ForEach(apps, id: \.bundleID) { app in cell(app, icon: m.icon, reorderable: reorderable) }
        }
    }

    // MARK: Keyboard focus and layout cache

    private func recordLayout(_ pages: [[LauncherPageSection]], columns: Int) {
        model.layoutPages = pages.map { $0.map { $0.apps.map(\.bundleID) } }
        model.layoutColumns = columns
        var items: [String: LauncherApp] = [:]
        for page in pages { for section in page { for app in section.apps { items[app.bundleID] = app } } }
        model.layoutItems = items
    }

    private func recordSearchLayout(_ apps: [LauncherApp], columns: Int) {
        model.layoutPages = [[apps.map(\.bundleID)]]
        model.layoutColumns = columns
        model.layoutItems = Dictionary(apps.map { ($0.bundleID, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func arrow(dx: Int, dy: Int) -> Bool {
        if model.openFolderID != nil { return false }
        let isPaged = (model.presentation == .centred || model.presentation == .fullscreen)
            && model.query.isEmpty && model.scrollDirection == .horizontal
        if isPaged {
            guard let pos = LauncherFocus.move(pages: model.layoutPages, columns: model.layoutColumns, from: model.focusedID,
                                               currentPage: model.pageIndex, dx: dx, dy: dy) else { return false }
            model.focusedID = pos.id
            model.pageIndex = pos.page
            return true
        }
        let ids = model.layoutPages.flatMap { $0 }.flatMap { $0 }
        guard let next = LauncherFocus.moveFlat(ids: ids, columns: model.layoutColumns, from: model.focusedID, dx: dx, dy: dy) else {
            return false
        }
        model.focusedID = next
        return true
    }

    private func handleTab(_ delta: Int) {
        switch model.presentation {
        case .linuxMenu where model.query.isEmpty:
            model.selectedCategory = LauncherFocus.cycleCategory(current: model.selectedCategory, delta: delta)
            model.focusedID = nil
        case .windowsStart where model.query.isEmpty:
            model.showingAllApps.toggle()
            model.focusedID = nil
        default:
            if model.query.isEmpty { model.pageTurns.send(delta) }
        }
    }

    private var keyboardTargetApp: LauncherApp? {
        if let id = model.focusedID, let item = model.layoutItems[id], !LauncherFolders.isFolderID(item.bundleID) {
            return item
        }
        return matches.first
    }

    @ViewBuilder private var unifiedSearchExtras: some View {
        if !matchingActions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("System Actions").font(.system(size: 11.5, weight: .semibold)).foregroundColor(.secondary)
                ForEach(matchingActions, id: \.keyword) { macro in
                    Button { actions.runMacro(macro) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: macro.symbol).font(.system(size: 14, weight: .semibold)).foregroundColor(.accentColor).frame(width: 24)
                            Text(verbatim: macro.title).font(.system(size: 13, weight: .medium))
                            Spacer(minLength: 0)
                            Text(verbatim: macro.subtitle).font(.system(size: 11)).foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.08)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        if !matchingFolders.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("App Groups").font(.system(size: 11.5, weight: .semibold)).foregroundColor(.secondary)
                HStack(spacing: 8) {
                    ForEach(matchingFolders) { folder in
                        Button { model.openFolderID = folder.id } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "folder.fill").font(.system(size: 12)).foregroundColor(.accentColor)
                                Text(verbatim: folder.name).font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        if !matchingFiles.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recent Files").font(.system(size: 11.5, weight: .semibold)).foregroundColor(.secondary)
                ForEach(matchingFiles) { item in
                    Button { actions.openPlace(URL(fileURLWithPath: item.path)) } label: {
                        recommendedRow(icon: NSWorkspace.shared.icon(forFile: item.path), title: item.name, subtitleVerbatim: item.subtitle)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func activate(_ app: LauncherApp) {
        if LauncherFolders.isFolderID(app.bundleID) { model.openFolderID = app.bundleID } else { actions.launch(app) }
    }

    // MARK: Cells

    private func folder(for app: LauncherApp) -> LauncherFolder? {
        LauncherFolders.isFolderID(app.bundleID) ? model.state.folders.first { $0.id == app.bundleID } : nil
    }

    @ViewBuilder private func cellImage(_ app: LauncherApp, icon: CGFloat) -> some View {
        if let folder = folder(for: app) {
            let members = LauncherFolders.members(of: folder, in: indexer.apps).prefix(4)
            ZStack {
                RoundedRectangle(cornerRadius: icon * 0.23, style: .continuous).fill(Color.primary.opacity(0.16))
                RoundedRectangle(cornerRadius: icon * 0.23, style: .continuous).strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                LazyVGrid(columns: [GridItem(.fixed(icon * 0.36), spacing: icon * 0.06), GridItem(.fixed(icon * 0.36), spacing: icon * 0.06)],
                          spacing: icon * 0.06) {
                    ForEach(Array(members), id: \.bundleID) { m in
                        Image(nsImage: LauncherIconCache.icon(forPath: m.path)).resizable().interpolation(.high)
                            .frame(width: icon * 0.36, height: icon * 0.36)
                    }
                }
            }
            .frame(width: icon, height: icon)
        } else {
            Image(nsImage: LauncherIconCache.icon(forPath: app.path)).resizable().interpolation(.high)
                .frame(width: icon, height: icon)
                .opacity(model.state.hidden.contains(app.bundleID) ? 0.45 : 1)
        }
    }

    @ViewBuilder private func cell(_ app: LauncherApp, icon: CGFloat, reorderable: Bool) -> some View {
        let isFolder = LauncherFolders.isFolderID(app.bundleID)
        let base = Button { if model.editing && !isFolder { return }; activate(app) } label: {
            VStack(spacing: 6) {
                cellImage(app, icon: icon)
                Text(verbatim: app.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: icon + 34, height: 30, alignment: .top)
                    .overlay(alignment: .bottom) {
                        if model.prefs.showRunningDot, model.runningIDs.contains(app.bundleID) {
                            Circle().fill(Color.accentColor.opacity(0.9)).frame(width: 4, height: 4).offset(y: 4)
                        }
                    }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: model.focusedID == app.bundleID ? 2.5 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(LauncherWiggle(active: model.editing, seed: app.bundleID))
        .overlay(alignment: .topLeading) { if model.editing { editBadge(app, isFolder: isFolder) } }
        .contextMenu { menu(app, reorderable: reorderable) }
        if reorderable || model.editing {
            base
                .onDrag { NSItemProvider(object: app.bundleID as NSString) }
                .onDrop(of: [.plainText], isTargeted: nil) { providers in
                    guard let provider = providers.first else { return false }
                    _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                        guard let id = object as? String else { return }
                        DispatchQueue.main.async {
                            if model.editing { actions.dropOnto(id, app) } else { actions.move(id, app) }
                        }
                    }
                    return true
                }
        } else {
            base
        }
    }

    /// Edit mode's corner button: hides an app from the launcher, or dissolves a folder (its apps return to the grid).
    private func editBadge(_ app: LauncherApp, isFolder: Bool) -> some View {
        Button {
            if isFolder {
                model.state.folders = LauncherFolders.delete(model.state.folders, id: app.bundleID); actions.persist()
            } else {
                actions.toggleHidden(app)
            }
        } label: {
            Image(systemName: "minus").font(.system(size: 10, weight: .heavy)).foregroundColor(.white)
                .frame(width: 20, height: 20).background(Circle().fill(Color.black.opacity(0.55)))
        }
        .buttonStyle(.plain)
        .help(isFolder ? Text("Delete Folder") : Text("Hide from Launcher"))
    }

    // MARK: Folder overlay

    private func folderOverlay(_ folder: LauncherFolder) -> some View {
        let members = LauncherFolders.members(of: folder, in: indexer.apps)
        return ZStack {
            Color.black.opacity(0.28).onTapGesture { model.openFolderID = nil }
            VStack(spacing: 18) {
                TextField("Folder Name", text: Binding(
                    get: { folder.name },
                    set: { model.state.folders = LauncherFolders.rename(model.state.folders, id: folder.id, to: $0) }
                ), onCommit: actions.persist)
                .textFieldStyle(.plain).multilineTextAlignment(.center).font(.system(size: 20, weight: .semibold))
                .frame(maxWidth: 260)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(96), spacing: 14, alignment: .top), count: min(5, max(1, members.count))),
                          spacing: 16) {
                    ForEach(members, id: \.bundleID) { app in
                        Button { actions.launch(app) } label: {
                            VStack(spacing: 6) {
                                Image(nsImage: LauncherIconCache.icon(forPath: app.path)).resizable().interpolation(.high)
                                    .frame(width: 64, height: 64)
                                Text(verbatim: app.name).font(.system(size: 12)).lineLimit(1).frame(maxWidth: 92)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Open") { actions.launch(app) }
                            Button("Remove from Folder") {
                                model.state.folders = LauncherFolders.remove(model.state.folders, appID: app.bundleID)
                                actions.persist()
                                if !model.state.folders.contains(where: { $0.id == folder.id }) { model.openFolderID = nil }
                            }
                        }
                    }
                }
            }
            .padding(28)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.regularMaterial))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
            .shadow(color: .black.opacity(0.3), radius: 24, y: 8)
        }
    }

    @ViewBuilder private func menu(_ app: LauncherApp, reorderable: Bool) -> some View {
        let pinned = model.state.pinned.contains(app.bundleID)
        let hidden = model.state.hidden.contains(app.bundleID)
        let kept = actions.isKeptInDock(app.bundleID)
        let running = model.runningIDs.contains(app.bundleID)
        if LauncherFolders.isFolderID(app.bundleID) {
            Button("Open") { model.openFolderID = app.bundleID }
            Button("Delete Folder") {
                model.state.folders = LauncherFolders.delete(model.state.folders, id: app.bundleID); actions.persist()
            }
        } else {
            Button("Open") { actions.launch(app) }
            if running { Button("Quit") { actions.quitApp(app) } }
            Button("Show in Finder") { actions.reveal(app) }
            Button("Copy Path") { actions.copyPath(app) }
            Divider()
            if pinned { Button("Unpin") { actions.togglePin(app) } } else { Button("Pin") { actions.togglePin(app) } }
            if kept { Button("Remove from Dock") { actions.toggleKeepInDock(app) } } else { Button("Keep in Dock") { actions.toggleKeepInDock(app) } }
            if reorderable { Button("Move to Start") { actions.move(app.bundleID, nil) } }
            Divider()
            Menu {
                Button("New App Group") { actions.newFolder(app) }
                ForEach(model.state.folders) { f in
                    Button { model.state.folders = LauncherFolders.add(model.state.folders, appID: app.bundleID, to: f.id); actions.persist() } label: {
                        Text(verbatim: f.name)
                    }
                }
                ForEach(DockAppGroupStore.shared.groups) { g in
                    Button { DockAppGroupStore.shared.addApp(app.bundleID, to: g.id) } label: {
                        Text(verbatim: g.name)
                    }
                }
            } label: { Text("Add to App Group") }
            if hidden { Button("Show in Launcher") { actions.toggleHidden(app) } } else { Button("Hide from Launcher") { actions.toggleHidden(app) } }
            Divider()
            Button("Uninstall…") { actions.uninstall(app) }
            Button("Delete Data…") { actions.deleteData(app) }
        }
    }
}

@MainActor
final class LauncherModel: ObservableObject {
    @Published var query = "" { didSet { if query != oldValue { pageIndex = 0; focusedID = nil } } }
    @Published var editing = false
    @Published var focusedID: String?
    @Published var openFolderID: String?
    /// ⌘1–⌘9: absolute page requests.
    let pageJumps = PassthroughSubject<Int, Never>()
    /// The grid as last drawn (ids per section per page), for arrow-key focus. Plain properties: writing them never redraws.
    var layoutPages: [[[String]]] = []
    var layoutColumns = 1
    var layoutItems: [String: LauncherApp] = [:]
    @Published var focusNonce = 0
    @Published var searchPosition: LauncherSearchPosition = .top
    @Published var scrollDirection: LauncherScrollDirection = .vertical
    @Published var pinnedRow = true
    @Published var pageIndex = 0
    /// Page requests from the keyboard, scroll wheel and search field (the view clamps them to the page count).
    let pageTurns = PassthroughSubject<Int, Never>()
    /// Screen space to keep clear (notch, menu bar, Dock, KatiKati bars).
    @Published var screenInsets: (top: Double, bottom: Double, leading: Double, trailing: Double) = (0, 0, 0, 0)
    @Published var state = LauncherState()
    @Published var prefs = LauncherPrefs() { didSet { if prefs != oldValue { prefs.save() } } }
    /// Dock-kept apps (Pinned on page 1) and the apps running right now (dot under the name); read at each summon.
    @Published var keptIDs: [String] = []
    @Published var stashedAppIDs: [String] = []
    @Published var presentation: LauncherPresentation = .default
    @Published var runningIDs: Set<String> = []
    @Published var recentFiles: [LauncherRecentItem] = []
    @Published var selectedCategory: LauncherSidebarCategory = .favorites
    @Published var showingAllApps = false
}

/// AppKit search field so it can take first responder the moment the panel opens (macOS 12 has no `@FocusState`).
struct LauncherSearchField: NSViewRepresentable {
    @Binding var text: String
    let focusNonce: Int
    let onSubmit: () -> Void
    var onCommandSubmit: () -> Void = {}
    var onOptionSubmit: () -> Void = {}
    let onCancel: () -> Void
    let onTab: (Int) -> Void
    /// Arrow keys over the grid; return false to let the field handle the key (caret movement).
    let onArrow: (_ dx: Int, _ dy: Int) -> Bool

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = String(localized: "Search Apps, Files & Actions")
        field.delegate = context.coordinator
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 15)
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if context.coordinator.focusNonce != focusNonce {
            context.coordinator.focusNonce = focusNonce
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: LauncherSearchField
        var focusNonce = -1
        init(_ parent: LauncherSearchField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                if flags.contains(.command) { parent.onCommandSubmit() }
                else if flags.contains(.option) { parent.onOptionSubmit() }
                else { parent.onSubmit() }
                return true
            case #selector(NSResponder.cancelOperation(_:)): parent.onCancel(); return true
            case #selector(NSResponder.insertTab(_:)):
                parent.onTab(1); return true
            case #selector(NSResponder.insertBacktab(_:)):
                parent.onTab(-1); return true
            case #selector(NSResponder.moveRight(_:)):
                guard parent.text.isEmpty else { return false }
                return parent.onArrow(1, 0)
            case #selector(NSResponder.moveLeft(_:)):
                guard parent.text.isEmpty else { return false }
                return parent.onArrow(-1, 0)
            case #selector(NSResponder.moveDown(_:)): return parent.onArrow(0, 1)
            case #selector(NSResponder.moveUp(_:)): return parent.onArrow(0, -1)
            default: return false
            }
        }
    }
}

/// 13g: the launcher's own settings, one tap from the grid. Edits apply live and persist.
struct LauncherGearPopover: View {
    @ObservedObject var model: LauncherModel
    let actions: LauncherActions

    private var hiddenSuggested: Int { LauncherHidePresets.bundleIDs.filter(model.state.hidden.contains).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            slider("Blur", value: $model.prefs.blur, range: 0...1)
            slider("Icon Size", value: $model.prefs.iconScale, range: LauncherPrefs.iconScaleRange)
            row("Columns") {
                Picker("Columns", selection: $model.prefs.columns) {
                    Text("Auto").tag(0)
                    ForEach(LauncherPrefs.columnRange, id: \.self) { Text(verbatim: "\($0)").tag($0) }
                }.labelsHidden().fixedSize()
            }
            row("Rows") {
                Picker("Rows", selection: $model.prefs.rows) {
                    Text("Auto").tag(0)
                    ForEach(LauncherPrefs.rowRange, id: \.self) { Text(verbatim: "\($0)").tag($0) }
                }.labelsHidden().fixedSize()
            }
            row("Sort By") {
                Picker("Sort By", selection: $model.prefs.sort) {
                    Text("Custom Order").tag(LauncherSortMode.custom)
                    Text("Name").tag(LauncherSortMode.name)
                    Text("Most Used").tag(LauncherSortMode.mostUsed)
                    Text("Recently Added").tag(LauncherSortMode.recentlyAdded)
                    Text("Category").tag(LauncherSortMode.category)
                }.labelsHidden().fixedSize()
            }
            Toggle("Group by Category", isOn: $model.prefs.groupByCategory)
            Toggle("Show Running Apps", isOn: $model.prefs.showRunningDot)
            Divider()
            HStack {
                Button("Hide Rarely Used Apps") {
                    model.state.hidden = LauncherHidePresets.hidingAll(model.state.hidden); actions.persist()
                }
                .disabled(hiddenSuggested == LauncherHidePresets.bundleIDs.count)
                Button("Show All Hidden Apps") { model.state.hidden = []; actions.persist() }
                    .disabled(model.state.hidden.isEmpty)
            }
            .controlSize(.small)
        }
        .padding(16).frame(width: 300)
    }

    private func row<C: View>(_ title: LocalizedStringKey, @ViewBuilder _ control: () -> C) -> some View {
        HStack { Text(title); Spacer(minLength: 12); control() }
    }

    private func slider(_ title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Slider(value: value, in: range)
        }
    }
}

/// Edit mode's jiggle: a small alternating rotation, stopped under Reduce Motion.
struct LauncherWiggle: ViewModifier {
    let active: Bool
    let seed: String
    @State private var flip = false

    func body(content: Content) -> some View {
        let animate = active && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        content
            .rotationEffect(.degrees(animate ? (flip ? 1.6 : -1.6) : 0))
            .animation(animate ? .easeInOut(duration: 0.11 + Double(abs(seed.hashValue) % 40) / 1000).repeatForever(autoreverses: true) : .default,
                       value: flip)
            .onChange(of: active) { on in flip = on }
            .onAppear { if active { flip = true } }
    }
}

/// Compact CPU · RAM · Disk pill displayed in the Launcher top-right toolbar.
struct LauncherTelemetryPill: View {
    @ObservedObject var monitor: SystemMonitorController

    var body: some View {
        let telemetry = LauncherTelemetrySnapshot.from(snapshot: monitor.snapshot)
        HStack(spacing: 6) {
            Image(systemName: "cpu")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            Text(verbatim: telemetry.summaryText)
                .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundColor(.primary.opacity(0.85))
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
        .help(Text("System Telemetry (CPU · RAM · Disk)"))
        .accessibilityLabel(Text(verbatim: telemetry.summaryText))
    }
}

private extension LauncherView {
    @ViewBuilder var drawerBody: some View {
        ZStack {
            VStack(spacing: 0) {
                drawerHeader
                Divider().opacity(0.35)
                drawerContent
            }
            if let folder = openFolder { folderOverlay(folder) }
        }
    }

    var drawerHeader: some View {
        HStack(spacing: 8) {
            LauncherSearchField(text: $model.query, focusNonce: model.focusNonce,
                                onSubmit: {
                                    if let id = model.focusedID, let item = model.layoutItems[id] { activate(item) }
                                    else if let answer = answers.first { run(answer) }
                                    else if isRunnable { _ = LauncherRunner.run(routed) }
                                    else if let first = matches.first { actions.launch(first) }
                                    else if let q = LauncherQuickAction.resolve(model.query) { actions.quickAction(q) }
                                },
                                onCancel: {
                                    if model.openFolderID != nil { model.openFolderID = nil }
                                    else if model.editing { model.editing = false }
                                    else { actions.close() }
                                },
                                onTab: { _ in },
                                onArrow: { arrow(dx: $0, dy: $1) })
                .frame(maxWidth: .infinity)
                .frame(height: 28)

            Button {
                drawerStyleRaw = (drawerStyle == .grid ? LauncherDrawerViewStyle.list : .grid).rawValue
            } label: {
                Image(systemName: drawerStyle == .grid ? "list.bullet" : "square.grid.2x2")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .help(drawerStyle == .grid ? Text("List") : Text("Grid"))
            .accessibilityLabel(drawerStyle == .grid ? Text("List") : Text("Grid"))

            Button { model.editing.toggle(); model.openFolderID = nil } label: {
                Group { if model.editing { Text("Done") } else { Text("Edit") } }
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Capsule().fill(model.editing ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.10)))
            }
            .buttonStyle(.plain)

            Button(action: actions.close) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .help(Text("Close"))
            .accessibilityLabel(Text("Close"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder var drawerContent: some View {
        let cols = drawerStyle == .grid ? 4 : 1
        if model.query.isEmpty {
            let page = LauncherAppIndex.page(
                apps: indexer.apps,
                usage: model.state.usage,
                pinned: model.stashedAppIDs + (model.pinnedRow ? model.state.pinned : []),
                columns: cols,
                now: Date(),
                hidden: Set(model.state.hidden),
                order: model.state.order,
                keptIDs: model.pinnedRow ? model.keptIDs : [],
                separatePinned: true,
                sort: model.prefs.sort,
                groupByCategory: model.prefs.groupByCategory,
                folders: model.state.folders
            )
            let sections: [(kind: LauncherSectionKind, apps: [LauncherApp], reorderable: Bool)] = {
                var list: [(LauncherSectionKind, [LauncherApp], Bool)] = []
                if !page.pinned.isEmpty { list.append((.pinned, page.pinned, false)) }
                if page.groups.isEmpty {
                    list.append((.allApps, page.all, true))
                } else {
                    list += page.groups.map { (.category($0.title), $0.apps, false) }
                }
                return list
            }()
            let _ = recordLayout(
                [sections.map { LauncherPageSection(kind: $0.kind, apps: $0.apps, showsHeader: true) }],
                columns: cols
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, sec in
                        VStack(alignment: .leading, spacing: 8) {
                            sectionTitle(sec.kind)
                            drawerCollection(sec.apps, reorderable: sec.reorderable)
                        }
                    }
                }
                .padding(14)
            }
        } else if !hasAnySearchResult {
            noResults
            Spacer(minLength: 0)
        } else {
            let _ = recordSearchLayout(matches, columns: cols)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !answers.isEmpty { answerSection }
                    commandSection
                    unifiedSearchExtras
                    if !matches.isEmpty { drawerCollection(matches, reorderable: false) }
                }
                .padding(14)
            }
        }
    }

    @ViewBuilder func drawerCollection(_ apps: [LauncherApp], reorderable: Bool) -> some View {
        if drawerStyle == .grid {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 72, maximum: 110), spacing: 10), count: 4), spacing: 12) {
                ForEach(apps, id: \.bundleID) { app in
                    drawerInteractiveCell(app, reorderable: reorderable) {
                        VStack(spacing: 5) {
                            cellImage(app, icon: 44)
                            Text(verbatim: app.name)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .frame(maxWidth: 84)
                                .overlay(alignment: .bottom) {
                                    if model.prefs.showRunningDot, model.runningIDs.contains(app.bundleID) {
                                        Circle().fill(Color.secondary).frame(width: 3.5, height: 3.5).offset(y: 6)
                                    }
                                }
                        }
                        .padding(6)
                    }
                }
            }
        } else {
            LazyVStack(spacing: 4) {
                ForEach(apps, id: \.bundleID) { app in
                    drawerInteractiveCell(app, reorderable: reorderable) {
                        HStack(spacing: 10) {
                            cellImage(app, icon: 28)
                            Text(verbatim: app.name)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if model.prefs.showRunningDot, model.runningIDs.contains(app.bundleID) {
                                Circle().fill(Color.secondary).frame(width: 5, height: 5)
                            }
                            if LauncherFolders.isFolderID(app.bundleID) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                    }
                }
            }
        }
    }

    @ViewBuilder func drawerInteractiveCell<Content: View>(
        _ app: LauncherApp,
        reorderable: Bool,
        @ViewBuilder label: () -> Content
    ) -> some View {
        let isFolder = LauncherFolders.isFolderID(app.bundleID)
        let base = Button {
            if model.editing && !isFolder { return }
            activate(app)
        } label: {
            label()
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: model.focusedID == app.bundleID ? 2 : 0))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(LauncherWiggle(active: model.editing, seed: app.bundleID))
        .overlay(alignment: .topLeading) { if model.editing { editBadge(app, isFolder: isFolder) } }
        .contextMenu { menu(app, reorderable: reorderable) }

        if reorderable || model.editing {
            base
                .onDrag { NSItemProvider(object: app.bundleID as NSString) }
                .onDrop(of: [.plainText], isTargeted: nil) { providers in
                    guard let provider = providers.first else { return false }
                    _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                        guard let id = object as? String else { return }
                        DispatchQueue.main.async {
                            if model.editing { actions.dropOnto(id, app) } else { actions.move(id, app) }
                        }
                    }
                    return true
                }
        } else {
            base
        }
    }

    // MARK: Windows Start Preset & Shared Footer

    private var sixColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 74, maximum: 112), spacing: 10, alignment: .top), count: 6)
    }

    private func pillButton(_ title: LocalizedStringKey, icon: String, trailing: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if !trailing { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
                Text(title)
                if trailing { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
            }
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.09)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder var windowsStartBody: some View {
        let visibleApps = indexer.apps.filter { !model.state.hidden.contains($0.bundleID) }
        let page = LauncherAppIndex.page(
            apps: indexer.apps, usage: model.state.usage,
            pinned: model.pinnedRow ? model.state.pinned : [],
            columns: 6, now: Date(),
            hidden: Set(model.state.hidden), order: model.state.order,
            keptIDs: model.pinnedRow ? model.keptIDs : [], separatePinned: true,
            sort: model.prefs.sort, groupByCategory: false, folders: model.state.folders
        )
        ZStack {
            VStack(spacing: 0) {
                searchFieldCluster
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                    .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 12)
                if !model.query.isEmpty { windowsStartSearchContent }
                else if model.showingAllApps { windowsStartAllAppsContent(apps: visibleApps) }
                else { windowsStartHomeContent(page: page, visibleApps: visibleApps) }
                Spacer(minLength: 0)
                launcherFooterBar
            }
            if let folder = openFolder { folderOverlay(folder) }
        }
    }

    @ViewBuilder private var windowsStartSearchContent: some View {
        if !hasAnySearchResult { noResults } else {
            let _ = recordSearchLayout(matches, columns: 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !answers.isEmpty { answerSection }
                    commandSection
                    unifiedSearchExtras
                    if !matches.isEmpty {
                        LazyVGrid(columns: sixColumns, spacing: 14) {
                            ForEach(matches, id: \.bundleID) { cell($0, icon: 44, reorderable: false) }
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder private func windowsStartHomeContent(page: LauncherPage, visibleApps: [LauncherApp]) -> some View {
        let pinnedApps = page.pinned.isEmpty
            ? Array(LauncherAppIndex.recommendedApps(apps: visibleApps, usage: model.state.usage, now: Date(), limit: 12))
            : page.pinned
        let recommended = LauncherAppIndex.recommendedApps(
            apps: visibleApps, usage: model.state.usage, excluding: Set(pinnedApps.map(\.bundleID)), now: Date(), limit: 6
        )
        let _ = recordLayout([[LauncherPageSection(kind: .pinned, apps: Array(pinnedApps.prefix(18)), showsHeader: true)]], columns: 6)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(page.pinned.isEmpty ? "Most Used" : "Pinned").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        pillButton("All Apps", icon: "chevron.right", trailing: true) { model.showingAllApps = true }
                    }
                    LazyVGrid(columns: sixColumns, spacing: 12) {
                        ForEach(pinnedApps.prefix(18), id: \.bundleID) { cell($0, icon: 44, reorderable: false) }
                    }
                }
                if model.prefs.showRecommended && (!recommended.isEmpty || !model.recentFiles.isEmpty) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recommended").font(.system(size: 13, weight: .semibold))
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 8) {
                            ForEach(recommended.prefix(4), id: \.bundleID) { app in
                                Button { actions.launch(app) } label: {
                                    recommendedRow(icon: LauncherIconCache.icon(forPath: app.path), title: app.name, subtitleKey: "Most Used")
                                }
                                .buttonStyle(.plain).contextMenu { menu(app, reorderable: false) }
                            }
                            ForEach(model.recentFiles.prefix(max(0, 6 - min(4, recommended.count)))) { item in
                                Button { actions.openPlace(URL(fileURLWithPath: item.path)) } label: {
                                    recommendedRow(icon: NSWorkspace.shared.icon(forFile: item.path), title: item.name, subtitleVerbatim: item.subtitle)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 14)
        }
    }

    @ViewBuilder private func windowsStartAllAppsContent(apps: [LauncherApp]) -> some View {
        let groups = LauncherAppIndex.alphaGroups(apps)
        let _ = recordLayout([[LauncherPageSection(kind: .allApps, apps: groups.flatMap(\.apps), showsHeader: true)]], columns: 6)
        VStack(spacing: 8) {
            HStack {
                Text("All Apps").font(.system(size: 13, weight: .semibold))
                Spacer()
                pillButton("Back", icon: "chevron.left", trailing: false) { model.showingAllApps = false }
            }
            .padding(.horizontal, 24)
            ScrollViewReader { reader in
                HStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(groups) { group in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(verbatim: group.letter).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(.secondary).id(group.letter)
                                    LazyVGrid(columns: sixColumns, spacing: 12) {
                                        ForEach(group.apps, id: \.bundleID) { cell($0, icon: 44, reorderable: false) }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 24).padding(.bottom, 14)
                    }
                    VStack(spacing: 1) {
                        ForEach(groups) { group in
                            Button { withAnimation(.easeOut(duration: 0.16)) { reader.scrollTo(group.letter, anchor: .top) } } label: {
                                Text(verbatim: group.letter).font(.system(size: 9.5, weight: .semibold, design: .rounded)).foregroundColor(.secondary).frame(width: 16, height: 13)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.trailing, 8)
                }
            }
        }
    }

    private func recommendedRow(icon: NSImage, title: String, subtitleKey: LocalizedStringKey? = nil, subtitleVerbatim: String? = nil) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                if let subtitleKey { Text(subtitleKey).font(.system(size: 10.5)).foregroundColor(.secondary).lineLimit(1) }
                else if let subtitleVerbatim { Text(verbatim: subtitleVerbatim).font(.system(size: 10.5)).foregroundColor(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
        .contentShape(Rectangle())
    }

    var launcherFooterBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.28)
            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 18)).foregroundColor(.secondary)
                    Text(verbatim: NSFullUserName().isEmpty ? NSUserName() : NSFullUserName()).font(.system(size: 12, weight: .medium)).lineLimit(1)
                }
                if model.prefs.showFooterTelemetry { LauncherTelemetryPill(monitor: monitor) }
                Spacer(minLength: 0)
                if model.prefs.showQuickPlaces {
                    HStack(spacing: 4) {
                        footerPlaceButton("house", help: "Home", url: FileManager.default.homeDirectoryForCurrentUser)
                        if let dl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first { footerPlaceButton("arrow.down.circle", help: "Downloads", url: dl) }
                        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first { footerPlaceButton("doc", help: "Documents", url: docs) }
                        Button(action: actions.openSettings) {
                            Image(systemName: "gearshape").font(.system(size: 13, weight: .medium)).frame(width: 28, height: 28)
                                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.07)))
                        }
                        .buttonStyle(.plain).help(Text("Launcher Settings")).accessibilityLabel(Text("Launcher Settings"))
                    }
                }
                if model.prefs.showPowerControls {
                    Menu {
                        Button { actions.runMacro(.lock) } label: { Label("Lock Screen", systemImage: "lock") }
                        Button { actions.runMacro(.sleep) } label: { Label("Sleep", systemImage: "moon.zzz") }
                        Divider()
                        Button { actions.runMacro(.restart) } label: { Label("Restart Mac", systemImage: "arrow.clockwise") }
                        Button { actions.runMacro(.shutdown) } label: { Label("Shut Down", systemImage: "power") }
                        Button { actions.runMacro(.logout) } label: { Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right") }
                    } label: {
                        Image(systemName: "power").font(.system(size: 13, weight: .semibold)).frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.09)))
                    }
                    .menuStyle(.borderlessButton).fixedSize().help(Text("Power")).accessibilityLabel(Text("Power"))
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
    }

    private func footerPlaceButton(_ symbol: String, help: LocalizedStringKey, url: URL) -> some View {
        Button { actions.openPlace(url) } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
        .help(Text(help))
        .accessibilityLabel(Text(help))
    }

    // MARK: Linux Menu Preset (KDE Kickoff / Whisker)

    private var linuxGridColumns: Int {
        switch model.prefs.density {
        case .compact: return 6
        case .standard: return 5
        case .spacious: return 4
        }
    }

    private var linuxIconSize: CGFloat {
        let base: CGFloat = switch model.prefs.density {
        case .compact: 36
        case .standard: 44
        case .spacious: 52
        }
        return base * model.prefs.iconScale
    }

    private func categoryLabel(_ category: LauncherSidebarCategory) -> Text {
        switch category {
        case .favorites: return Text("Favorites")
        case .allApps: return Text("All Apps")
        case .productivity: return Text("Productivity")
        case .developer: return Text("Developer")
        case .internet: return Text("Internet")
        case .media: return Text("Media")
        case .utilities: return Text("Utilities")
        case .system: return Text("System")
        }
    }

    @ViewBuilder var linuxMenuBody: some View {
        let visibleApps = indexer.apps.filter { !model.state.hidden.contains($0.bundleID) }
        let pinnedSet = Set(model.keptIDs + model.state.pinned)
        let filtered = LauncherSort.apply(
            model.prefs.sort,
            to: LauncherSidebarCategory.filter(model.selectedCategory, apps: visibleApps, pinnedIDs: pinnedSet),
            usage: model.state.usage,
            order: model.state.order
        )
        let displayed = model.query.isEmpty ? filtered : matches
        let cols = model.prefs.viewMode == .list ? 1 : linuxGridColumns
        let _ = recordLayout([[LauncherPageSection(kind: .allApps, apps: displayed, showsHeader: false)]], columns: cols)

        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    searchFieldCluster
                    Button {
                        model.prefs.viewMode = model.prefs.viewMode == .grid ? .list : .grid
                    } label: {
                        Image(systemName: model.prefs.viewMode == .grid ? "list.bullet" : "square.grid.2x2")
                            .font(.system(size: 12.5, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.primary.opacity(0.09)))
                    }
                    .buttonStyle(.plain)
                    .help(model.prefs.viewMode == .grid ? Text("List") : Text("Grid"))
                    .accessibilityLabel(model.prefs.viewMode == .grid ? Text("List") : Text("Grid"))
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 10)

                Divider().opacity(0.24)

                HStack(spacing: 0) {
                    if model.prefs.showCategorySidebar && model.query.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(LauncherSidebarCategory.allCases) { cat in
                                    linuxCategoryRow(cat)
                                }
                            }
                            .padding(10)
                        }
                        .frame(width: 176)
                        Divider().opacity(0.24)
                    }

                    if !model.query.isEmpty && !hasAnySearchResult {
                        noResults.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                if !model.query.isEmpty {
                                    if !answers.isEmpty { answerSection }
                                    commandSection
                                    unifiedSearchExtras
                                }
                                if model.prefs.viewMode == .list {
                                    LazyVStack(spacing: 3) {
                                        ForEach(displayed, id: \.bundleID) { linuxListRow($0) }
                                    }
                                } else {
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 68, maximum: 120), spacing: 10, alignment: .top), count: linuxGridColumns), spacing: 12) {
                                        ForEach(displayed, id: \.bundleID) { cell($0, icon: linuxIconSize, reorderable: false) }
                                    }
                                }
                            }
                            .padding(14)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                launcherFooterBar
            }
            if let folder = openFolder { folderOverlay(folder) }
        }
    }

    private func linuxCategoryRow(_ category: LauncherSidebarCategory) -> some View {
        let active = model.selectedCategory == category
        return Button {
            hoverCategoryTask?.cancel()
            model.selectedCategory = category
            model.focusedID = nil
        } label: {
            HStack(spacing: 9) {
                Image(systemName: category.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(active ? .accentColor : .secondary)
                    .frame(width: 18)
                categoryLabel(category)
                    .font(.system(size: 12.5, weight: active ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(active ? Color.accentColor.opacity(0.18) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoverCategoryTask?.cancel()
            guard hovering, model.selectedCategory != category else { return }
            hoverCategoryTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 90_000_000)
                guard !Task.isCancelled else { return }
                model.selectedCategory = category
                model.focusedID = nil
            }
        }
    }

    private func linuxListRow(_ app: LauncherApp) -> some View {
        Button { activate(app) } label: {
            HStack(spacing: 10) {
                cellImage(app, icon: 28)
                Text(verbatim: app.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
                if model.prefs.showRunningDot, model.runningIDs.contains(app.bundleID) {
                    Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: model.focusedID == app.bundleID ? 2 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { menu(app, reorderable: false) }
    }
}
