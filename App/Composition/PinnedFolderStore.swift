import Foundation

/// 固定文件夹区的持久层：有序文件夹路径列表（顺序即显示序，拖拽重排/拖放固定都改这个数组）。
/// 应用非沙盒，存标准化裸路径即可，无需 security-scoped bookmark。
@MainActor
final class PinnedFolderStore: ObservableObject {
    @Published private(set) var folderPaths: [String] = []
    /// 逐文件夹排序方式（normalized path → FolderSortOrder.rawValue）。缺省 = 默认排序，不落盘。
    @Published private(set) var sortOrders: [String: String] = [:]
    /// Pinned by us, not by the user, and not opened yet: nothing may read such a folder (no cover
    /// enumeration, no watcher), or a privacy-protected one — Downloads — raises the system's
    /// access prompt at first launch with no user action behind it. Cleared by the first open.
    private(set) var unopenedSeedPaths: Set<String> = []
    /// Builtin folders the user removed on purpose, so a launch does not push them back.
    private var removedBuiltins: Set<String> = []
    private let key = "pinnedFolderPaths"
    private let sortKey = "pinnedFolderSortOrders"
    private let unopenedSeedKey = "pinnedFolderUnopenedSeeds"
    private static let removedBuiltinKey = "pinnedFolderRemovedBuiltins"

    init() {
        folderPaths = UserDefaults.standard.stringArray(forKey: key) ?? []
        sortOrders = UserDefaults.standard.dictionary(forKey: sortKey) as? [String: String] ?? [:]
        unopenedSeedPaths = Set(UserDefaults.standard.stringArray(forKey: unopenedSeedKey) ?? [])
        removedBuiltins = Set(UserDefaults.standard.stringArray(forKey: Self.removedBuiltinKey) ?? [])
    }

    static func downloadsPath() -> String? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first.map { normalized($0.path) }
    }

    /// Downloads is part of the dock, not a preference (owner 2026-10-31): every launch puts it back.
    func isBuiltin(_ path: String) -> Bool { Self.downloadsPath() == Self.normalized(path) }

    func ensureBuiltins() {
        guard let downloads = Self.downloadsPath(),
              !removedBuiltins.contains(downloads),
              !contains(downloads)
        else { return }
        // Before `add`: its publication is what makes the cover store look at the folder.
        setUnopenedSeeds(unopenedSeedPaths.union([downloads]))
        add(downloads)
    }

    /// The chip menu's confirmed removal — the only way a builtin leaves the dock.
    func removeBuiltin(_ path: String) {
        let normalized = Self.normalized(path)
        removedBuiltins.insert(normalized)
        UserDefaults.standard.set(removedBuiltins.sorted(), forKey: Self.removedBuiltinKey)
        removeNow(normalized)
    }

    func isUnopenedSeed(_ path: String) -> Bool { unopenedSeedPaths.contains(Self.normalized(path)) }

    /// The user opened the folder: from here on it is read like any other. Returns whether it
    /// was an unopened seed, so the caller knows to refresh its cover.
    @discardableResult
    func noteOpened(_ path: String) -> Bool {
        guard isUnopenedSeed(path) else { return false }
        setUnopenedSeeds(unopenedSeedPaths.subtracting([Self.normalized(path)]))
        return true
    }

    private func setUnopenedSeeds(_ paths: Set<String>) {
        unopenedSeedPaths = paths
        UserDefaults.standard.set(paths.sorted(), forKey: unopenedSeedKey)
    }

    func contains(_ path: String) -> Bool { folderPaths.contains(Self.normalized(path)) }

    func add(_ path: String) {
        let normalized = Self.normalized(path)
        guard !normalized.isEmpty, !folderPaths.contains(normalized) else { return }
        folderPaths.append(normalized)
        if removedBuiltins.remove(normalized) != nil {
            UserDefaults.standard.set(removedBuiltins.sorted(), forKey: Self.removedBuiltinKey)
        }
        persist()
    }

    /// 拖放固定：插到显示序 index 位。已固定的路径 = 移到新位置（Dock 语义,重复拖入即重排）。
    func insert(_ path: String, at index: Int) {
        let normalized = Self.normalized(path)
        guard !normalized.isEmpty else { return }
        var next = folderPaths
        var target = min(max(0, index), next.count)
        if let existing = next.firstIndex(of: normalized) {
            next.remove(at: existing)
            if existing < target { target -= 1 }
        }
        next.insert(normalized, at: min(target, next.count))
        guard next != folderPaths else { return }
        folderPaths = next
        persist()
    }

    /// 区内拖拽重排：把 draggedPath 移到 targetPath 左/右（复用 StripOrdering 纯函数）。
    func reorder(draggedPath: String, relativeTo targetPath: String, after: Bool) {
        let next = StripOrdering.reordering(folderPaths,
                                            move: Self.normalized(draggedPath),
                                            relativeTo: Self.normalized(targetPath),
                                            after: after)
        guard next != folderPaths else { return }
        folderPaths = next
        persist()
    }

    /// Builtins are permanent: a drag or a stray menu gesture cannot drop them (`removeBuiltin` is the
    /// one path, and the chip asks first).
    func remove(_ path: String) {
        guard !isBuiltin(path) else { return }
        removeNow(path)
    }

    private func removeNow(_ path: String) {
        let normalized = Self.normalized(path)
        folderPaths.removeAll { $0 == normalized }
        if unopenedSeedPaths.contains(normalized) { setUnopenedSeeds(unopenedSeedPaths.subtracting([normalized])) }
        if sortOrders.removeValue(forKey: normalized) != nil {
            UserDefaults.standard.set(sortOrders, forKey: sortKey)
        }
        persist()
    }

    func sortOrder(for path: String) -> FolderSortOrder {
        FolderSortOrder(rawValue: sortOrders[Self.normalized(path)] ?? "") ?? .default
    }

    func setSortOrder(_ order: FolderSortOrder, for path: String) {
        let normalized = Self.normalized(path)
        guard sortOrders[normalized] != order.rawValue else { return }
        sortOrders[normalized] = order.rawValue
        UserDefaults.standard.set(sortOrders, forKey: sortKey)
    }

    private func persist() {
        UserDefaults.standard.set(folderPaths, forKey: key)
    }

    /// 标准化：展开 ~ / 折叠 .. 并去尾斜杠，保证同一文件夹只固定一次。
    static func normalized(_ path: String) -> String {
        FilePathNormalization.normalized(path)
    }
}
