import Foundation

/// Phase 30a: a destructive app operation. Both move files to the Trash (undoable) — never a hard delete.
enum AppRemoval: String, CaseIterable, Sendable {
    /// The `.app` bundle itself.
    case uninstall
    /// The app's support files / caches / preferences / containers.
    case deleteData

    var needsQuitFirst: Bool { self == .uninstall }
    var symbol: String { self == .uninstall ? "trash" : "trash.slash" }
}

/// What an operation will move to the Trash, shown in the confirm sheet.
struct AppRemovalPlan: Equatable, Sendable {
    var bundleID: String
    var name: String
    var removal: AppRemoval
    var paths: [String]
}

/// Phase 30a: pure planner. The candidate layout follows macOS conventions; `exists` filters to what is
/// actually on disk (injected so the planner stays testable).
enum AppRemovalPlanner {
    static func plan(bundleID: String, name: String, appPath: String, removal: AppRemoval,
                     home: String = NSHomeDirectory(), exists: (String) -> Bool = { _ in true }) -> AppRemovalPlan {
        let paths: [String]
        switch removal {
        case .uninstall:
            paths = [appPath]
        case .deleteData:
            paths = dataPaths(bundleID: bundleID, name: name, home: home).filter(exists)
        }
        return AppRemovalPlan(bundleID: bundleID, name: name, removal: removal, paths: paths)
    }

    /// Standard support-file locations for a bundle id / display name, augmented with AppLeftoverScanPlan.
    static func dataPaths(bundleID: String, name: String, home: String = NSHomeDirectory()) -> [String] {
        let leftovers = AppLeftoverScanPlan.expectedCandidatePaths(home: home, bundleID: bundleID, appName: name)
        let standard = [
            "\(home)/Library/Application Support/\(name)",
            "\(home)/Library/Caches/\(bundleID)",
            "\(home)/Library/Preferences/\(bundleID).plist",
            "\(home)/Library/Containers/\(bundleID)",
            "\(home)/Library/Saved Application State/\(bundleID).savedState",
            "\(home)/Library/WebKit/\(bundleID)",
            "\(home)/Library/HTTPStorages/\(bundleID)",
        ]
        var combined: [String] = []
        var seen = Set<String>()
        for p in standard + leftovers {
            if seen.insert(p).inserted { combined.append(p) }
        }
        return combined
    }
}

// MARK: - MB-11: Uninstaller catalogue

/// One app the opt-in Uninstaller may offer. Built from the launcher's own scan, so the sheet never
/// grows a second app index; `id` falls back to the path for the rare bundle-less helper app.
struct UninstallerEntry: Identifiable, Equatable, Sendable {
    var bundleID: String
    var name: String
    var path: String
    var installedAt: Date

    var id: String { bundleID.isEmpty ? path : bundleID }
}

enum UninstallerCatalog {
    /// `/System` bundles are never offered: their removal is not KatiKati's call, and moving them to
    /// the Trash would need SIP off anyway. One entry per bundle id; the shortest path wins, matching
    /// `LauncherAppIndex.merged` so the sheet and the launcher name the same copy.
    static func entries(from apps: [LauncherApp]) -> [UninstallerEntry] {
        var best: [String: UninstallerEntry] = [:]
        for app in apps where !app.path.isEmpty && !isSystemPath(app.path) {
            let key = app.bundleID.isEmpty ? app.path : app.bundleID
            let entry = UninstallerEntry(bundleID: app.bundleID, name: app.name,
                                         path: app.path, installedAt: app.installedAt)
            guard let current = best[key] else { best[key] = entry; continue }
            if entry.path.count < current.path.count
                || (entry.path.count == current.path.count && entry.installedAt > current.installedAt) {
                best[key] = entry
            }
        }
        return best.values.sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
        }
    }

    static func filter(_ entries: [UninstallerEntry], query: String) -> [UninstallerEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.bundleID.localizedCaseInsensitiveContains(trimmed)
        }
    }

    static func isSystemPath(_ path: String) -> Bool {
        path.hasPrefix("/System/")
    }
}
