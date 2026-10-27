import Foundation

/// Persistence for the DockPops-style drawer pop: an ordered list of `PopItem`s (apps, files, folders),
/// at most `PopPolicy.capacity`. Every list decision is `PopPolicy`'s; this class only loads and saves.
///
/// First launch migrates the old app-only drawer (`drawerBundleIDs` in `drawerDisplayOrder` order) into the
/// pop. The legacy keys are left in place so a downgrade still finds its drawer.
@MainActor
final class PopStore: ObservableObject {
    @Published private(set) var items: [PopItem] = []
    /// How many items the last `add` could not fit; the UI reads it to say "Pop is full".
    @Published private(set) var lastRejectedForCapacity = 0

    nonisolated static let itemsKey = "com.katikati.drawer.popItems"
    private static let legacyBundleIDsKey = "drawerBundleIDs"
    private static let legacyOrderKey = "drawerDisplayOrder"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.itemsKey),
           let decoded = try? JSONDecoder().decode([PopItem].self, from: data) {
            items = decoded
        } else {
            items = PopPolicy.migrating(
                legacyBundleIDs: defaults.stringArray(forKey: Self.legacyBundleIDsKey) ?? [],
                legacyOrder: defaults.stringArray(forKey: Self.legacyOrderKey) ?? [])
            persist()
        }
    }

    var isFull: Bool { items.count >= PopPolicy.capacity }

    func contains(_ item: PopItem) -> Bool { items.contains { $0.id == item.id } }

    func add(_ new: [PopItem]) {
        let result = PopPolicy.adding(new, to: items)
        lastRejectedForCapacity = result.rejectedForCapacity
        if result.items != items { items = result.items; persist() }
    }

    func remove(_ id: String) {
        let next = PopPolicy.removing(id, from: items)
        if next != items { items = next; persist() }
    }

    func reorder(draggedID: String, relativeTo targetID: String, after: Bool) {
        let next = PopPolicy.reordering(items, draggedID: draggedID, relativeTo: targetID, after: after)
        if next != items { items = next; persist() }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Self.itemsKey)
    }
}
