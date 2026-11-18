import AppKit
import Foundation
import QuickLookThumbnailing

/// Bounded LRU icon and QuickLook thumbnail cache for desktop folder boxes.
@MainActor
enum DesktopThumbnailCache {
    private static let icons: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 200
        return cache
    }()

    private static let thumbnails: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 200
        return cache
    }()

    static func clearAll() {
        icons.removeAllObjects()
        thumbnails.removeAllObjects()
    }

    static func icon(for path: String, size: CGFloat) -> NSImage {
        let key = "\(path)|\(Int(size.rounded()))" as NSString
        if let cached = icons.object(forKey: key) { return cached }
        let base = NSWorkspace.shared.icon(forFile: path)
        let copy = (base.copy() as? NSImage) ?? base
        copy.size = NSSize(width: size, height: size)
        icons.setObject(copy, forKey: key)
        return copy
    }

    static func cachedThumbnail(path: String, modified: Date?, size: CGFloat, scale: CGFloat) -> NSImage? {
        thumbnails.object(forKey: thumbnailKey(path: path, modified: modified, size: size, scale: scale))
    }

    static func loadThumbnail(path: String, modified: Date?, size: CGFloat, scale: CGFloat) async -> NSImage? {
        let key = thumbnailKey(path: path, modified: modified, size: size, scale: scale)
        if let hit = thumbnails.object(forKey: key) { return hit }

        let request = QLThumbnailGenerator.Request(
            fileAt: URL(fileURLWithPath: path),
            size: CGSize(width: size, height: size),
            scale: max(1, scale),
            representationTypes: .thumbnail
        )
        request.iconMode = true

        let image: NSImage? = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
                if let rep {
                    continuation.resume(returning: NSImage(cgImage: rep.cgImage, size: NSSize(width: size, height: size)))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
        if let image { thumbnails.setObject(image, forKey: key) }
        return image
    }

    private static func thumbnailKey(path: String, modified: Date?, size: CGFloat, scale: CGFloat) -> NSString {
        "\(path)|\(modified?.timeIntervalSinceReferenceDate ?? 0)|\(Int(size.rounded()))|\(Int(scale.rounded()))" as NSString
    }
}

/// Live folder-backed state, off-main watcher, TCC recovery, and volume unmount resilience for one desktop box.
@MainActor
final class DesktopFolderBoxModel: ObservableObject {
    enum LoadState: Equatable {
        case loading
        case loaded([FolderContentsLoader.Entry])
        case needsPermission(String)
        case volumeUnavailable(String)
        case error(String)
    }

    @Published private(set) var loadState: LoadState = .loading
    @Published var selectedPaths: Set<String> = []
    @Published var cutURLs: [URL] = []

    private(set) var backingPath: String
    private(set) var sortMode: DesktopSortMode
    private(set) var manualOrder: [String]
    var onManualOrderUpdated: (([String]) -> Void)?

    private var watcher: DirectoryWatcher?
    private var watcherToken = 0
    private var generation = 0
    private var workspaceObservers: [NSObjectProtocol] = []
    private var appActiveObserver: NSObjectProtocol?
    private var isStarted = false

    private static let reloadQueue = DispatchQueue(
        label: "com.katikati.desktop-box-reload",
        qos: .userInitiated
    )

    init(
        backingPath: String,
        sortMode: DesktopSortMode,
        manualOrder: [String],
        onManualOrderUpdated: (([String]) -> Void)? = nil
    ) {
        self.backingPath = FilePathNormalization.normalized(backingPath)
        self.sortMode = sortMode
        self.manualOrder = manualOrder
        self.onManualOrderUpdated = onManualOrderUpdated
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        installObservers()
        attachWatcher()
        reload()
    }

    func stop() {
        isStarted = false
        watcher?.stop()
        watcher = nil
        watcherToken += 1
        let wsCenter = NSWorkspace.shared.notificationCenter
        for token in workspaceObservers { wsCenter.removeObserver(token) }
        workspaceObservers.removeAll()
        if let appActiveObserver { NotificationCenter.default.removeObserver(appActiveObserver) }
        appActiveObserver = nil
    }

    func updateConfig(backingPath: String, sortMode: DesktopSortMode, manualOrder: [String]) {
        let normalized = FilePathNormalization.normalized(backingPath)
        let pathChanged = normalized != self.backingPath
        let sortChanged = sortMode != self.sortMode
        let orderChanged = manualOrder != self.manualOrder
        self.backingPath = normalized
        self.sortMode = sortMode
        self.manualOrder = manualOrder

        guard isStarted else { return }
        if pathChanged {
            attachWatcher()
            reload()
        } else if sortChanged || orderChanged {
            if case .loaded(let entries) = loadState {
                let reconciled = DesktopFolderOrdering.reconcile(
                    entries: entries,
                    manualOrder: self.manualOrder,
                    sortMode: self.sortMode
                )
                loadState = .loaded(reconciled.ordered)
            } else {
                reload()
            }
        }
    }

    func reload() {
        let path = backingPath
        if Self.isVolumeMissing(for: path) {
            loadState = .volumeUnavailable(path)
            return
        }

        generation += 1
        let expectedGen = generation
        let targetURL = URL(fileURLWithPath: path, isDirectory: true)
        let currentSort = sortMode
        let currentManual = manualOrder

        Self.reloadQueue.async { [weak self] in
            let result = Result { try FolderContentsLoader.load(directory: targetURL) }
            Task { @MainActor [weak self] in
                guard let self, self.generation == expectedGen else { return }
                switch result {
                case .success(let entries):
                    let reconciled = DesktopFolderOrdering.reconcile(
                        entries: entries,
                        manualOrder: currentManual,
                        sortMode: currentSort
                    )
                    self.loadState = .loaded(reconciled.ordered)
                    if reconciled.updatedManualOrder != self.manualOrder {
                        self.manualOrder = reconciled.updatedManualOrder
                        self.onManualOrderUpdated?(reconciled.updatedManualOrder)
                    }
                    let present = Set(entries.map(\.url.path))
                    self.selectedPaths = self.selectedPaths.intersection(present)
                case .failure(let error):
                    if FolderContentsLoader.isPermissionDenied(error) {
                        self.loadState = .needsPermission(path)
                    } else if Self.isVolumeMissing(for: path) {
                        self.loadState = .volumeUnavailable(path)
                    } else {
                        self.loadState = .error(error.localizedDescription)
                    }
                }
            }
        }
    }

    func requestFolderAccessViaOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: backingPath, isDirectory: true)
        panel.prompt = String(localized: "Grant Access")
        if panel.runModal() == .OK, let chosen = panel.url {
            backingPath = FilePathNormalization.normalized(chosen.path)
            attachWatcher()
            reload()
        }
    }

    func noteTrashedInApp() {
        TrashStateStore.shared.noteTrashedInApp()
    }

    private func attachWatcher() {
        watcher?.stop()
        watcher = nil
        watcherToken += 1
        let expected = watcherToken
        let path = backingPath
        guard !Self.isVolumeMissing(for: path) else { return }

        DirectoryWatcher.start(
            path: path,
            onChange: { [weak self] in
                Task { @MainActor [weak self] in self?.reload() }
            },
            completion: { [weak self] newWatcher in
                Task { @MainActor [weak self] in
                    guard let self, self.watcherToken == expected, self.isStarted else {
                        newWatcher?.stop()
                        return
                    }
                    self.watcher = newWatcher
                }
            }
        )
    }

    private func installObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        let mount = wsCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else { return }
                if case .volumeUnavailable = self.loadState {
                    self.attachWatcher()
                    self.reload()
                }
            }
        }
        let unmount = wsCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else { return }
                if Self.isVolumeMissing(for: self.backingPath) {
                    self.watcher?.stop()
                    self.watcher = nil
                    self.loadState = .volumeUnavailable(self.backingPath)
                }
            }
        }
        workspaceObservers = [mount, unmount]

        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else { return }
                if case .needsPermission = self.loadState { self.reload() }
            }
        }
    }

    private static func isVolumeMissing(for path: String) -> Bool {
        guard path.hasPrefix("/Volumes/") else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return false }
        let mountPoint = "/\(parts[0])/\(parts[1])"
        return !FileManager.default.fileExists(atPath: mountPoint)
    }
}
