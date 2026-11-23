import AppKit
import Foundation
import UniformTypeIdentifiers

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

// MARK: - Dock App Groups Store (DockFolders, Slice DO-5)

/// Stores iOS/iPadOS-style Dock App Groups and optionally syncs them two-way with `LauncherStore` folders.
@MainActor
final class DockAppGroupStore: ObservableObject {
    static let shared = DockAppGroupStore()

    @Published private(set) var groups: [DockAppGroup] = []
    @Published private(set) var isEnabled: Bool
    @Published private(set) var syncWithLauncherFolders: Bool
    @Published private(set) var viewMode: PopViewMode

    private let defaults: UserDefaults
    private let launcherStoreURL: URL

    init(defaults: UserDefaults = .standard, launcherStoreURL: URL = LauncherStore.defaultURL) {
        self.defaults = defaults
        self.launcherStoreURL = launcherStoreURL
        if let data = defaults.data(forKey: DockAppGroups.defaultsKey),
           let decoded = try? JSONDecoder().decode([DockAppGroup].self, from: data) {
            groups = decoded
        }
        isEnabled = defaults.object(forKey: DockAppGroups.enabledKey) as? Bool ?? true
        syncWithLauncherFolders = defaults.bool(forKey: DockAppGroups.syncLauncherKey)
        viewMode = PopViewMode(rawValue: defaults.string(forKey: DockAppGroups.viewModeKey) ?? "") ?? .grid
        if syncWithLauncherFolders { syncFromLauncherIfEnabled() }
    }

    func group(id: String) -> DockAppGroup? { groups.first { $0.id == id } }

    func createGroup(name: String, appIDs: [String] = [], iconGrid: DockAppGroupIconGrid = .grid2x2) {
        apply(DockAppGroups.create(groups, name: name, appIDs: appIDs, iconGrid: iconGrid))
    }

    func addApp(_ appID: String, to groupID: String) {
        apply(DockAppGroups.add(groups, appID: appID, to: groupID))
    }

    func removeApp(_ appID: String, from groupID: String) {
        apply(DockAppGroups.remove(groups, appID: appID, from: groupID))
    }

    func renameGroup(_ groupID: String, to name: String) {
        apply(DockAppGroups.rename(groups, id: groupID, to: name))
    }

    func setIconGrid(_ grid: DockAppGroupIconGrid, for groupID: String) {
        apply(DockAppGroups.setIconGrid(groups, id: groupID, to: grid))
    }

    func deleteGroup(_ groupID: String) {
        let deleted = group(id: groupID)
        let next = DockAppGroups.delete(groups, id: groupID)
        apply(next, syncToLauncher: false)
        guard syncWithLauncherFolders, let deleted else { return }
        let store = LauncherStore(url: launcherStoreURL)
        var state = store.load()
        let folderID = deleted.syncedLauncherFolderID ?? deleted.id
        let nextFolders = LauncherFolders.delete(state.folders, id: folderID)
        if nextFolders != state.folders {
            state.folders = nextFolders
            try? store.save(state)
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: DockAppGroups.enabledKey)
    }

    func setViewMode(_ mode: PopViewMode) {
        guard viewMode != mode else { return }
        viewMode = mode
        defaults.set(mode.rawValue, forKey: DockAppGroups.viewModeKey)
    }

    func setSyncWithLauncher(_ sync: Bool) {
        guard syncWithLauncherFolders != sync else { return }
        syncWithLauncherFolders = sync
        defaults.set(sync, forKey: DockAppGroups.syncLauncherKey)
        if sync { syncFromLauncherIfEnabled() }
    }

    func syncFromLauncherIfEnabled() {
        guard syncWithLauncherFolders else { return }
        let launcherFolders = LauncherStore(url: launcherStoreURL).load().folders
        apply(DockAppGroups.importingFromLauncher(launcherFolders, into: groups), syncToLauncher: false)
    }

    func autoGroupInstalledApps() {
        Task { @MainActor [weak self] in
            let scanned = await Task.detached(priority: .utility) { LauncherIndexer.scanDirectories() }.value
            guard let self else { return }
            let autoGroups = DockAppGroups.autoGroupedByCategory(apps: scanned)
            let custom = self.groups.filter { !$0.id.hasPrefix("\(DockAppGroups.idPrefix)cat.") }
            self.apply(custom + autoGroups)
        }
    }

    func handleAppDrop(_ providers: [NSItemProvider], into groupID: String) -> Bool {
        let pasteboardURLs = (NSPasteboard(name: .drag).readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]) ?? []
        guard !providers.isEmpty || !pasteboardURLs.isEmpty else { return false }
        for url in pasteboardURLs where url.pathExtension.lowercased() == "app" {
            if let bid = Bundle(url: url)?.bundleIdentifier { addApp(bid, to: groupID) }
        }
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let url, url.pathExtension.lowercased() == "app",
                      let bid = Bundle(url: url)?.bundleIdentifier else { return }
                Task { @MainActor in self?.addApp(bid, to: groupID) }
            }
        }
        return true
    }

    private func apply(_ next: [DockAppGroup], syncToLauncher: Bool = true) {
        guard next != groups else { return }
        groups = next
        if let data = try? JSONEncoder().encode(next) {
            defaults.set(data, forKey: DockAppGroups.defaultsKey)
        }
        guard syncToLauncher, syncWithLauncherFolders else { return }
        let store = LauncherStore(url: launcherStoreURL)
        var state = store.load()
        let nextFolders = DockAppGroups.exportingToLauncher(next, existing: state.folders)
        if nextFolders != state.folders {
            state.folders = nextFolders
            try? store.save(state)
        }
    }
}
