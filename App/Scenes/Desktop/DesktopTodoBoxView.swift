import SwiftUI

/// Desktop To-Do widget content. Shares the one `TasksController` (and `tasks.json`) with the edge-deck flyout.
struct DesktopTodoBoxView: View {
    @ObservedObject var tasks: TasksController
    let onAcquireLock: (DesktopInteractionLock) -> Void
    let onReleaseLock: (DesktopInteractionLock) -> Void

    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    private var visibleItems: [TaskItem] {
        tasks.list.items.sorted { lhs, rhs in
            if lhs.done != rhs.done { return !lhs.done }
            if lhs.important != rhs.important { return lhs.important }
            return false
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            TextField(text: $draft, prompt: Text("Add a task…")) { EmptyView() }
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit {
                    tasks.add(draft)
                    draft = ""
                }
                .onChange(of: fieldFocused) { _, focused in
                    if focused { onAcquireLock(.inlineRename) } else { onReleaseLock(.inlineRename) }
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)

            if visibleItems.isEmpty {
                Spacer()
                Image(systemName: "checklist")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(visibleItems) { task in row(task) }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func row(_ task: TaskItem) -> some View {
        HStack(spacing: 8) {
            Button { tasks.toggle(task.id) } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.done ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            Text(verbatim: task.text)
                .font(.system(size: 12))
                .strikethrough(task.done)
                .foregroundStyle(task.done ? .secondary : .primary)
                .lineLimit(2)
            Spacer(minLength: 0)
            if task.important {
                Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.yellow)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .contextMenu {
            Button { tasks.toggleImportant(task.id) } label: {
                Label(String(localized: "Important"), systemImage: task.important ? "star.slash" : "star")
            }
            Button(role: .destructive) { tasks.delete(task.id) } label: {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
        }
    }
}
