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

    /// Standard support-file locations for a bundle id / display name.
    static func dataPaths(bundleID: String, name: String, home: String = NSHomeDirectory()) -> [String] {
        [
            "\(home)/Library/Application Support/\(name)",
            "\(home)/Library/Caches/\(bundleID)",
            "\(home)/Library/Preferences/\(bundleID).plist",
            "\(home)/Library/Containers/\(bundleID)",
            "\(home)/Library/Saved Application State/\(bundleID).savedState",
            "\(home)/Library/WebKit/\(bundleID)",
            "\(home)/Library/HTTPStorages/\(bundleID)",
        ]
    }
}
