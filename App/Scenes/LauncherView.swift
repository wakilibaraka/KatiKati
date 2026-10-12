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
    private static let headerHeight = 34.0
    private static let dotsHeight = 36.0
    @State private var dragX: CGFloat = 0

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
            searchField
                .padding(.top, model.screenInsets.top).padding(.bottom, model.screenInsets.bottom)
                .padding(.leading, model.screenInsets.leading).padding(.trailing, model.screenInsets.trailing)
        }
        .accessibilityLabel(Text("Launcher"))
    }

    private var searchField: some View {
        let p = model.searchPosition
        return LauncherSearchField(text: $model.query, focusNonce: model.focusNonce,
                                   onSubmit: { if let first = matches.first { actions.launch(first) } },
                                   onCancel: actions.close,
                                   onPage: { model.pageTurns.send($0) })
            .frame(width: p.fieldWidth, height: 28)
            .padding(p == .top ? .top : p == .bottom ? .bottom : p == .left ? .leading : .trailing, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(p))
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
        let columns = min(8, LauncherGrid.columns(forWidth: width, minCell: 84, gap: Self.gap))
        let cellWidth = (width - Double(columns - 1) * Self.gap) / Double(columns)
        let icon = CGFloat(min(max(cellWidth * 0.56, 56), 128))
        return Metrics(columns: columns, icon: icon, rowHeight: Double(icon) + 44 + Self.rowSpacing, width: width)
    }

    @ViewBuilder private var content: some View {
        GeometryReader { proxy in
            let m = metrics(width: Double(proxy.size.width))
            if model.query.isEmpty {
                let page = LauncherAppIndex.page(apps: indexer.apps, usage: model.state.usage, pinned: model.state.pinned,
                                                 columns: m.columns, now: Date(),
                                                 hidden: Set(model.state.hidden), order: model.state.order)
                if model.scrollDirection == .horizontal {
                    pager(page, m, size: proxy.size)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            ForEach(LauncherPaging.paginate(page, columns: m.columns, pageHeight: 1_000_000,
                                                            rowHeight: m.rowHeight, headerHeight: Self.headerHeight)
                                        .flatMap { $0 }, id: \.kind.hashValue) { section in
                                sectionView(section, m)
                            }
                        }
                        .padding(.horizontal, 56).padding(.bottom, 80)
                        .frame(maxWidth: 1612)
                        .frame(maxWidth: .infinity)
                    }
                }
            } else if matches.isEmpty {
                Text("No Apps Found").foregroundColor(.secondary).frame(maxWidth: .infinity).padding(.top, 40)
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
        let pages = LauncherPaging.paginate(page, columns: m.columns,
                                            pageHeight: Double(size.height) - Self.dotsHeight - 8,
                                            rowHeight: m.rowHeight, headerHeight: Self.headerHeight)
        let count = max(1, pages.count)
        let index = min(model.pageIndex, count - 1)
        return ZStack(alignment: .bottom) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(pages.enumerated()), id: \.offset) { _, sections in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                            sectionView(section, m).padding(.bottom, 4)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: CGFloat(m.width))
                    .frame(width: size.width, height: size.height - Self.dotsHeight, alignment: .top)
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

    @ViewBuilder private func sectionView(_ section: LauncherPageSection, _ m: Metrics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if section.showsHeader { sectionTitle(section.kind).frame(height: Self.headerHeight - 10, alignment: .bottomLeading) }
            grid(section.apps, m, reorderable: section.kind == .allApps)
        }
    }

    @ViewBuilder private func sectionTitle(_ kind: LauncherSectionKind) -> some View {
        switch kind {
        case .mostUsed: Text("Most Used").font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
        case .recentlyInstalled: Text("Recently Installed").font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
        case .allApps: Text("All Apps").font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
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
