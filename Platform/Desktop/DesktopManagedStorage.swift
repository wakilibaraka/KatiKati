import Foundation

enum DesktopMigrationError: Error, Equatable {
    case sourceMissingOrNotDirectory
    case invalidTargetOverlap
    case copyFailed(String)
    case verificationFailed(expectedFiles: Int, actualFiles: Int, expectedBytes: Int64, actualBytes: Int64)
}

struct DesktopMigrationReport: Equatable, Sendable {
    let destinationURL: URL
    let verifiedFileCount: Int
    let verifiedTotalBytes: Int64
    let sourcePreserved: Bool
}

/// Copy-first, manifest-and-byte-verified migration and export for optional KatiKati Managed Storage.
enum DesktopManagedStorage {
    nonisolated static var defaultRootURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support
            .appendingPathComponent("KatiKati", isDirectory: true)
            .appendingPathComponent("ManagedBoxes", isDirectory: true)
    }

    nonisolated static func createManagedBoxDirectory(
        for boxID: UUID = UUID(),
        rootURL: URL = defaultRootURL
    ) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let target = DesktopFileOperations.uniqueURL(in: rootURL, preferredName: boxID.uuidString, fileManager: fm)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }

    nonisolated static func migrateToManagedStorage(
        from sourceURL: URL,
        boxID: UUID,
        rootURL: URL = defaultRootURL,
        moveSourceToTrashAfterVerify: Bool = false
    ) throws -> DesktopMigrationReport {
        try copyVerifiedTree(
            from: sourceURL,
            intoParent: rootURL,
            preferredName: boxID.uuidString,
            stagingPrefix: "\(boxID.uuidString).staging",
            moveSourceToTrashAfterVerify: moveSourceToTrashAfterVerify
        )
    }

    nonisolated static func exportManagedBox(
        from managedURL: URL,
        to destinationDirectory: URL
    ) throws -> DesktopMigrationReport {
        try copyVerifiedTree(
            from: managedURL,
            intoParent: destinationDirectory,
            preferredName: managedURL.lastPathComponent,
            stagingPrefix: ".katikati-export.staging",
            moveSourceToTrashAfterVerify: false
        )
    }

    nonisolated static func cleanupOrphanedStagingDirectories(in rootURL: URL = defaultRootURL) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil) else { return }
        for url in entries where url.lastPathComponent.contains(".staging-") {
            try? fm.removeItem(at: url)
        }
    }

    // MARK: - Shared Verified Copy Pipeline

    private nonisolated static func copyVerifiedTree(
        from sourceURL: URL,
        intoParent parentURL: URL,
        preferredName: String,
        stagingPrefix: String,
        moveSourceToTrashAfterVerify: Bool
    ) throws -> DesktopMigrationReport {
        let fm = FileManager.default
        let stdSource = sourceURL.standardizedFileURL.resolvingSymlinksInPath()
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: stdSource.path, isDirectory: &isDir), isDir.boolValue else {
            throw DesktopMigrationError.sourceMissingOrNotDirectory
        }

        try fm.createDirectory(at: parentURL, withIntermediateDirectories: true)
        let stdParent = parentURL.standardizedFileURL.resolvingSymlinksInPath()
        let finalURL = DesktopFileOperations.uniqueURL(in: stdParent, preferredName: preferredName, fileManager: fm)
        if pathsOverlap(stdSource.path, stdParent.path) || pathsOverlap(stdSource.path, finalURL.path) {
            throw DesktopMigrationError.invalidTargetOverlap
        }

        let stagingURL = stdParent.appendingPathComponent("\(stagingPrefix)-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.copyItem(at: stdSource, to: stagingURL)
        } catch {
            try? fm.removeItem(at: stagingURL)
            throw DesktopMigrationError.copyFailed(error.localizedDescription)
        }

        let expected = collectManifest(under: stdSource)
        let actual = collectManifest(under: stagingURL)
        guard expected.entries == actual.entries else {
            try? fm.removeItem(at: stagingURL)
            throw DesktopMigrationError.verificationFailed(
                expectedFiles: expected.fileCount,
                actualFiles: actual.fileCount,
                expectedBytes: expected.totalBytes,
                actualBytes: actual.totalBytes
            )
        }

        do {
            try fm.moveItem(at: stagingURL, to: finalURL)
        } catch {
            try? fm.removeItem(at: stagingURL)
            throw DesktopMigrationError.copyFailed(error.localizedDescription)
        }

        var trashed = false
        if moveSourceToTrashAfterVerify {
            trashed = (try? fm.trashItem(at: stdSource, resultingItemURL: nil)) != nil
        }

        return DesktopMigrationReport(
            destinationURL: finalURL,
            verifiedFileCount: actual.fileCount,
            verifiedTotalBytes: actual.totalBytes,
            sourcePreserved: !trashed
        )
    }

    private nonisolated static func collectManifest(
        under root: URL
    ) -> (entries: [String: Int64], fileCount: Int, totalBytes: Int64) {
        let fm = FileManager.default
        let basePath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let prefix = basePath.hasSuffix("/") ? basePath : basePath + "/"
        var entries: [String: Int64] = [:]
        var fileCount = 0
        var totalBytes: Int64 = 0

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]
        ) else {
            return (entries, 0, 0)
        }

        for case let url as URL in enumerator {
            let stdPath = url.standardizedFileURL.resolvingSymlinksInPath().path
            let rel = stdPath.hasPrefix(prefix) ? String(stdPath.dropFirst(prefix.count)) : url.lastPathComponent
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey])
            if values?.isDirectory == true {
                entries[rel] = -1
            } else {
                let bytes = Int64(values?.fileSize ?? 0)
                entries[rel] = bytes
                fileCount += 1
                totalBytes += bytes
            }
        }
        return (entries, fileCount, totalBytes)
    }

    private nonisolated static func pathsOverlap(_ a: String, _ b: String) -> Bool {
        let normA = a.hasSuffix("/") ? a : a + "/"
        let normB = b.hasSuffix("/") ? b : b + "/"
        return a == b || normB.hasPrefix(normA) || normA.hasPrefix(normB)
    }
}
