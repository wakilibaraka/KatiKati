import Foundation

/// Port plan #4a (2026-10-27): a named snapshot of the bar (Work, Personal, Gaming), the model half of
/// Dockset-style profiles. Pure: `BarProfilePlan` turns "what the bar is now" plus "the profile to apply"
/// into the exact store edits, so the rule that matters most is testable without any store or window:
/// **switching a profile never opens, quits or moves a window.** It only changes which apps keep a slot
/// on the bar, in which order, plus pinned folders, the widget preset and the layout mode. A running app
/// that is not in the profile keeps its window cards; it only loses its kept slot (so it leaves the bar
/// when it quits, exactly as an un-kept app does today).
struct BarProfile: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    /// Kept apps in bar order (bundle ids).
    var keptApps: [String]
    /// Pinned folder paths in display order.
    var pinnedFolders: [String]
    /// `WidgetPreset.id`, or nil to leave the widget arrangement alone.
    var widgetPresetID: String?
    /// `BarLayoutMode.rawValue`, or nil to leave the layout alone. A raw value this build does not know
    /// (a profile made by a newer build) is ignored, not an error.
    var layoutMode: String?

    init(id: String = UUID().uuidString, name: String, keptApps: [String] = [], pinnedFolders: [String] = [],
         widgetPresetID: String? = nil, layoutMode: String? = nil) {
        self.id = id
        self.name = name
        self.keptApps = keptApps
        self.pinnedFolders = pinnedFolders
        self.widgetPresetID = widgetPresetID
        self.layoutMode = layoutMode
    }

    // Lenient decode: a profile file written by an older or newer build still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        keptApps = try c.decodeIfPresent([String].self, forKey: .keptApps) ?? []
        pinnedFolders = try c.decodeIfPresent([String].self, forKey: .pinnedFolders) ?? []
        widgetPresetID = try c.decodeIfPresent(String.self, forKey: .widgetPresetID)
        layoutMode = try c.decodeIfPresent(String.self, forKey: .layoutMode)
    }
}

/// What the command bar shows for a stored profile.
struct BarProfileSummary: Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var appCount: Int
}

/// What the bar holds right now, in the same shape as a profile.
struct BarProfileState: Equatable, Sendable {
    var keptApps: [String]
    var pinnedFolders: [String]
    var widgetPresetID: String?
    var layoutMode: String?
}

enum BarProfilePlan {
    /// The edits that turn the current bar into the profile.
    struct Edits: Equatable, Sendable {
        /// Kept apps to un-keep (currently kept, not in the profile).
        var keptToRemove: [String] = []
        /// Apps to keep that are not kept yet, in the profile's order.
        var keptToAdd: [String] = []
        /// The kept order once the edits are done: the profile's apps that are installed, in its order.
        var finalKeptOrder: [String] = []
        var foldersToUnpin: [String] = []
        var foldersToPin: [String] = []
        var finalFolderOrder: [String] = []
        /// Nil leaves the current widget preset in place.
        var widgetPresetID: String?
        /// Nil leaves the current layout in place.
        var layoutMode: BarLayoutMode?
        /// Profile apps that are no longer installed and folders that no longer exist: reported, not applied.
        var skippedApps: [String] = []
        var skippedFolders: [String] = []
        /// True when the kept apps or folders are the same set in a different order.
        var reordersKept = false
        var reordersFolders = false

        /// Applying a profile twice is a no-op the second time.
        var isNoOp: Bool {
            keptToRemove.isEmpty && keptToAdd.isEmpty && foldersToUnpin.isEmpty && foldersToPin.isEmpty
                && !reordersKept && !reordersFolders && widgetPresetID == nil && layoutMode == nil
        }
    }

    static func edits(from current: BarProfileState, to profile: BarProfile,
                      isInstalled: (String) -> Bool, folderExists: (String) -> Bool) -> Edits {
        var out = Edits()

        let wantedApps = unique(profile.keptApps)
        out.skippedApps = wantedApps.filter { !isInstalled($0) }
        out.finalKeptOrder = wantedApps.filter(isInstalled)
        let keptNow = Set(current.keptApps)
        let keptAfter = Set(out.finalKeptOrder)
        out.keptToRemove = current.keptApps.filter { !keptAfter.contains($0) }
        out.keptToAdd = out.finalKeptOrder.filter { !keptNow.contains($0) }
        out.reordersKept = out.keptToRemove.isEmpty && out.keptToAdd.isEmpty
            && out.finalKeptOrder != unique(current.keptApps)

        let wantedFolders = unique(profile.pinnedFolders)
        out.skippedFolders = wantedFolders.filter { !folderExists($0) }
        out.finalFolderOrder = wantedFolders.filter(folderExists)
        let foldersNow = Set(current.pinnedFolders)
        let foldersAfter = Set(out.finalFolderOrder)
        out.foldersToUnpin = current.pinnedFolders.filter { !foldersAfter.contains($0) }
        out.foldersToPin = out.finalFolderOrder.filter { !foldersNow.contains($0) }
        out.reordersFolders = out.foldersToUnpin.isEmpty && out.foldersToPin.isEmpty
            && out.finalFolderOrder != unique(current.pinnedFolders)

        if let preset = profile.widgetPresetID, preset != current.widgetPresetID { out.widgetPresetID = preset }
        if let raw = profile.layoutMode, raw != current.layoutMode, let mode = BarLayoutMode(rawValue: raw) {
            out.layoutMode = mode
        }
        return out
    }

    /// First occurrence wins, order kept.
    private static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// The profile a "Save current bar as…" would store.
    static func snapshot(of state: BarProfileState, name: String, id: String = UUID().uuidString) -> BarProfile {
        BarProfile(id: id, name: name, keptApps: unique(state.keptApps), pinnedFolders: unique(state.pinnedFolders),
                   widgetPresetID: state.widgetPresetID, layoutMode: state.layoutMode)
    }
}
