import Foundation

/// The iCloud-Drive notes folder (Phase 7A-6c): a plain path
/// (`~/Library/Mobile Documents/com~apple~CloudDocs/KatiKati Notes`), no ubiquity container and
/// no CloudKit entitlement (the app is not sandboxed). Reads and writes go through
/// `NSFileCoordinator` so iCloud's daemon never sees half-written files. Evicted files appear as
/// `.Name.md.icloud` placeholders: they are reported as *unresolved* (never as deleted) and a
/// download is requested for the next pass.
struct NotesSyncFolder {
    struct File: Equatable {
        var name: String
        var fileModified: Date
        var text: String
    }

    struct Scan: Equatable {
        var files: [File] = []
        /// Names present in the folder whose contents were not readable this pass.
        var unresolved: Set<String> = []
    }

    let url: URL
    private let fileManager: FileManager

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    static func defaultICloudURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/KatiKati Notes", isDirectory: true)
    }

    var exists: Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    func createIfNeeded() throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// `.Shopping.md.icloud` → `Shopping.md`; nil for anything that is not an evicted placeholder.
    static func placeholderTarget(_ rawName: String) -> String? {
        guard rawName.hasPrefix("."), rawName.hasSuffix(".icloud") else { return nil }
        let inner = String(rawName.dropFirst().dropLast(".icloud".count))
        return inner.isEmpty ? nil : inner
    }

    func scan() -> Scan {
        var scan = Scan()
        guard let names = try? fileManager.contentsOfDirectory(atPath: url.path) else { return scan }
        for raw in names.sorted() {
            if let target = Self.placeholderTarget(raw) {
                guard (target as NSString).pathExtension == NoteFileName.fileExtension else { continue }
                scan.unresolved.insert(target)
                try? fileManager.startDownloadingUbiquitousItem(at: url.appendingPathComponent(raw))
                continue
            }
            guard (raw as NSString).pathExtension == NoteFileName.fileExtension, !raw.hasPrefix(".") else { continue }
            let file = url.appendingPathComponent(raw)
            if let text = coordinatedRead(file) {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                scan.files.append(File(name: raw, fileModified: Note.wholeSeconds(modified), text: text))
            } else {
                scan.unresolved.insert(raw)
            }
        }
        return scan
    }

    /// Writes atomically and returns the file's new modification date.
    @discardableResult
    func write(name: String, text: String) throws -> Date {
        let file = url.appendingPathComponent(name)
        var failure: Error?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &coordinationError) { target in
            do { try text.write(to: target, atomically: true, encoding: .utf8) } catch { failure = error }
        }
        if let error = failure ?? coordinationError { throw error }
        return modificationDate(of: name)
    }

    func remove(name: String) throws {
        let file = url.appendingPathComponent(name)
        var failure: Error?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forDeleting, error: &coordinationError) { target in
            do { try fileManager.removeItem(at: target) } catch { failure = error }
        }
        if let error = failure ?? coordinationError { throw error }
    }

    func modificationDate(of name: String) -> Date {
        let file = url.appendingPathComponent(name)
        let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        return Note.wholeSeconds(date)
    }

    private func coordinatedRead(_ file: URL) -> String? {
        var result: String?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &coordinationError) { target in
            result = try? String(contentsOf: target, encoding: .utf8)
        }
        return coordinationError == nil ? result : nil
    }
}
