import SwiftUI

/// To-dos with a per-task time tracker (Phase 7A-P3). Reuses the band-tile look of Reminders / Alarms.
struct TasksFlyoutView: View {
    @ObservedObject private var tasks = ProductivityServices.shared.tasks
    @AppStorage(TilePalette.storageKey) private var palette: TilePalette = .classic
    @Environment(\.colorScheme) private var colorScheme
    @State private var draft = ""

    var body: some View {
        let size = ProductivityFlyout.size(.tasks)
        let env = TileEnv(palette: palette, isDark: colorScheme == .dark)
        let list = tasks.list
        BandTile(env: env, kind: .reminders, width: size.width - 16, height: size.height - 16, header: {
            HStack {
                Text("Tasks")
                Spacer()
                if list.items.contains(where: { $0.done }) {
                    Button { tasks.clearCompleted() } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).help(Text("Clear Completed"))
                }
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    // Ticks only while a tracker is running (the view is static otherwise).
                    Text(verbatim: TaskDisplay.duration(list.totalTracked(at: list.runningID == nil ? Date(timeIntervalSince1970: 0) : ctx.date)))
                        .monospacedDigit().opacity(list.runningID == nil ? 0 : 0.85)
                }
            }
        }, content: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    TextField("Add a task", text: $draft, onCommit: addDraft).textFieldStyle(.roundedBorder)
                    Button(action: addDraft) { Image(systemName: "plus.circle.fill").font(.system(size: 16)) }
                        .buttonStyle(.plain).foregroundColor(env.accent(.reminders)).help(Text("Add a task"))
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if list.items.isEmpty {
                    Text("No tasks").font(.system(size: 12, weight: .semibold)).foregroundColor(env.secondary).padding(.top, 4)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(list.items) { item in row(item, env: env) }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        })
        .padding(8)
    }

    private func addDraft() { tasks.add(draft); draft = "" }

    private func row(_ item: TaskItem, env: TileEnv) -> some View {
        HStack(spacing: 6) {
            Button { tasks.toggle(item.id) } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle").font(.system(size: 14))
            }
            .buttonStyle(.plain).foregroundColor(env.accent(.reminders))
            Text(item.text)
                .font(.system(size: 12, weight: item.important ? .bold : .semibold))
                .strikethrough(item.done).opacity(item.done ? 0.45 : 1).lineLimit(1)
            Spacer(minLength: 4)
            if !item.done {
                Button { tasks.toggleTracking(item.id) } label: {
                    HStack(spacing: 3) {
                        if item.runningSince != nil {
                            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                                Text(verbatim: TaskDisplay.duration(item.elapsed(at: ctx.date))).monospacedDigit()
                            }
                        } else if item.trackedSeconds > 0 {
                            Text(verbatim: TaskDisplay.duration(item.trackedSeconds)).monospacedDigit().opacity(0.6)
                        }
                        Image(systemName: item.runningSince != nil ? "pause.circle.fill" : "play.circle")
                    }
                    .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundColor(item.runningSince != nil ? env.accent(.reminders) : env.secondary)
            }
        }
        .frame(height: 28)
        .contextMenu {
            if item.important { Button("Unmark Important") { tasks.toggleImportant(item.id) } }
            else { Button("Mark Important") { tasks.toggleImportant(item.id) } }
            Button("Delete") { tasks.delete(item.id) }
        }
    }
}
