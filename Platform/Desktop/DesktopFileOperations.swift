import AppKit
import Foundation

enum DesktopDropTransferMode: Equatable, Sendable {
    case copy
    case move

    static func resolve(
        sourceVolume: String?,
        destinationVolume: String?,
        forceCopy: Bool,
        forceMove: Bool
    ) -> DesktopDropTransferMode {
        if forceCopy { return .copy }
        if forceMove { return .move }
        if let src = sourceVolume, let dst = destinationVolume, src == dst { return .move }
        return .copy
    }
}

enum DesktopTrashResult: Equatable, Sendable {
    case trashed([URL])
    case requiresPermanentDeleteConfirmation([URL])
    case failed([URL])
}

struct DesktopFileMenuCallbacks {
    var onQuickLook: ([URL]) -> Void
    var onRename: (URL) -> Void
    var onNewFolder: () -> Void
    var onCut: ([URL]) -> Void
    var onPaste: () -> Void
    var onTrash: ([URL]) -> Void
    var onCompress: ([URL]) -> Void
    var onExtract: (URL) -> Void
}

private final class DesktopMenuItem: NSMenuItem {
    private let actionBlock: () -> Void

    init(title: String, systemSymbol: String? = nil, actionBlock: @escaping () -> Void) {
        self.actionBlock = actionBlock
        super.init(title: title, action: #selector(invokeBlock), keyEquivalent: "")
        self.target = self
        if let systemSymbol {
            self.image = NSImage(systemSymbolName: systemSymbol, accessibilityDescription: nil)
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func invokeBlock() { actionBlock() }
}

/// Native Finder-compatible file operations, drag transfer rules, ZIP ditto helpers, and `NSMenu` builder.
enum DesktopFileOperations {
    private static let archiveQueue = DispatchQueue(label: "com.katikati.desktop-archive", qos: .utility)

    nonisolated static func uniqueURL(
        in directory: URL,
        preferredName: String,
        fileManager: FileManager = .default
    ) -> URL {
        let initial = directory.appendingPathComponent(preferredName)
        guard fileManager.fileExists(atPath: initial.path) else { return initial }
        let ext = (preferredName as NSString).pathExtension
        let stem = ext.isEmpty ? preferredName : (preferredName as NSString).deletingPathExtension
        var index = 2
        while true {
            let candidateName = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }

    nonisolated static func volumeIdentifier(for url: URL) -> String? {
        try? url.resourceValues(forKeys: [.volumeURLKey]).volume?
            .standardizedFileURL.resolvingSymlinksInPath().path
    }

    nonisolated static func importFiles(
        _ urls: [URL],
        into destination: URL,
        forceCopy: Bool = false,
        forceMove: Bool = false
    ) throws -> [URL] {
        let fm = FileManager.default
        let dstVol = volumeIdentifier(for: destination)
        let stdDest = destination.standardizedFileURL.resolvingSymlinksInPath().path
        var imported: [URL] = []

        for source in urls {
            let srcParent = source.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path
            let mode = DesktopDropTransferMode.resolve(
                sourceVolume: volumeIdentifier(for: source),
                destinationVolume: dstVol,
                forceCopy: forceCopy,
                forceMove: forceMove
            )
            if mode == .move && srcParent == stdDest {
                imported.append(source)
                continue
            }
            let target = uniqueURL(in: destination, preferredName: source.lastPathComponent, fileManager: fm)
            switch mode {
            case .copy: try fm.copyItem(at: source, to: target)
            case .move: try fm.moveItem(at: source, to: target)
            }
            imported.append(target)
        }
        return imported
    }

    nonisolated static func createNewFolder(
        in directory: URL,
        baseName: String = String(localized: "Untitled Folder")
    ) throws -> URL {
        let target = uniqueURL(in: directory, preferredName: baseName)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        return target
    }

    nonisolated static func renameItem(at url: URL, to rawName: String) throws -> URL {
        let sanitized = rawName.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard !sanitized.isEmpty else { throw CocoaError(.fileWriteInvalidFileName) }
        let target = url.deletingLastPathComponent().appendingPathComponent(sanitized)
        if target.standardizedFileURL == url.standardizedFileURL { return url }
        guard !FileManager.default.fileExists(atPath: target.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }

    nonisolated static func moveToTrash(_ urls: [URL]) -> DesktopTrashResult {
        var trashed: [URL] = []
        var needsPermanent: [URL] = []
        var failed: [URL] = []
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                trashed.append(url)
            } catch let error as NSError {
                let unsupported = error.domain == NSCocoaErrorDomain && error.code == CocoaError.featureUnsupported.rawValue
                let posixUnsupported = error.domain == NSPOSIXErrorDomain && error.code == Int(ENOTSUP)
                if unsupported || posixUnsupported {
                    needsPermanent.append(url)
                } else {
                    failed.append(url)
                }
            }
        }
        if !needsPermanent.isEmpty { return .requiresPermanentDeleteConfirmation(needsPermanent) }
        if !failed.isEmpty { return .failed(failed) }
        return .trashed(trashed)
    }

    nonisolated static func permanentlyDelete(_ urls: [URL]) throws {
        for url in urls { try FileManager.default.removeItem(at: url) }
    }

    nonisolated static func compressToZip(
        _ urls: [URL],
        in directory: URL,
        completion: @escaping @Sendable (Result<URL, Error>) -> Void
    ) {
        guard let first = urls.first else { return }
        let stem = urls.count == 1 ? first.deletingPathExtension().lastPathComponent : directory.lastPathComponent
        let archiveURL = uniqueURL(in: directory, preferredName: "\(stem).zip")
        archiveQueue.async {
            let result: Result<URL, Error> = Result {
                for url in urls {
                    let proc = Process()
                    proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                    proc.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", url.path, archiveURL.path]
                    try proc.run()
                    proc.waitUntilExit()
                    if proc.terminationStatus != 0 { throw CocoaError(.fileWriteUnknown) }
                }
                return archiveURL
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    nonisolated static func extractZip(
        _ archiveURL: URL,
        to directory: URL,
        completion: @escaping @Sendable (Result<URL, Error>) -> Void
    ) {
        let folderName = archiveURL.deletingPathExtension().lastPathComponent
        let destURL = uniqueURL(in: directory, preferredName: folderName)
        archiveQueue.async {
            let result: Result<URL, Error> = Result {
                try FileManager.default.createDirectory(at: destURL, withIntermediateDirectories: true)
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                proc.arguments = ["-x", "-k", archiveURL.path, destURL.path]
                try proc.run()
                proc.waitUntilExit()
                if proc.terminationStatus != 0 { throw CocoaError(.fileReadCorruptFile) }
                return destURL
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    @MainActor static func open(_ urls: [URL]) {
        for url in urls { NSWorkspace.shared.open(url) }
    }

    @MainActor static func open(_ urls: [URL], withApplication appURL: URL) {
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    @MainActor static func copyToPasteboard(_ urls: [URL]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
    }

    @MainActor static func readPasteboardURLs() -> [URL] {
        NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] ?? []
    }

    @MainActor static func buildContextMenu(
        for urls: [URL],
        in directory: URL,
        hasCutItems: Bool,
        callbacks: DesktopFileMenuCallbacks
    ) -> NSMenu {
        let menu = NSMenu()
        let canPaste = hasCutItems || !readPasteboardURLs().isEmpty

        if urls.isEmpty {
            menu.addItem(DesktopMenuItem(title: String(localized: "New Folder"), systemSymbol: "folder.badge.plus", actionBlock: callbacks.onNewFolder))
            if canPaste {
                menu.addItem(DesktopMenuItem(title: String(localized: "Paste"), systemSymbol: "doc.on.clipboard", actionBlock: callbacks.onPaste))
            }
            menu.addItem(.separator())
            menu.addItem(DesktopMenuItem(title: String(localized: "Show in Finder"), systemSymbol: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([directory])
            })
            return menu
        }

        menu.addItem(DesktopMenuItem(title: String(localized: "Open"), systemSymbol: "arrow.up.forward.app") { open(urls) })
        if let primary = urls.first { menu.addItem(openWithItem(for: primary, allURLs: urls)) }
        menu.addItem(DesktopMenuItem(title: String(localized: "Quick Look"), systemSymbol: "eye") { callbacks.onQuickLook(urls) })
        menu.addItem(DesktopMenuItem(title: String(localized: "Show in Finder"), systemSymbol: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        })
        menu.addItem(.separator())

        if urls.count == 1, let single = urls.first {
            menu.addItem(DesktopMenuItem(title: String(localized: "Rename"), systemSymbol: "pencil") { callbacks.onRename(single) })
        }
        menu.addItem(DesktopMenuItem(title: String(localized: "Copy"), systemSymbol: "doc.on.doc") { copyToPasteboard(urls) })
        menu.addItem(DesktopMenuItem(title: String(localized: "Cut"), systemSymbol: "scissors") { callbacks.onCut(urls) })
        if canPaste {
            menu.addItem(DesktopMenuItem(title: String(localized: "Paste"), systemSymbol: "doc.on.clipboard", actionBlock: callbacks.onPaste))
        }
        menu.addItem(DesktopMenuItem(title: String(localized: "Copy Path"), systemSymbol: "link") {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
        })
        menu.addItem(DesktopMenuItem(title: String(localized: "New Folder"), systemSymbol: "folder.badge.plus", actionBlock: callbacks.onNewFolder))
        menu.addItem(.separator())

        if urls.count == 1, let single = urls.first, single.pathExtension.lowercased() == "zip" {
            menu.addItem(DesktopMenuItem(title: String(localized: "Extract"), systemSymbol: "archivebox.fill") { callbacks.onExtract(single) })
        } else {
            menu.addItem(DesktopMenuItem(title: String(localized: "Compress"), systemSymbol: "archivebox") { callbacks.onCompress(urls) })
        }
        menu.addItem(.separator())
        menu.addItem(DesktopMenuItem(title: String(localized: "Move to Trash"), systemSymbol: "trash") { callbacks.onTrash(urls) })
        return menu
    }

    @MainActor private static func openWithItem(for url: URL, allURLs: [URL]) -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: "Open With"), action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "square.and.arrow.up.on.square", accessibilityDescription: nil)
        let submenu = NSMenu()
        let defaultPath = NSWorkspace.shared.urlForApplication(toOpen: url)?.standardizedFileURL.path
        var seen = Set<String>()
        let apps = NSWorkspace.shared.urlsForApplications(toOpen: url)
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
            .sorted { a, b in
                if a.standardizedFileURL.path == defaultPath { return true }
                if b.standardizedFileURL.path == defaultPath { return false }
                let na = FileManager.default.displayName(atPath: a.path)
                let nb = FileManager.default.displayName(atPath: b.path)
                return na.localizedStandardCompare(nb) == .orderedAscending
            }

        if apps.isEmpty {
            let none = NSMenuItem(title: String(localized: "No Apps Available"), action: nil, keyEquivalent: "")
            none.isEnabled = false
            submenu.addItem(none)
        } else {
            for appURL in apps {
                let name = FileManager.default.displayName(atPath: appURL.path)
                let title = appURL.standardizedFileURL.path == defaultPath
                    ? String(format: String(localized: "%@ (default)"), name)
                    : name
                let row = DesktopMenuItem(title: title) { open(allURLs, withApplication: appURL) }
                let icon = NSWorkspace.shared.icon(forFile: appURL.path).copy() as? NSImage
                icon?.size = NSSize(width: 16, height: 16)
                row.image = icon
                submenu.addItem(row)
            }
        }
        item.submenu = submenu
        return item
    }
}
