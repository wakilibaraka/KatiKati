import Foundation

struct DesktopOrganizeOptions: Equatable, Sendable {
    var sourceDirectory: URL
    var destinationRoot: URL
    var includeFolders: Bool
    var enabledCategories: Set<DesktopAutoStackCategory>
    var createBoxesForCategories: Bool

    init(
        sourceDirectory: URL,
        destinationRoot: URL,
        includeFolders: Bool = false,
        enabledCategories: Set<DesktopAutoStackCategory> = Set(DesktopAutoStackCategory.allCases),
        createBoxesForCategories: Bool = true
    ) {
        self.sourceDirectory = sourceDirectory
        self.destinationRoot = destinationRoot
        self.includeFolders = includeFolders
        self.enabledCategories = enabledCategories
        self.createBoxesForCategories = createBoxesForCategories
    }
}

struct DesktopOrganizeMoveItem: Equatable, Identifiable, Sendable {
    var id: String { sourceURL.path }
    let sourceURL: URL
    let filename: String
    let category: DesktopAutoStackCategory
}

struct DesktopOrganizeBucket: Equatable, Identifiable, Sendable {
    var id: DesktopAutoStackCategory { category }
    let category: DesktopAutoStackCategory
    let folderName: String
    let targetDirectory: URL
    let items: [DesktopOrganizeMoveItem]
}

struct DesktopOrganizePlan: Equatable, Sendable {
    let sourceDirectory: URL
    let destinationRoot: URL
    let buckets: [DesktopOrganizeBucket]
    let skippedNames: [String]

    var totalFileCount: Int {
        buckets.reduce(0) { $0 + $1.items.count }
    }
}

struct DesktopOrganizeUndoEntry: Codable, Equatable, Sendable {
    let originalPath: String
    let movedPath: String
}

struct DesktopOrganizeUndoRecord: Codable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let sourceDirectoryPath: String
    let createdDirectoryPaths: [String]
    let moves: [DesktopOrganizeUndoEntry]
}

/// Pure dry-run planner that turns directory entries into previewable, category-bucketed move plans.
enum DesktopAutoOrganizeEngine {
    static func buildPlan(
        entries: [FolderContentsLoader.Entry],
        options: DesktopOrganizeOptions
    ) -> DesktopOrganizePlan {
        let destPath = options.destinationRoot.standardizedFileURL.resolvingSymlinksInPath().path
        var grouped: [DesktopAutoStackCategory: [DesktopOrganizeMoveItem]] = [:]
        var skipped: [String] = []

        for entry in entries {
            let name = entry.url.lastPathComponent
            if name.hasPrefix(".") {
                skipped.append(name)
                continue
            }
            let entryPath = entry.url.standardizedFileURL.resolvingSymlinksInPath().path
            if entryPath == destPath {
                skipped.append(name)
                continue
            }

            let category = DesktopAutoStackClassifier.category(
                forFileName: name,
                isDirectory: entry.isDirectory
            )
            if entry.isDirectory && category != .apps && !options.includeFolders {
                skipped.append(name)
                continue
            }
            guard options.enabledCategories.contains(category) else {
                skipped.append(name)
                continue
            }

            grouped[category, default: []].append(DesktopOrganizeMoveItem(
                sourceURL: entry.url,
                filename: name,
                category: category
            ))
        }

        let buckets: [DesktopOrganizeBucket] = DesktopAutoStackCategory.allCases.compactMap { category in
            guard let raw = grouped[category], !raw.isEmpty else { return nil }
            let sorted = raw.sorted {
                $0.filename.localizedStandardCompare($1.filename) == .orderedAscending
            }
            let folderName = category.localizedTitle
            return DesktopOrganizeBucket(
                category: category,
                folderName: folderName,
                targetDirectory: options.destinationRoot.appendingPathComponent(folderName, isDirectory: true),
                items: sorted
            )
        }

        return DesktopOrganizePlan(
            sourceDirectory: options.sourceDirectory,
            destinationRoot: options.destinationRoot,
            buckets: buckets,
            skippedNames: skipped
        )
    }
}
