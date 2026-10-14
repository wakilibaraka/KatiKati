import AppKit
import SwiftUI

/// Phase 27b: the command-bar's state. The controller fills `apps`/`running`/`usage` at summon; the view
/// edits `query` and reads `results`. `selection` is driven by the controller's key monitor.
@MainActor
final class CommandBarModel: ObservableObject {
    @Published var query = ""
    @Published var results: [CommandBarResult] = []
    @Published var selection = 0
    var focusNonce = 0
    var apps: [LauncherApp] = []
    var running: [RunningAppRef] = []
    var usage: [String: LauncherUsage] = [:]
    var custom: [CustomCommand] = []
    var processes: [ProcessEntry] = []

    func refresh() {
        results = CommandBarResults.build(query: query, apps: apps, usage: usage, running: running,
                                          custom: custom, processes: processes,
                                          generate: { GeneratorService.value(for: $0) ?? "" })
        selection = 0
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
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(model.results.enumerated()), id: \.offset) { index, result in
                            row(result, selected: index == model.selection)
                                .id(index)
                                .onTapGesture { onRun(result) }
                        }
                    }
                    .padding(6)
                }
                .onChange(of: model.selection) { value in
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(value, anchor: .center) }
                }
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
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Color.accentColor.opacity(0.22) : Color.clear))
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
        case .generator:
            Image(systemName: "wand.and.stars").font(.system(size: 15, weight: .semibold)).frame(width: 24, height: 24)
        case .custom(let command):
            Image(systemName: command.kind == .link ? "link" : "terminal").font(.system(size: 15, weight: .semibold)).frame(width: 24, height: 24)
        case .process:
            Image(systemName: "bolt.slash").font(.system(size: 15, weight: .semibold)).frame(width: 24, height: 24)
        case .script:
            Image(systemName: "terminal").font(.system(size: 15, weight: .semibold)).frame(width: 24, height: 24)
        case .shortcut:
            Image(systemName: "bolt.fill").font(.system(size: 15, weight: .semibold)).frame(width: 24, height: 24)
        case .path:
            Image(systemName: "doc").font(.system(size: 15, weight: .semibold)).frame(width: 24, height: 24)
        }
    }
}
