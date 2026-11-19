import AppKit
import Foundation

/// Batch and single-row actions for unified desktop search, routed through the existing app surfaces.
@MainActor
enum DesktopSearchActions {
    static func open(_ result: DesktopSearchResult) {
        switch result.provider {
        case .app:
            guard let path = result.path else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            if let bundleID = result.payload, !bundleID.isEmpty,
               let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                running.activate(options: [.activateAllWindows])
                return
            }
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration)
        case .setting:
            guard let raw = result.payload, let tab = SettingsTab(rawValue: raw) else { return }
            NSApp.activate(ignoringOtherApps: true)
            AppDelegate.shared?.openSettings(selecting: tab)
        case .file:
            guard let path = result.path else { return }
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        case .note, .todo:
            break
        }
    }

    static func open(_ results: [DesktopSearchResult]) {
        for result in results { open(result) }
    }

    static func reveal(_ results: [DesktopSearchResult]) {
        let urls = results.compactMap(\.path).map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    @discardableResult
    static func copy(_ results: [DesktopSearchResult]) -> Bool {
        guard let text = DesktopSearchBatchAction.clipboardText(for: results) else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return true
    }

    /// Copies the selected files into the chosen Desktop folder box (same-volume moves stay moves).
    @discardableResult
    static func move(_ results: [DesktopSearchResult], toBox item: DesktopWidgetItem) -> String? {
        guard let folder = item.backingPath else { return nil }
        let urls = DesktopSearchBatchAction.filePaths(in: results).map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { return nil }
        do {
            _ = try DesktopFileOperations.importFiles(
                urls,
                into: URL(fileURLWithPath: folder, isDirectory: true),
                forceMove: true
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Trash is the one destructive batch action, and it asks first.
    @discardableResult
    static func confirmAndTrash(_ results: [DesktopSearchResult]) -> Int {
        let urls = DesktopSearchBatchAction.filePaths(in: results).map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { return 0 }
        let alert = NSAlert()
        alert.messageText = String(localized: "Move to Trash?")
        alert.informativeText = urls.count == 1
            ? urls[0].lastPathComponent
            : String(format: String(localized: "%lld items will be moved to the Trash."), urls.count)
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Move to Trash"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return 0 }
        var trashed = 0
        for url in urls {
            if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil { trashed += 1 }
        }
        return trashed
    }
}
