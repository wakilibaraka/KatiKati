import Foundation

/// How the drawer pop lays its items out, the three views DockPops calls Grid / List / Tiles.
enum PopViewMode: String, Codable, CaseIterable, Identifiable {
    case grid, list, tiles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: return String(localized: "Grid")
        case .list: return String(localized: "List")
        case .tiles: return String(localized: "Tiles")
        }
    }
}

/// Persistence for the DockPops-style drawer pop: an ordered list of `PopItem`s (apps, files, folders),
/// at most `PopPolicy.capacity`. Every list decision is `PopPolicy`'s; this class only loads and saves.
///
/// First launch migrates the old app-only drawer (`drawerBundleIDs` in `drawerDisplayOrder` order) into the
/// pop. The legacy keys are left in place so a downgrade still finds its drawer.
@MainActor
final class PopStore: ObservableObject {
    /// The one drawer pop. Shared like `BackgroundAppsStore` / `TrashStateStore`: the strip chip, its
    /// popup and the stash sync (`AppDelegate`) all read the same list.
    static let shared = PopStore()

    @Published private(set) var items: [PopItem] = []
    /// How many items the last `add` could not fit; the UI reads it to say "Pop is full".
    @Published private(set) var lastRejectedForCapacity = 0
    /// Grid / List / Tiles, the pop's own view (right-click the drawer icon → View).
    @Published private(set) var viewMode: PopViewMode = .grid
    /// The pop's own theme; nil follows the app's Appearance theme.
    @Published private(set) var theme: DockThemeStyle?

    nonisolated static let itemsKey = "com.katikati.drawer.popItems"
    nonisolated static let viewModeKey = "com.katikati.drawer.popViewMode"
    nonisolated static let themeKey = "com.katikati.drawer.popTheme"
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
        if let raw = defaults.string(forKey: Self.viewModeKey), let mode = PopViewMode(rawValue: raw) {
            viewMode = mode
        }
        if let data = defaults.data(forKey: Self.themeKey) {
            theme = try? JSONDecoder().decode(DockThemeStyle.self, from: data)
        }
    }

    var isFull: Bool { items.count >= PopPolicy.capacity }

    func setViewMode(_ mode: PopViewMode) {
        guard mode != viewMode else { return }
        viewMode = mode
        defaults.set(mode.rawValue, forKey: Self.viewModeKey)
    }

    func setTheme(_ style: DockThemeStyle?) {
        guard style != theme else { return }
        theme = style
        if let data = style.flatMap({ try? JSONEncoder().encode($0) }) {
            defaults.set(data, forKey: Self.themeKey)
        } else {
            defaults.removeObject(forKey: Self.themeKey)
        }
    }

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

    /// Called whenever the stashed apps change (`PopPolicy.syncingApps`).
    func syncApps(drawerBundleIDs: [String]) {
        let next = PopPolicy.syncingApps(items, drawerBundleIDs: drawerBundleIDs)
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
