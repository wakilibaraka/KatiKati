import Foundation

/// Phase 30k: scans the home folder (skipping heavy/system dirs) into a `FileIndex`. Runs off the caller's
/// thread; capped so memory stays bounded.
enum DirectoryScanner {
    private static let skipped: Set<String> = [
        "Library", "node_modules", ".git", ".Trash", ".build", "Pods", "DerivedData", ".cache", ".npm",
        ".gradle", ".cargo", ".rustup", "site-packages", "__pycache__",
    ]

    static func scan(root: String = NSHomeDirectory(), limit: Int = 400_000) -> [FileIndex.Entry] {
        var out: [FileIndex.Entry] = []
        let options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        guard let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: root),
                                                             includingPropertiesForKeys: [.isDirectoryKey],
                                                             options: options,
                                                             errorHandler: { _, _ in true }) else { return [] }
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name.hasPrefix(".") { enumerator.skipDescendants(); continue }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory, skipped.contains(name) { enumerator.skipDescendants(); continue }
            out.append(FileIndex.Entry(path: url.path, name: name, isDirectory: isDirectory))
            if out.count >= limit { break }
        }
        return out
    }
}
