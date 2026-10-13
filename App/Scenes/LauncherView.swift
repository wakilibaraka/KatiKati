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

    var body: some View {
        let inset = model.searchPosition.reservedInsets(sheetSide: .right, sheetWidth: 0)
        ZStack {
            Color.black.opacity(0.001).onTapGesture(perform: actions.close)
            content
                .padding(.top, 50 + inset.top + model.screenInsets.top)
                .padding(.bottom, inset.bottom + model.screenInsets.bottom)
                .padding(.leading, inset.leading + model.screenInsets.leading)
                .padding(.trailing, inset.trailing + model.screenInsets.trailing)
            toolbar
            searchField
                .padding(.top, model.screenInsets.top).padding(.bottom, model.screenInsets.bottom)
                .padding(.leading, model.screenInsets.leading).padding(.trailing, model.screenInsets.trailing)
        }
        .accessibilityLabel(Text("Launcher"))
    }

    private var searchField: some View {
        let p = model.searchPosition
        return LauncherSearchField(text: $model.query, focusNonce: model.focusNonce,
                                   onSubmit: {
                                       if let first = matches.first { actions.launch(first) }
                                       else if let q = LauncherQuickAction.resolve(model.query) { actions.quickAction(q) }
                                   },
                                   onCancel: actions.close,
                                   onPage: { model.pageTurns.send($0) })
            .frame(width: p.fieldWidth, height: 28)
            .padding(p == .top ? .top : p == .bottom ? .bottom : p == .left ? .leading : .trailing, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(p))
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
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
                                                 sort: model.prefs.sort, groupByCategory: model.prefs.groupByCategory)
                if model.scrollDirection == .horizontal {
                    pager(page, m, size: proxy.size)
                } else {
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
            } else if matches.isEmpty {
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
            } else {
                ScrollView {
                    grid(matches, m, reorderable: false).padding(.horizontal, 56).padding(.bottom, 80)
                        .frame(maxWidth: 1612).frame(maxWidth: .infinity)
                }
            }
        }
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

    @ViewBuilder private func cell(_ app: LauncherApp, icon: CGFloat, reorderable: Bool) -> some View {
        let base = Button { actions.launch(app) } label: {
            VStack(spacing: 8) {
                Image(nsImage: LauncherIconCache.icon(forPath: app.path)).resizable().interpolation(.high)
                    .frame(width: icon, height: icon)
                    .opacity(model.state.hidden.contains(app.bundleID) ? 0.45 : 1)
                Text(verbatim: app.name).font(.system(size: 13)).lineLimit(1).frame(maxWidth: icon + 36)
                    .overlay(alignment: .bottom) {
                        if model.prefs.showRunningDot, model.runningIDs.contains(app.bundleID) {
                            Circle().fill(Color.secondary).frame(width: 4, height: 4).offset(y: 7)
                        }
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { menu(app, reorderable: reorderable) }
        if reorderable {
            base
                .onDrag { NSItemProvider(object: app.bundleID as NSString) }
                .onDrop(of: [.plainText], isTargeted: nil) { providers in
                    guard let provider = providers.first else { return false }
                    _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                        guard let id = object as? String else { return }
                        DispatchQueue.main.async { actions.move(id, app) }
                    }
                    return true
                }
        } else {
            base
        }
    }

    @ViewBuilder private func menu(_ app: LauncherApp, reorderable: Bool) -> some View {
        let pinned = model.state.pinned.contains(app.bundleID)
        let hidden = model.state.hidden.contains(app.bundleID)
        Button("Open") { actions.launch(app) }
        Button("Show in Finder") { actions.reveal(app) }
        Button("Copy Path") { actions.copyPath(app) }
        Divider()
        if pinned { Button("Unpin") { actions.togglePin(app) } } else { Button("Pin") { actions.togglePin(app) } }
        if reorderable { Button("Move to Start") { actions.move(app.bundleID, nil) } }
        Divider()
        if hidden { Button("Show in Launcher") { actions.toggleHidden(app) } } else { Button("Hide from Launcher") { actions.toggleHidden(app) } }
    }
}

@MainActor
final class LauncherModel: ObservableObject {
    @Published var query = "" { didSet { if query != oldValue { pageIndex = 0 } } }
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
            case #selector(NSResponder.moveRight(_:)), #selector(NSResponder.insertTab(_:)):
                guard parent.text.isEmpty else { return false }
                parent.onPage(1); return true
            case #selector(NSResponder.moveLeft(_:)), #selector(NSResponder.insertBacktab(_:)):
                guard parent.text.isEmpty else { return false }
                parent.onPage(-1); return true
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
