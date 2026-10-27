import AppKit

/// Port plan #4b (2026-10-27): stores named bar profiles (`profiles.json` in Application Support/KatiKati)
/// and applies one by editing the kept-app and pinned-folder stores, the widget preset and the layout
/// mode. The rule of what changes lives in `BarProfilePlan`; this type only reads the stores, asks the
/// plan, and performs the edits. It never opens, quits or moves a window.
///
/// Lazy by construction: nothing is read from disk or observed until a profile is listed, saved or
/// applied, so a person who never uses profiles pays nothing.
///
/// The kept apps' on-screen order is owned by `StripOrderStore` and follows the open windows, so a profile
/// restores *which* apps are kept; it does not rewrite the strip's live order.
@MainActor
final class BarProfileService {
    private let kept: KeptAppStore
    private let folders: PinnedFolderStore
    private let settings: AppSettingsStore
    private let fileURL: URL
    private var cached: [BarProfile]?

    init(kept: KeptAppStore, folders: PinnedFolderStore, settings: AppSettingsStore,
         fileURL: URL = BarProfileService.defaultURL) {
        self.kept = kept
        self.folders = folders
        self.settings = settings
        self.fileURL = fileURL
    }

    nonisolated static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KatiKati", isDirectory: true)
            .appendingPathComponent("profiles.json")
    }

    // MARK: - Storage

    var profiles: [BarProfile] {
        if let cached { return cached }
        let loaded = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode([BarProfile].self, from: $0) } ?? []
        cached = loaded
        return loaded
    }

    func summaries() -> [BarProfileSummary] {
        profiles.map { BarProfileSummary(id: $0.id, name: $0.name, appCount: $0.keptApps.count) }
    }

    private func save(_ list: [BarProfile]) {
        cached = list
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(list).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("BarProfileService: could not save profiles: \(error.localizedDescription)")
        }
    }

    // MARK: - Save and delete

    /// Stores the bar as it is now under `name`. A profile with the same name (ignoring case) is replaced,
    /// so "save as Work" twice updates Work instead of piling up copies.
    @discardableResult
    func saveCurrent(named rawName: String) -> BarProfile? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        var list = profiles
        let existing = list.firstIndex { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        let profile = BarProfilePlan.snapshot(of: currentState(), name: name, id: existing.map { list[$0].id } ?? UUID().uuidString)
        if let existing { list[existing] = profile } else { list.append(profile) }
        save(list)
        return profile
    }

    func delete(id: String) {
        save(profiles.filter { $0.id != id })
    }

    // MARK: - Apply

    func profile(id: String) -> BarProfile? { profiles.first { $0.id == id } }

    @discardableResult
    func apply(id: String) -> BarProfilePlan.Edits? {
        guard let found = profile(id: id) else { return nil }
        return apply(found)
    }

    @discardableResult
    func apply(_ profile: BarProfile) -> BarProfilePlan.Edits {
        let edits = BarProfilePlan.edits(
            from: currentState(), to: profile,
            isInstalled: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil },
            folderExists: { var isDir: ObjCBool = false; return FileManager.default.fileExists(atPath: $0, isDirectory: &isDir) && isDir.boolValue })
        guard !edits.isNoOp else { return edits }

        for id in edits.keptToRemove { kept.remove(id) }
        for id in edits.keptToAdd { kept.add(id) }

        for path in edits.foldersToUnpin { folders.remove(path) }
        for path in edits.foldersToPin { folders.add(path) }
        var previous: String?
        for path in edits.finalFolderOrder {
            if let previous { folders.reorder(draggedPath: path, relativeTo: previous, after: true) }
            previous = path
        }

        if let presetID = edits.widgetPresetID,
           let preset = (WidgetPresets.builtIns + settings.userWidgetPresets).first(where: { $0.id == presetID }) {
            settings.applyWidgetPreset(preset)
        }
        if let mode = edits.layoutMode { settings.setBarLayoutMode(mode) }
        if !edits.skippedApps.isEmpty || !edits.skippedFolders.isEmpty {
            NSLog("BarProfileService: profile \(profile.name) skipped \(edits.skippedApps.count) apps and \(edits.skippedFolders.count) folders that are gone")
        }
        return edits
    }

    private func currentState() -> BarProfileState {
        BarProfileState(keptApps: kept.bundleIDs, pinnedFolders: folders.folderPaths,
                        widgetPresetID: nil, layoutMode: settings.barLayoutMode.rawValue)
    }
}
