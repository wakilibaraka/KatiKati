import AppKit

/// Phase 30b: performs an app removal. The app is quit first (uninstall), then every planned path is
/// moved to the Trash (undoable). Nothing is ever hard-deleted.
@MainActor
enum AppRemovalService {
    static func plan(bundleID: String, name: String, appPath: String, removal: AppRemoval) -> AppRemovalPlan {
        AppRemovalPlanner.plan(bundleID: bundleID, name: name, appPath: appPath, removal: removal,
                               exists: { FileManager.default.fileExists(atPath: $0) })
    }

    @discardableResult
    static func perform(_ plan: AppRemovalPlan) -> Int {
        if plan.removal.needsQuitFirst {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: plan.bundleID) {
                app.terminate()
            }
        }
        var moved = 0
        for path in plan.paths {
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                moved += 1
            } catch {
                NSSound.beep()   // permission / read-only volume: silently refuse, like Finder
            }
        }
        if moved > 0 { TrashStateStore.shared.noteTrashedInApp() }
        return moved
    }

    /// Confirm (listing what will go) then perform. Shared by the launcher and the command bar.
    static func confirmAndPerform(bundleID: String, name: String, appPath: String, removal: AppRemoval) {
        let plan = plan(bundleID: bundleID, name: name, appPath: appPath, removal: removal)
        guard !plan.paths.isEmpty else { NSSound.beep(); return }
        let alert = NSAlert()
        alert.messageText = String(localized: removal == .uninstall ? "Uninstall" : "Delete Data")
        alert.informativeText = plan.paths.joined(separator: "\n")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Move to Trash"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        if alert.runModal() == .alertFirstButtonReturn { perform(plan) }
    }
}
