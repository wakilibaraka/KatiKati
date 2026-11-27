import AppKit
import Combine
import Foundation

/// Unified multi-provider desktop search (Phase 66A–B): Spotlight files, apps, Settings pages,
/// notes and to-dos, ranked together with persisted history and favorites.
@MainActor
final class DesktopSearchService: ObservableObject {
    static let shared = DesktopSearchService()

    @Published private(set) var results: [DesktopSearchResult] = []
    @Published private(set) var isSearching = false
    @Published private(set) var selection = DesktopSearchSelectionModel()
    @Published private(set) var history: DesktopSearchHistory
    @Published private(set) var favorites: DesktopSearchFavorites
    @Published private(set) var query = ""

    private let defaults: UserDefaults
    private let indexer = LauncherIndexer()
    private let store = LauncherStore(url: LauncherStore.defaultURL)
    private var apps: [LauncherApp] = []
    private var usage: [String: LauncherUsage] = [:]
    private var notes: [Note] = []
    private var notesLoaded = false
    private var searchTask: Task<Void, Never>?
    private var searchToken = UUID()
    private var appsObserver: AnyCancellable?
    private var started = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        history = DesktopSearchHistory.decode(defaults.string(forKey: DesktopSearchConfig.historyKey))
        favorites = DesktopSearchFavorites.decode(defaults.string(forKey: DesktopSearchConfig.favoritesKey))
        usage = store.load().usage
        appsObserver = indexer.$apps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] apps in
                guard let self else { return }
                self.apps = apps
                if !self.query.isEmpty { self.refreshLocalResults() }
            }
    }

    var orderedIDs: [String] { results.map(\.id) }

    var selectedResults: [DesktopSearchResult] {
        results.filter { selection.isSelected($0.id) }
    }

    var resultLimit: Int { DesktopSearchConfig.resultLimit(defaults: defaults) }

    func start() {
        guard !started else { return }
        started = true
        indexer.start()
        loadNotesIfNeeded()
        if !query.isEmpty { refreshLocalResults() }
    }

    func setQuery(_ value: String, immediate: Bool = false) {
        guard query != value else { return }
        query = value
        selection.clear()
        searchTask?.cancel()
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        refreshLocalResults()
        if immediate {
            startFileSearch(query: value)
        } else {
            searchTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard !Task.isCancelled, let self else { return }
                self.startFileSearch(query: value)
            }
        }
    }

    func submit() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        history = history.recording(trimmed)
        defaults.set(history.encoded(), forKey: DesktopSearchConfig.historyKey)
    }

    func clearHistory() {
        history = DesktopSearchHistory()
        defaults.removeObject(forKey: DesktopSearchConfig.historyKey)
    }

    func toggleFavorite(_ result: DesktopSearchResult) {
        favorites = favorites.toggling(result)
        defaults.set(favorites.encoded(), forKey: DesktopSearchConfig.favoritesKey)
    }

    func isFavorite(_ id: String) -> Bool { favorites.contains(id) }

    /// Re-runs the local providers (used after notes finish decrypting or the app index arrives).
    func refreshLocalResults() {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let local = localResults(for: query)
        let files = results.filter { $0.provider == .file }
        results = DesktopSearchRanker.rank(local + files, query: query, limit: resultLimit)
    }

    // MARK: - Selection

    func tap(_ id: String) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift) {
            selection.selectRange(to: id, in: orderedIDs)
        } else if flags.contains(.command) {
            selection.toggle(id, in: orderedIDs)
        } else {
            selection.replace([id])
        }
    }

    func rubberBand(_ rect: CGRect, rowFrames: [String: CGRect]) {
        selection.rubberBand(rect, rowFrames: rowFrames, additive: NSEvent.modifierFlags.contains(.command))
    }

    func clearSelection() { selection.clear() }

    func selectAll() { selection.replace(Set(orderedIDs)) }

    // MARK: - Providers

    private func localResults(for rawQuery: String) -> [DesktopSearchResult] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        var rows: [DesktopSearchResult] = []
        rows += appResults(query)
        rows += settingResults(query)
        rows += noteResults(query)
        rows += todoResults(query)
        return rows
    }

    private func appResults(_ query: String) -> [DesktopSearchResult] {
        LauncherSearch.search(query, in: apps, usage: usage, limit: 12).map { app in
            DesktopSearchResult(
                id: "app:\(app.bundleID.isEmpty ? app.path : app.bundleID)",
                provider: .app,
                title: app.name,
                subtitle: (app.path as NSString).abbreviatingWithTildeInPath,
                path: app.path,
                payload: app.bundleID,
                symbol: "app"
            )
        }
    }

    private func settingResults(_ query: String) -> [DesktopSearchResult] {
        SettingsSearchIndex.matchingTabs(for: query, in: SettingsTab.allCases).map { tab in
            DesktopSearchResult(
                id: "setting:\(tab.rawValue)",
                provider: .setting,
                title: tab.title,
                subtitle: tab.subtitle,
                payload: tab.rawValue,
                symbol: tab.symbolName
            )
        }
    }

    private func noteResults(_ query: String) -> [DesktopSearchResult] {
        let needle = query.lowercased()
        return notes.compactMap { note in
            guard note.displayTitle.lowercased().contains(needle) || note.body.lowercased().contains(needle) else {
                return nil
            }
            let snippet = note.body.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty } ?? ""
            return DesktopSearchResult(
                id: "note:\(note.id)",
                provider: .note,
                title: note.displayTitle,
                subtitle: String(snippet.prefix(120)),
                payload: note.id,
                symbol: "note.text"
            )
        }
    }

    private func todoResults(_ query: String) -> [DesktopSearchResult] {
        let needle = query.lowercased()
        return ProductivityServices.shared.tasks.list.items.compactMap { item in
            guard item.text.lowercased().contains(needle) else { return nil }
            return DesktopSearchResult(
                id: "todo:\(item.id.uuidString)",
                provider: .todo,
                title: item.text,
                subtitle: item.done ? String(localized: "Completed") : String(localized: "To-Do"),
                payload: item.id.uuidString,
                symbol: item.done ? "checkmark.circle" : "circle"
            )
        }
    }

    private func startFileSearch(query: String) {
        let token = UUID()
        searchToken = token
        let filter = SearchPathFilter(userExcludedPaths: DesktopSearchConfig.excludedPaths(defaults: defaults))
        let limit = resultLimit
        let local = localResults(for: query)

        if let indexed = FileIndexService.shared.search(terms: [query], extensions: [], imageOnly: false, limit: limit) {
            let files = fileResults(indexed, filter: filter)
            guard searchToken == token else { return }
            results = DesktopSearchRanker.rank(local + files, query: query, limit: limit)
            isSearching = false
            return
        }

        searchTask = Task { [weak self] in
            let files = await Task.detached(priority: .userInitiated) {
                DesktopSearchSpotlight.search(query: query, filter: filter, limit: limit)
            }.value
            guard !Task.isCancelled, let self, self.searchToken == token, self.query == query else { return }
            self.results = DesktopSearchRanker.rank(local + files, query: query, limit: limit)
            self.isSearching = false
        }
    }

    private func fileResults(_ entries: [FileEntry], filter: SearchPathFilter) -> [DesktopSearchResult] {
        filter.filtering(entries).map { entry in
            DesktopSearchResult(
                id: "file:\(entry.path)",
                provider: .file,
                title: entry.name,
                subtitle: (entry.path as NSString).deletingLastPathComponent,
                path: entry.path,
                symbol: "doc"
            )
        }
    }

    private func loadNotesIfNeeded() {
        guard !notesLoaded else { return }
        notesLoaded = true
        Task.detached(priority: .utility) { [weak self] in
            let directory = NotesStore.defaultDirectory()
            let keys = FileNoteKeyProvider(
                keyFile: FileNoteKeyProvider.defaultKeyFile(),
                legacy: KeychainNoteKeyProvider(),
                hasExistingNotes: { FileNoteKeyProvider.directoryHasNotes(directory) }
            )
            guard let store = try? NotesStore(directory: directory, keyProvider: keys) else { return }
            let loaded = store.loadAll().notes
            await MainActor.run {
                guard let self else { return }
                self.notes = loaded
                if !self.query.isEmpty { self.refreshLocalResults() }
            }
        }
    }
}
