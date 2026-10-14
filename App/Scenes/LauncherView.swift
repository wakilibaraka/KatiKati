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
}

/// The launcher surface: a search field and one app grid, 8 icons across — a Most Used row (pins and usage, then
/// presets), a Recently Installed row, then All Apps in your own order. Pages slide sideways by default (swipe, scroll,
/// arrow keys, dots) or scroll down, per Settings. While searching, the grid shows one flat set of matches.
struct LauncherView: View {
    @ObservedObject var indexer: LauncherIndexer
    @ObservedObject var model: LauncherModel
    let actions: LauncherActions

    private static let gap = 12.0
    private static let rowSpacing = 20.0
    /// Height of the caption + divider slot above each section (page 1 and later pages reserve the same one).
    private static let slotHeight = 30.0
    private static let dotsHeight = 36.0
    @State private var dragX: CGFloat = 0
    @State private var showGear = false

    private var matches: [LauncherApp] {
        LauncherSearch.search(model.query, in: indexer.apps, usage: model.state.usage)
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
        let inset = model.searchPosition.reservedInsets(sheetSide: .right, sheetWidth: 0)
        ZStack {
            Color.black.opacity(0.001).onTapGesture(perform: actions.close)
            content
                .padding(.top, 50 + inset.top + model.screenInsets.top)
                .padding(.bottom, inset.bottom + model.screenInsets.bottom)
                .padding(.leading, inset.leading + model.screenInsets.leading)
                .padding(.trailing, inset.trailing + model.screenInsets.trailing)
            if let folder = openFolder { folderOverlay(folder) }
            toolbar
            searchField
                .padding(.top, model.screenInsets.top).padding(.bottom, model.screenInsets.bottom)
                .padding(.leading, model.screenInsets.leading).padding(.trailing, model.screenInsets.trailing)
        }
        .background(pageShortcuts)
        .accessibilityLabel(Text("Launcher"))
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

    private var searchField: some View {
        let p = model.searchPosition
        return LauncherSearchField(text: $model.query, focusNonce: model.focusNonce,
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
                                   onPage: { model.pageTurns.send($0) },
                                   onArrow: { arrow(dx: $0, dy: $1) })
            .frame(width: p.fieldWidth, height: 28)
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
        .padding(.top, 14 + model.screenInsets.top).padding(.trailing, 20 + model.screenInsets.trailing)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
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
                let page = LauncherAppIndex.page(apps: indexer.apps, usage: model.state.usage, pinned: model.state.pinned,
                                                 columns: m.columns, now: Date(),
                                                 hidden: Set(model.state.hidden), order: model.state.order,
                                                 keptIDs: model.keptIDs, separatePinned: true,
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
            } else if matches.isEmpty && answers.isEmpty && !isRunnable {
                noResults
            } else {
                let _ = recordSearchLayout(matches, columns: m.columns)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if !answers.isEmpty { answerSection }
                        commandSection
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
                ForEach(Array(pages.enumerated()), id: \.offset) { _, sections in
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
        guard let pos = LauncherFocus.move(pages: model.layoutPages, columns: model.layoutColumns, from: model.focusedID,
                                           currentPage: model.pageIndex, dx: dx, dy: dy) else { return false }
        model.focusedID = pos.id
        if model.query.isEmpty, model.scrollDirection == .horizontal { model.pageIndex = pos.page }
        return true
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
            VStack(spacing: 8) {
                cellImage(app, icon: icon)
                Text(verbatim: app.name).font(.system(size: 13)).lineLimit(1).frame(maxWidth: icon + 36)
                    .overlay(alignment: .bottom) {
                        if model.prefs.showRunningDot, model.runningIDs.contains(app.bundleID) {
                            Circle().fill(Color.secondary).frame(width: 4, height: 4).offset(y: 7)
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
        if LauncherFolders.isFolderID(app.bundleID) {
            Button("Open") { model.openFolderID = app.bundleID }
            Button("Delete Folder") {
                model.state.folders = LauncherFolders.delete(model.state.folders, id: app.bundleID); actions.persist()
            }
        } else {
        Button("Open") { actions.launch(app) }
        Button("Show in Finder") { actions.reveal(app) }
        Button("Copy Path") { actions.copyPath(app) }
        Divider()
        if pinned { Button("Unpin") { actions.togglePin(app) } } else { Button("Pin") { actions.togglePin(app) } }
        if reorderable { Button("Move to Start") { actions.move(app.bundleID, nil) } }
        Divider()
        if hidden { Button("Show in Launcher") { actions.toggleHidden(app) } } else { Button("Hide from Launcher") { actions.toggleHidden(app) } }
        Divider()
        Menu {
            Button("New Folder") { actions.newFolder(app) }
            ForEach(model.state.folders) { f in
                Button { model.state.folders = LauncherFolders.add(model.state.folders, appID: app.bundleID, to: f.id); actions.persist() } label: {
                    Text(verbatim: f.name)
                }
            }
        } label: { Text("Add to Folder") }
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
    @Published var scrollDirection: LauncherScrollDirection = .horizontal
    @Published var pageIndex = 0
    /// Page requests from the keyboard, scroll wheel and search field (the view clamps them to the page count).
    let pageTurns = PassthroughSubject<Int, Never>()
    /// Screen space to keep clear (notch, menu bar, Dock, KatiKati bars).
    @Published var screenInsets: (top: Double, bottom: Double, leading: Double, trailing: Double) = (0, 0, 0, 0)
    @Published var state = LauncherState()
    @Published var prefs = LauncherPrefs() { didSet { if prefs != oldValue { prefs.save() } } }
    /// Dock-kept apps (Pinned on page 1) and the apps running right now (dot under the name); read at each summon.
    var keptIDs: [String] = []
    @Published var runningIDs: Set<String> = []
}

/// AppKit search field so it can take first responder the moment the panel opens (macOS 12 has no `@FocusState`).
struct LauncherSearchField: NSViewRepresentable {
    @Binding var text: String
    let focusNonce: Int
    let onSubmit: () -> Void
    let onCancel: () -> Void
    let onPage: (Int) -> Void
    /// Arrow keys over the grid; return false to let the field handle the key (caret movement).
    let onArrow: (_ dx: Int, _ dy: Int) -> Bool

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = String(localized: "Search Apps")
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
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit(); return true
            case #selector(NSResponder.cancelOperation(_:)): parent.onCancel(); return true
            case #selector(NSResponder.insertTab(_:)):
                guard parent.text.isEmpty else { return false }
                parent.onPage(1); return true
            case #selector(NSResponder.insertBacktab(_:)):
                guard parent.text.isEmpty else { return false }
                parent.onPage(-1); return true
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
