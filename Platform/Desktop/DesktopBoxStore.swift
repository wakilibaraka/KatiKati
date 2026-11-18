import Combine
import CoreGraphics
import Foundation

enum DesktopBoxRecoveryState: Equatable, Sendable {
    case clean
    case recoveredFromBackup
    case corruptPrimaryAndNoBackup
}

/// Atomic JSON store for desktop widgets with `.bak` rotation, corruption recovery, and debounced saves.
@MainActor
final class DesktopBoxStore: ObservableObject {
    @Published private(set) var items: [DesktopWidgetItem] = []
    @Published private(set) var recoveryState: DesktopBoxRecoveryState = .clean
    @Published private(set) var lastSaveError: String?

    let storageURL: URL
    private var backupURL: URL { storageURL.appendingPathExtension("bak") }
    private var corruptArchiveURL: URL { storageURL.appendingPathExtension("corrupt") }
    private var pendingSaveWork: DispatchWorkItem?
    private let debounceInterval: TimeInterval

    nonisolated static var defaultStorageURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support
            .appendingPathComponent("KatiKati", isDirectory: true)
            .appendingPathComponent("desktop-boxes.json", isDirectory: false)
    }

    nonisolated static var defaultStarterInboxURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("KatiKati", isDirectory: true)
            .appendingPathComponent("Inbox", isDirectory: true)
    }

    init(storageURL: URL = DesktopBoxStore.defaultStorageURL, debounceInterval: TimeInterval = 0.35) {
        self.storageURL = storageURL
        self.debounceInterval = debounceInterval
        load()
    }

    func item(for id: UUID) -> DesktopWidgetItem? {
        items.first { $0.id == id }
    }

    func add(_ item: DesktopWidgetItem) {
        var copy = item
        if copy.zOrder == 0 {
            copy.zOrder = (items.map(\.zOrder).max() ?? 0) + 1
        }
        items.append(copy)
        flushNow()
    }

    func update(_ item: DesktopWidgetItem, immediate: Bool = false) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard items[index] != item else { return }
        items[index] = item
        immediate ? flushNow() : scheduleSave()
    }

    func updateFrames(
        _ frames: [UUID: CGRect],
        normalized: [UUID: NormalizedWidgetRect],
        immediate: Bool = false
    ) {
        var changed = false
        for index in items.indices {
            let id = items[index].id
            if let frame = frames[id], items[index].frame != frame {
                items[index].frame = frame
                changed = true
            }
            if let norm = normalized[id], items[index].normalizedFrame != norm {
                items[index].normalizedFrame = norm
                changed = true
            }
        }
        guard changed else { return }
        immediate ? flushNow() : scheduleSave()
    }

    func remove(id: UUID) {
        let before = items.count
        items.removeAll { $0.id == id }
        guard items.count != before else { return }
        flushNow()
    }

    /// Creates `~/KatiKati/Inbox` (or custom URL) if missing and registers a non-TCC starter box.
    @discardableResult
    func createStarterInboxBox(
        at directoryURL: URL = DesktopBoxStore.defaultStarterInboxURL,
        displayUUID: String?,
        visibleFrame: CGRect,
        gap: CGFloat = CGFloat(DesktopCanvasConfig.defaultSnapGap),
        edgeMargin: CGFloat = CGFloat(DesktopCanvasConfig.defaultEdgeMargin)
    ) throws -> DesktopWidgetItem {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let normalizedPath = FilePathNormalization.normalized(directoryURL.path)
        if let existing = items.first(where: { $0.backingPath == normalizedPath }) {
            return existing
        }
        let siblings = items.filter { !$0.isHidden }.map(\.frame)
        let frame = DesktopLayoutEngine.initialPlacement(
            existing: siblings,
            visibleFrame: visibleFrame,
            gap: gap,
            edgeMargin: edgeMargin
        )
        let box = DesktopWidgetItem(
            kind: .folder,
            title: directoryURL.lastPathComponent,
            backingPath: normalizedPath,
            displayUUID: displayUUID,
            frame: frame,
            normalizedFrame: DesktopLayoutEngine.normalize(frame, in: visibleFrame)
        )
        add(box)
        return box
    }

    func scheduleSave() {
        pendingSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.writeToDisk()
        }
        pendingSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    func flushNow() {
        pendingSaveWork?.cancel()
        pendingSaveWork = nil
        writeToDisk()
    }

    private func load() {
        let fm = FileManager.default
        if fm.fileExists(atPath: storageURL.path) {
            if let decoded = decodeFile(at: storageURL) {
                items = decoded
                recoveryState = .clean
                return
            }
            preserveCorruptPrimary()
            if fm.fileExists(atPath: backupURL.path), let recovered = decodeFile(at: backupURL) {
                items = recovered
                recoveryState = .recoveredFromBackup
                return
            }
            items = []
            recoveryState = .corruptPrimaryAndNoBackup
            return
        }
        if fm.fileExists(atPath: backupURL.path), let recovered = decodeFile(at: backupURL) {
            items = recovered
            recoveryState = .recoveredFromBackup
        }
    }

    private func decodeFile(at url: URL) -> [DesktopWidgetItem]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([DesktopWidgetItem].self, from: data)
    }

    private func preserveCorruptPrimary() {
        let fm = FileManager.default
        try? fm.removeItem(at: corruptArchiveURL)
        try? fm.copyItem(at: storageURL, to: corruptArchiveURL)
    }

    private func writeToDisk() {
        let fm = FileManager.default
        do {
            let parent = storageURL.deletingLastPathComponent()
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)

            if fm.fileExists(atPath: storageURL.path), decodeFile(at: storageURL) != nil {
                try? fm.removeItem(at: backupURL)
                try? fm.copyItem(at: storageURL, to: backupURL)
            }
            try data.write(to: storageURL, options: .atomic)
            lastSaveError = nil
        } catch {
            lastSaveError = error.localizedDescription
        }
    }
}
