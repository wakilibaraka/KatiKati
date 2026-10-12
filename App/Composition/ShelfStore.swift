import Foundation

/// 中转格（临时文件中转）的持久层：路径列表，**引用不搬家**——文件留在原处，拖出时由
/// 目的地按系统语义拷贝/移动。新暂存插头部（最新在前）；v1 存裸路径不存 bookmark，
/// 文件被移走/删除即失效，由 `prune()`（弹窗打开时调）剔除。
/// 列表操作是纯静态函数（stashing/pruned），进单测。
@MainActor
final class ShelfStore: ObservableObject {
    /// Pinned-first, newest-first display order. Kept as the paths the dock/popup already consume.
    @Published private(set) var items: [ShelfItem] = []
    var itemPaths: [String] { items.map(\.path) }

    private let legacyKey = "shelfItemPaths"
    private let itemsKey = "shelfItemsV2"
    private let defaults: UserDefaults

    // Settings (written by `AppSettingsStore`, read here at action time so the store stays independent).
    nonisolated static let autoExpireKey = "com.katikati.shelf.autoExpire"
    nonisolated static let expiryDaysKey = "com.katikati.shelf.expiryDays"
    nonisolated static let storageKey = "com.katikati.shelf.storage"
    nonisolated static let shakeKey = "com.katikati.shelf.shake"
    /// Set the first time anything is parked; the first-use guide never shows again after it.
    nonisolated static let introSeenKey = "com.katikati.shelf.introSeen"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: itemsKey), let decoded = try? JSONDecoder().decode([ShelfItem].self, from: data) {
            items = ShelfPolicy.ordered(decoded)
        } else if let legacy = defaults.stringArray(forKey: legacyKey), !legacy.isEmpty {
            items = ShelfPolicy.ordered(ShelfPolicy.migrated(paths: legacy, now: Date()))
            persist()
        }
        if !items.isEmpty { defaults.set(true, forKey: Self.introSeenKey) }   // existing users are past the guide
        applyExpiry()
    }

    var introSeen: Bool { defaults.bool(forKey: Self.introSeenKey) }

    var storage: ShelfStorage { ShelfStorage(rawValue: defaults.string(forKey: Self.storageKey) ?? "") ?? .reference }
    var autoExpire: Bool { defaults.bool(forKey: Self.autoExpireKey) }
    var expiryDays: Int {
        let d = defaults.integer(forKey: Self.expiryDaysKey)
        return ShelfPolicy.expiryChoices.contains(d) ? d : 1
    }

    /// Matches on the normalized form of both sides (`standardizingPath` drops a leading `/private`).
    private func item(for path: String) -> ShelfItem? {
        let normalized = Self.normalized(path)
        return items.first { Self.normalized($0.path) == normalized }
    }

    func isPinned(_ path: String) -> Bool { item(for: path)?.isPinned ?? false }

    func stash(paths: [String]) {
        let normalized = paths.map(Self.normalized)
        let entries: [(path: String, isOwnedCopy: Bool)]
        if storage == .copy {
            entries = normalized.map { Self.copyIntoShelf($0) ?? ($0, false) }
        } else {
            entries = normalized.map { ($0, false) }
        }
        let next = ShelfPolicy.ordered(ShelfPolicy.stashing(items, adding: entries, now: Date()))
        guard next != items else { return }
        items = next
        if !items.isEmpty { defaults.set(true, forKey: Self.introSeenKey) }
        persist()
    }

    func togglePin(_ path: String) {
        guard let item = item(for: path) else { return }
        items = ShelfPolicy.ordered(ShelfPolicy.togglingPin(items, id: item.id))
        persist()
    }

    func remove(_ path: String) {
        guard let item = item(for: path) else { return }
        Self.deleteCopyIfOwned(item)
        items = ShelfPolicy.removing(items, path: item.path)
        persist()
    }

    /// "Clear" keeps pinned items.
    func clear() {
        let r = ShelfPolicy.clearingUnpinned(items)
        guard !r.dropped.isEmpty else { return }
        r.dropped.forEach(Self.deleteCopyIfOwned)
        items = ShelfPolicy.ordered(r.kept)
        persist()
    }

    /// Drops unpinned items older than the configured days when auto-expire is on.
    func applyExpiry(now: Date = Date()) {
        guard autoExpire else { return }
        let r = ShelfPolicy.expired(items, now: now, days: expiryDays)
        guard !r.dropped.isEmpty else { return }
        r.dropped.forEach(Self.deleteCopyIfOwned)
        items = ShelfPolicy.ordered(r.kept)
        persist()
    }

    /// 剔除已不存在的路径（打开中转弹窗时调）。返回是否有变化。
    /// Only a definitely missing path is dropped: an unreadable one (e.g. a Desktop file while the
    /// Desktop permission is not granted) is still the user's file.
    @discardableResult
    func prune() -> Bool {
        applyExpiry()
        let kept = items.filter { FileReachability.of(path: $0.path) != .missing }
        guard kept.count != items.count else { return false }
        items = ShelfPolicy.ordered(kept)
        persist()
        return true
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: itemsKey) }
        defaults.set(items.map(\.path), forKey: legacyKey)   // keep the old key readable for a downgrade
    }

    // MARK: copy storage

    nonisolated static var shelfFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("KatiKati/Shelf", isDirectory: true)
    }

    /// Copies `path` into its own `<uuid>` folder under the shelf folder. nil = copy failed (the caller
    /// falls back to a reference).
    nonisolated private static func copyIntoShelf(_ path: String) -> (String, Bool)? {
        let source = URL(fileURLWithPath: path)
        let dir = shelfFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let target = dir.appendingPathComponent(source.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: target)
            return (target.path, true)
        } catch {
            try? FileManager.default.removeItem(at: dir)
            return nil
        }
    }

    nonisolated private static func deleteCopyIfOwned(_ item: ShelfItem) {
        guard item.isOwnedCopy else { return }
        let dir = URL(fileURLWithPath: item.path).deletingLastPathComponent()
        guard dir.deletingLastPathComponent().standardizedFileURL == shelfFolder.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - 纯逻辑（单测覆盖）

    /// 标准化：展开 ~ / 折叠 .. 并去尾斜杠（与 PinnedFolderStore 同一口径，实现在 `FilePathNormalization`）。
    nonisolated static func normalized(_ path: String) -> String {
        FilePathNormalization.normalized(path)
    }

    /// 暂存合并：新条目（自身去重、去空）插头部；已在列表里的移到头部（重复暂存 = 提到最前）。
    nonisolated static func stashing(_ current: [String], adding: [String]) -> [String] {
        var seen = Set<String>()
        let incoming = adding.filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !incoming.isEmpty else { return current }
        return incoming + current.filter { !seen.contains($0) }
    }

    /// 剔除不存在的路径（exists 注入，测试不碰真文件系统）。
    nonisolated static func pruned(_ paths: [String], exists: (String) -> Bool) -> [String] {
        paths.filter(exists)
    }
}
