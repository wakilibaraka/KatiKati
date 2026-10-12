import AppKit
import SwiftUI

/// Icons are cached by path; the system already memoises file icons, this just avoids re-sizing per redraw.
enum LauncherIconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(forPath path: String) -> NSImage {
        if let hit = cache.object(forKey: path as NSString) { return hit }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 64, height: 64)
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}

/// The launcher surface: a search field and one app grid — a Most Used row (usage, then presets), a Recently
/// Installed row, then All Apps. Scrolls down (default) or sideways, per Settings. While searching, the grid
/// shows one flat set of matches.
struct LauncherView: View {
    @ObservedObject var indexer: LauncherIndexer
    @ObservedObject var model: LauncherModel
    let onLaunch: (LauncherApp) -> Void
    let onTogglePin: (LauncherApp) -> Void
    let onClose: () -> Void

    private static let cell = 104.0
    private static let gap = 12.0

    private var matches: [LauncherApp] {
        LauncherSearch.search(model.query, in: indexer.apps, usage: model.state.usage)
    }

    var body: some View {
        let inset = model.searchPosition.reservedInsets(sheetSide: .right, sheetWidth: 0)
        ZStack {
            Color.black.opacity(0.001).onTapGesture(perform: onClose)
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
                                   onSubmit: { if let first = matches.first { onLaunch(first) } },
                                   onCancel: onClose)
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

    @ViewBuilder private var content: some View {
        GeometryReader { proxy in
            let width = min(Double(proxy.size.width) - 80, 1400)
            let columns = LauncherGrid.columns(forWidth: width, minCell: Self.cell, gap: Self.gap)
            if model.query.isEmpty {
                let page = LauncherAppIndex.page(apps: indexer.apps, usage: model.state.usage,
                                                 pinned: model.state.pinned, columns: columns, now: Date())
                if model.scrollDirection == .horizontal {
                    sideways(page, height: Double(proxy.size.height))
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            section(Text("Most Used"), page.mostUsed, columns: columns)
                            section(Text("Recently Installed"), page.recentlyInstalled, columns: columns)
                            section(Text("All Apps"), page.all, columns: columns)
                        }
                        .padding(.horizontal, 40).padding(.bottom, 80)
                        .frame(maxWidth: 1480)
                        .frame(maxWidth: .infinity)
                    }
                }
            } else if matches.isEmpty {
                Text("No Apps Found").foregroundColor(.secondary).frame(maxWidth: .infinity).padding(.top, 40)
            } else {
                ScrollView {
                    grid(matches, columns: columns).padding(.horizontal, 40).padding(.bottom, 80)
                        .frame(maxWidth: 1480).frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func columnItems(_ n: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: Self.cell, maximum: 160), spacing: Self.gap, alignment: .top), count: max(1, n))
    }

    private func grid(_ apps: [LauncherApp], columns: Int) -> some View {
        LazyVGrid(columns: columnItems(columns), spacing: 18) { ForEach(apps, id: \.bundleID, content: cell) }
    }

    @ViewBuilder private func section(_ title: Text, _ apps: [LauncherApp], columns: Int) -> some View {
        if !apps.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                title.font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
                grid(apps, columns: columns)
            }
        }
    }

    /// Sideways mode: each section is a block of rows that scrolls horizontally with the others.
    private func sideways(_ page: LauncherPage, height: Double) -> some View {
        let rowHeight = 110.0
        let rows = max(1, Int((height - 60) / rowHeight))
        return ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 40) {
                block(Text("Most Used"), page.mostUsed, rows: rows)
                block(Text("Recently Installed"), page.recentlyInstalled, rows: rows)
                block(Text("All Apps"), page.all, rows: rows)
            }
            .padding(.horizontal, 40)
        }
    }

    @ViewBuilder private func block(_ title: Text, _ apps: [LauncherApp], rows: Int) -> some View {
        if !apps.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                title.font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(92), spacing: 18, alignment: .top), count: rows), spacing: Self.gap) {
                    ForEach(apps, id: \.bundleID, content: cell)
                }
            }
        }
    }

    private func cell(_ app: LauncherApp) -> some View {
        let pinned = model.state.pinned.contains(app.bundleID)
        return Button { onLaunch(app) } label: {
            VStack(spacing: 6) {
                Image(nsImage: LauncherIconCache.icon(forPath: app.path)).resizable().frame(width: 64, height: 64)
                Text(verbatim: app.name).font(.system(size: 12)).lineLimit(1).frame(maxWidth: 100)
            }
            .frame(width: Self.cell)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if pinned { Button("Unpin") { onTogglePin(app) } } else { Button("Pin") { onTogglePin(app) } }
        }
    }
}

@MainActor
final class LauncherModel: ObservableObject {
    @Published var query = ""
    @Published var focusNonce = 0
    @Published var searchPosition: LauncherSearchPosition = .top
    @Published var scrollDirection: LauncherScrollDirection = .vertical
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
            default: return false
            }
        }
    }
}
