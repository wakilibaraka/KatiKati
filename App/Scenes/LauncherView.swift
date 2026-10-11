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

/// The launcher surface (Phase 7B-L4): the Pinned / Most Used / Recently Installed grid beside a sheet with the full
/// app list and the search field. The sheet sits on the side chosen in Settings (right by default). While searching,
/// the grid shows one flat set of matches and the sheet list narrows to them too.
struct LauncherView: View {
    @ObservedObject var indexer: LauncherIndexer
    @ObservedObject var model: LauncherModel
    let onLaunch: (LauncherApp) -> Void
    let onTogglePin: (LauncherApp) -> Void
    let onClose: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 128), spacing: 12)]

    private var matches: [LauncherApp] {
        LauncherSearch.search(model.query, in: indexer.apps, usage: model.state.usage)
    }

    var body: some View {
        let inset = model.searchPosition.reservedInsets(sheetSide: model.sheetSide)
        ZStack {
            Color.black.opacity(0.001).onTapGesture(perform: onClose)
            HStack(alignment: .top, spacing: 0) {
                if model.sheetSide == .left { sheet }
                content.frame(maxWidth: .infinity)
                if model.sheetSide == .right { sheet }
            }
            .padding(.top, 50 + inset.top + model.screenInsets.top)
            .padding(.bottom, inset.bottom + model.screenInsets.bottom)
            .padding(.leading, inset.leading - (model.sheetSide == .left ? 328 : 0) + model.screenInsets.leading)
            .padding(.trailing, inset.trailing - (model.sheetSide == .right ? 328 : 0) + model.screenInsets.trailing)
            searchField
                .padding(.top, model.screenInsets.top).padding(.bottom, model.screenInsets.bottom)
                .padding(.leading, model.screenInsets.leading).padding(.trailing, model.screenInsets.trailing)
        }
        .accessibilityLabel(Text("Launcher"))
    }

    private var searchField: some View {
        let p = model.searchPosition
        let sheetOnSameSide = (p == .left && model.sheetSide == .left) || (p == .right && model.sheetSide == .right)
        return LauncherSearchField(text: $model.query, focusNonce: model.focusNonce,
                                   onSubmit: { if let first = matches.first { onLaunch(first) } },
                                   onCancel: onClose)
            .frame(width: p.fieldWidth, height: 28)
            .padding(p == .top ? .top : p == .bottom ? .bottom : p == .left ? .leading : .trailing, 28 + (sheetOnSameSide ? 328 : 0))
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

    private var sheet: some View {
        VStack(spacing: 10) {
            Text("All Apps").font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(model.query.isEmpty ? indexer.apps : matches, id: \.bundleID) { app in
                        Button { onLaunch(app) } label: {
                            HStack(spacing: 10) {
                                Image(nsImage: LauncherIconCache.icon(forPath: app.path)).resizable().frame(width: 28, height: 28)
                                Text(verbatim: app.name).font(.system(size: 13)).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 3).padding(.horizontal, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 280)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.primary.opacity(0.08)))
        .padding(.horizontal, 24).padding(.bottom, 24)
    }

    @ViewBuilder private var content: some View {
        if model.query.isEmpty {
            let s = LauncherAppIndex.sections(apps: indexer.apps, usage: model.state.usage,
                                              pinned: model.state.pinned, now: Date())
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if !model.tiles.isEmpty { LauncherTilesRow(tiles: model.tiles, onClose: onClose) }
                    section(Text("Pinned"), s.pinned)
                    section(Text("Most Used"), s.mostUsed)
                    section(Text("Recently Installed"), s.recentlyInstalled)
                }
                .padding(.horizontal, 40).padding(.bottom, 80)
                .frame(maxWidth: 1000)
            }
        } else if matches.isEmpty {
            Text("No Apps Found").foregroundColor(.secondary).padding(.top, 40)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) { ForEach(matches, id: \.bundleID, content: cell) }
                    .padding(.horizontal, 40).padding(.bottom, 80)
                    .frame(maxWidth: 1000)
            }
        }
    }

    @ViewBuilder private func section(_ title: Text, _ apps: [LauncherApp]) -> some View {
        if !apps.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                title.font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
                LazyVGrid(columns: columns, spacing: 18) { ForEach(apps, id: \.bundleID, content: cell) }
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
    @Published var sheetSide: EdgeSide = .right
    @Published var searchPosition: LauncherSearchPosition = .top
    @Published var tiles: [LauncherTile] = LauncherTile.allCases
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
