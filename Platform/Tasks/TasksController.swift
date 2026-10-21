import Foundation

/// Observable to-do list + tracker shared by the Tasks flyout. Persists on every change; no timers (the view
/// ticks only while a tracker runs).
@MainActor
final class TasksController: ObservableObject {
    @Published private(set) var list: TaskList
    private let store: TasksStore

    init(store: TasksStore = TasksStore(url: TasksStore.defaultURL)) {
        self.store = store
        var loaded = store.load()
        // A tracker left running by a quit or crash keeps counting from its start, which would credit the time the
        // app was closed; close it at launch instead.
        if let id = loaded.runningID, let start = loaded.items.first(where: { $0.id == id })?.runningSince {
            loaded.stopTracking(id, now: start)
        }
        list = loaded
    }

    func add(_ text: String) { mutate { $0.add(text: text) } }
    func toggle(_ id: UUID) { mutate { $0.toggle(id) } }
    func toggleImportant(_ id: UUID) { mutate { $0.toggleImportant(id) } }
    func setDue(_ id: UUID, _ day: Date?) { mutate { $0.setDue(id, day) } }
    func delete(_ id: UUID) { mutate { $0.delete(id) } }
    func clearCompleted() { mutate { $0.clearCompleted(before: Date()) } }

    func toggleTracking(_ id: UUID) {
        mutate { list in
            if list.runningID == id { list.stopTracking(id) } else { list.startTracking(id) }
        }
    }

    private func mutate(_ change: (inout TaskList) -> Void) {
        var next = list
        change(&next)
        guard next != list else { return }
        list = next
        try? store.save(next)
    }
}
