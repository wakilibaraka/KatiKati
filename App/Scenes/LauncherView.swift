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

/// The launcher surface (Phase 7B-L3): search on top, then the Pinned / Most Used / Recently Installed grid.
/// While searching, one flat grid of matches.
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
        ZStack {
            Color.black.opacity(0.001).onTapGesture(perform: onClose)
            VStack(spacing: 22) {
                LauncherSearchField(text: $model.query, focusNonce: model.focusNonce,
                                    onSubmit: { if let first = matches.first { onLaunch(first) } },
                                    onCancel: onClose)
                    .frame(width: 420, height: 28)
                content
            }
            .padding(.top, 90)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .accessibilityLabel(Text("Launcher"))
    }

    @ViewBuilder private var content: some View {
        if model.query.isEmpty {
            let s = LauncherAppIndex.sections(apps: indexer.apps, usage: model.state.usage,
                                              pinned: model.state.pinned, now: Date())
            let shown = Set((s.pinned + s.mostUsed + s.recentlyInstalled).map(\.bundleID))
            let rest = indexer.apps.filter { !shown.contains($0.bundleID) }
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    section(Text("Pinned"), s.pinned)
                    section(Text("Most Used"), s.mostUsed)
                    section(Text("Recently Installed"), s.recentlyInstalled)
                    section(Text("All Apps"), rest)
                }
                .padding(.horizontal, 60).padding(.bottom, 80)
                .frame(maxWidth: 1000)
            }
        } else if matches.isEmpty {
            Text("No Apps Found").foregroundColor(.secondary).padding(.top, 40)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) { ForEach(matches, id: \.bundleID, content: cell) }
                    .padding(.horizontal, 60).padding(.bottom, 80)
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
