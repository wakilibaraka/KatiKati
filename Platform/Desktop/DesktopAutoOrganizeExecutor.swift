import Foundation

/// Scans, applies, and persists undo records for Preview-First Desktop Auto-Organize plans.
enum DesktopAutoOrganizeExecutor {
    nonisolated static var defaultDestinationRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("KatiKati", isDirectory: true)
            .appendingPathComponent("Organized", isDirectory: true)
    }

    nonisolated static var defaultUndoRecordURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support
            .appendingPathComponent("KatiKati", isDirectory: true)
            .appendingPathComponent("last-organize-undo.json", isDirectory: false)
    }

    nonisolated static func scanAndPlan(options: DesktopOrganizeOptions) throws -> DesktopOrganizePlan {
        let entries = try FolderContentsLoader.load(directory: options.sourceDirectory)
        return DesktopAutoOrganizeEngine.buildPlan(entries: entries, options: options)
    }

    @discardableResult
    nonisolated static func apply(
        _ plan: DesktopOrganizePlan,
        undoRecordURL: URL = defaultUndoRecordURL
    ) throws -> DesktopOrganizeUndoRecord {
        let fm = FileManager.default
        var createdDirs: [String] = []
        var moves: [DesktopOrganizeUndoEntry] = []

        func makeAndPersistRecord() -> DesktopOrganizeUndoRecord {
            let record = DesktopOrganizeUndoRecord(
                id: UUID(),
                createdAt: Date(),
                sourceDirectoryPath: plan.sourceDirectory.path,
                createdDirectoryPaths: createdDirs,
                moves: moves
            )
            guard !moves.isEmpty else { return record }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(record) {
                try? fm.createDirectory(at: undoRecordURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: undoRecordURL, options: .atomic)
            }
            return record
        }

        do {
            if !plan.buckets.isEmpty && !fm.fileExists(atPath: plan.destinationRoot.path) {
                try fm.createDirectory(at: plan.destinationRoot, withIntermediateDirectories: true)
                createdDirs.append(plan.destinationRoot.path)
            }

            for bucket in plan.buckets where !bucket.items.isEmpty {
                if !fm.fileExists(atPath: bucket.targetDirectory.path) {
                    try fm.createDirectory(at: bucket.targetDirectory, withIntermediateDirectories: true)
                    createdDirs.append(bucket.targetDirectory.path)
                }
                for item in bucket.items {
                    guard fm.fileExists(atPath: item.sourceURL.path) else { continue }
                    let targetURL = DesktopFileOperations.uniqueURL(
                        in: bucket.targetDirectory,
                        preferredName: item.filename,
                        fileManager: fm
                    )
                    try fm.moveItem(at: item.sourceURL, to: targetURL)
                    moves.append(DesktopOrganizeUndoEntry(
                        originalPath: item.sourceURL.path,
                        movedPath: targetURL.path
                    ))
                }
            }
        } catch {
            _ = makeAndPersistRecord()
            throw error
        }

        return makeAndPersistRecord()
    }

    nonisolated static func loadLastUndoRecord(from url: URL = defaultUndoRecordURL) -> DesktopOrganizeUndoRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(DesktopOrganizeUndoRecord.self, from: data)
    }

    @discardableResult
    nonisolated static func undo(
        _ record: DesktopOrganizeUndoRecord,
        undoRecordURL: URL = defaultUndoRecordURL
    ) -> (restoredCount: Int, failedPaths: [String]) {
        let fm = FileManager.default
        var restored = 0
        var failed: [String] = []

        for entry in record.moves.reversed() {
            let movedURL = URL(fileURLWithPath: entry.movedPath)
            guard fm.fileExists(atPath: movedURL.path) else {
                failed.append(entry.movedPath)
                continue
            }
            let originalURL = URL(fileURLWithPath: entry.originalPath)
            let parent = originalURL.deletingLastPathComponent()
            let target = fm.fileExists(atPath: originalURL.path)
                ? DesktopFileOperations.uniqueURL(in: parent, preferredName: originalURL.lastPathComponent, fileManager: fm)
                : originalURL
            do {
                try fm.createDirectory(at: parent, withIntermediateDirectories: true)
                try fm.moveItem(at: movedURL, to: target)
                restored += 1
            } catch {
                failed.append(entry.movedPath)
            }
        }

        for dirPath in record.createdDirectoryPaths.reversed() {
            let contents = (try? fm.contentsOfDirectory(atPath: dirPath)) ?? []
            if contents.isEmpty { try? fm.removeItem(atPath: dirPath) }
        }
        if failed.isEmpty {
            try? fm.removeItem(atPath: undoRecordURL.path)
        }
        return (restored, failed)
    }
}
