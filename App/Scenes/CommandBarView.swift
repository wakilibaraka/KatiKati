import AppKit
import SwiftUI

/// Phase 27b: the command-bar's state. The controller fills `apps`/`running`/`usage` at summon; the view
/// edits `query` and reads `results`.
@MainActor
final class CommandBarModel: ObservableObject {
    @Published var query = ""
    @Published var results: [CommandBarResult] = []
    var focusNonce = 0
    var apps: [LauncherApp] = []
    var running: [RunningAppRef] = []
    var usage: [String: LauncherUsage] = [:]

    func refresh() {
        results = CommandBarResults.build(query: query, apps: apps, usage: usage, running: running)
    }
}

/// The compact palette: a search field over one result list. Reuses the Phase 21 answer rows and the
/// launcher index; actions are routed by the controller.
struct CommandBarView: View {
    @ObservedObject var model: CommandBarModel
    let onRun: (CommandBarResult) -> Void
    let onClose: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Command Bar", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .focused($focused)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .onChange(of: model.query) { _ in model.refresh() }
                .onSubmit { if let first = model.results.first { onRun(first) } }
            Divider().opacity(0.25)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.results.enumerated()), id: \.offset) { index, result in
                        row(result, selected: index == 0)
                            .onTapGesture { onRun(result) }
                    }
                }
                .padding(6)
            }
        }
        .frame(width: 640, height: 380)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .onAppear { focused = true }
        .onChange(of: model.focusNonce) { _ in focused = true }
        .accessibilityLabel(Text("Command Bar"))
    }

    @ViewBuilder private func row(_ result: CommandBarResult, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol(result)).font(.system(size: 15, weight: .semibold)).frame(width: 22)
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
                Text("Quit").foregroundColor(.secondary)
                Text(verbatim: running.name)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Color.accentColor.opacity(0.22) : Color.clear))
        .contentShape(Rectangle())
    }

    private func symbol(_ result: CommandBarResult) -> String {
        switch result {
        case .answer(.math): return "equal"
        case .answer(.web): return "globe"
        case .app: return "app"
        case .quit: return "power"
        }
    }
}
