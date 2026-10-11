import AppKit
import SwiftUI

/// The launcher surface (Phase 7B-L2): a search field over a results list. L3 replaces the list with the grid.
struct LauncherView: View {
    @ObservedObject var indexer: LauncherIndexer
    @ObservedObject var model: LauncherModel
    let onLaunch: (LauncherApp) -> Void
    let onClose: () -> Void

    private var results: [LauncherApp] {
        model.query.isEmpty ? indexer.apps : LauncherSearch.search(model.query, in: indexer.apps, usage: model.state.usage)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.001).onTapGesture(perform: onClose)
            VStack(spacing: 18) {
                LauncherSearchField(text: $model.query, focusNonce: model.focusNonce,
                                    onSubmit: { if let first = results.first { onLaunch(first) } },
                                    onCancel: onClose)
                    .frame(width: 420, height: 28)
                if results.isEmpty {
                    Text("No Apps Found").foregroundColor(.secondary).padding(.top, 40)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(results, id: \.bundleID) { app in
                                Button { onLaunch(app) } label: {
                                    HStack(spacing: 10) {
                                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                                            .resizable().frame(width: 32, height: 32)
                                        Text(verbatim: app.name).font(.system(size: 14))
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 10).padding(.vertical, 3)
                            }
                        }
                    }
                    .frame(width: 420)
                }
            }
            .padding(.top, 120)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .accessibilityLabel(Text("Launcher"))
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
