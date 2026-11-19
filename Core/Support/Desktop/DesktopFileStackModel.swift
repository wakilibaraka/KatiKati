import CoreGraphics
import Foundation

enum DesktopStackGroupingMode: String, Codable, CaseIterable, Sendable {
    case none
    case autoByKind
    case manual
}

enum DesktopStackDisplayMode: String, Codable, CaseIterable, Sendable {
    case adaptive
    case grid3x3
    case grid5x5
}

enum DesktopAutoStackCategory: String, Codable, CaseIterable, Sendable {
    case documents, images, videos, audio, archives, code, apps, folders, other

    var symbolName: String {
        switch self {
        case .documents: return "doc.text.fill"
        case .images: return "photo.on.rectangle.angled"
        case .videos: return "film.stack"
        case .audio: return "music.note.list"
        case .archives: return "doc.zipper"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .apps: return "square.grid.2x2.fill"
        case .folders: return "folder.fill"
        case .other: return "square.stack.3d.up.fill"
        }
    }

    var localizedTitle: String {
        switch self {
        case .documents: return String(localized: "Documents")
        case .images: return String(localized: "Images")
        case .videos: return String(localized: "Videos")
        case .audio: return String(localized: "Audio")
        case .archives: return String(localized: "Archives")
        case .code: return String(localized: "Code")
        case .apps: return String(localized: "Apps")
        case .folders: return String(localized: "Folders")
        case .other: return String(localized: "Other")
        }
    }
}

enum DesktopAutoStackClassifier {
    private static let documentsExt: Set<String> = [
        "pdf", "doc", "docx", "rtf", "rtfd", "txt", "md", "markdown",
        "pages", "numbers", "key", "xls", "xlsx", "csv", "tsv", "ppt", "pptx", "epub"
    ]
    private static let imagesExt: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "webp", "gif", "tiff", "tif",
        "svg", "raw", "dng", "cr2", "nef", "arw", "psd", "ai", "sketch", "fig", "icns"
    ]
    private static let videosExt: Set<String> = [
        "mp4", "mov", "mkv", "m4v", "avi", "webm", "wmv", "flv", "ts", "mts"
    ]
    private static let audioExt: Set<String> = [
        "mp3", "m4a", "wav", "flac", "aac", "ogg", "opus", "aiff", "aif", "mid", "midi"
    ]
    private static let archivesExt: Set<String> = [
        "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "dmg", "iso", "pkg"
    ]
    private static let codeExt: Set<String> = [
        "swift", "py", "js", "jsx", "ts", "tsx", "rs", "go", "c", "cc", "cpp",
        "h", "hpp", "m", "mm", "java", "kt", "rb", "php", "sh", "zsh", "bash",
        "json", "yaml", "yml", "toml", "xml", "html", "css", "scss", "sql", "xcodeproj", "xcworkspace"
    ]

    static func category(forFileName name: String, isDirectory: Bool) -> DesktopAutoStackCategory {
        let ext = (name as NSString).pathExtension.lowercased()
        if ext == "app" { return .apps }
        if isDirectory { return .folders }
        if documentsExt.contains(ext) { return .documents }
        if imagesExt.contains(ext) { return .images }
        if videosExt.contains(ext) { return .videos }
        if audioExt.contains(ext) { return .audio }
        if archivesExt.contains(ext) { return .archives }
        if codeExt.contains(ext) { return .code }
        return .other
    }
}

struct DesktopManualStack: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var filenames: [String]

    init(id: UUID = UUID(), title: String, filenames: [String]) {
        self.id = id
        self.title = title
        self.filenames = filenames
    }
}

struct DesktopResolvedStack: Equatable, Identifiable {
    let id: String
    var title: String
    var category: DesktopAutoStackCategory?
    var manualStackID: UUID?
    var entries: [FolderContentsLoader.Entry]
}

enum DesktopDisplayCell: Equatable, Identifiable {
    case file(FolderContentsLoader.Entry)
    case stack(DesktopResolvedStack)

    var id: String {
        switch self {
        case .file(let entry): return "file:\(entry.url.path)"
        case .stack(let stack): return "stack:\(stack.id)"
        }
    }
}

/// Projects flat folder entries into File Stacks and manages manual stack mutations.
enum DesktopStackProjection {
    static func project(
        entries: [FolderContentsLoader.Entry],
        mode: DesktopStackGroupingMode,
        manualStacks: [DesktopManualStack]
    ) -> [DesktopDisplayCell] {
        switch mode {
        case .none:
            return entries.map { .file($0) }

        case .autoByKind:
            var grouped: [DesktopAutoStackCategory: [FolderContentsLoader.Entry]] = [:]
            for entry in entries {
                let category = DesktopAutoStackClassifier.category(
                    forFileName: entry.url.lastPathComponent,
                    isDirectory: entry.isDirectory
                )
                grouped[category, default: []].append(entry)
            }
            var cells: [DesktopDisplayCell] = []
            var singletons: [FolderContentsLoader.Entry] = []
            for category in DesktopAutoStackCategory.allCases {
                guard let bucket = grouped[category], !bucket.isEmpty else { continue }
                if bucket.count >= 2 {
                    cells.append(.stack(DesktopResolvedStack(
                        id: "auto:\(category.rawValue)",
                        title: category.localizedTitle,
                        category: category,
                        manualStackID: nil,
                        entries: bucket
                    )))
                } else {
                    singletons.append(contentsOf: bucket)
                }
            }
            cells.append(contentsOf: singletons.map { .file($0) })
            return cells

        case .manual:
            let byName = Dictionary(
                entries.map { ($0.url.lastPathComponent, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            var assigned: Set<String> = []
            var cells: [DesktopDisplayCell] = []
            for stack in manualStacks {
                let resolved = stack.filenames.compactMap { name -> FolderContentsLoader.Entry? in
                    guard !assigned.contains(name), let entry = byName[name] else { return nil }
                    assigned.insert(name)
                    return entry
                }
                guard !resolved.isEmpty else { continue }
                cells.append(.stack(DesktopResolvedStack(
                    id: "manual:\(stack.id.uuidString)",
                    title: stack.title,
                    category: nil,
                    manualStackID: stack.id,
                    entries: resolved
                )))
            }
            for entry in entries where !assigned.contains(entry.url.lastPathComponent) {
                cells.append(.file(entry))
            }
            return cells
        }
    }

    static func createStack(title: String, filenames: [String], in stacks: [DesktopManualStack]) -> [DesktopManualStack] {
        let unique = deduplicated(filenames)
        guard !unique.isEmpty else { return stacks }
        let movingSet = Set(unique)
        var next = removeFromAll(movingSet, in: stacks)
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        next.append(DesktopManualStack(title: trimmed.isEmpty ? "Stack \(next.count + 1)" : trimmed, filenames: unique))
        return next
    }

    static func addFiles(_ filenames: [String], toStackID stackID: UUID, in stacks: [DesktopManualStack]) -> [DesktopManualStack] {
        let moving = deduplicated(filenames)
        guard !moving.isEmpty else { return stacks }
        let movingSet = Set(moving)
        var next = stacks.map { stack -> DesktopManualStack in
            var copy = stack
            copy.filenames.removeAll { movingSet.contains($0) }
            if copy.id == stackID {
                copy.filenames.append(contentsOf: moving)
            }
            return copy
        }
        next.removeAll { $0.filenames.isEmpty }
        return next
    }

    static func removeFiles(_ filenames: [String], fromStackID stackID: UUID, in stacks: [DesktopManualStack]) -> [DesktopManualStack] {
        let removal = Set(filenames)
        return stacks.compactMap { stack in
            guard stack.id == stackID else { return stack }
            var copy = stack
            copy.filenames.removeAll { removal.contains($0) }
            return copy.filenames.isEmpty ? nil : copy
        }
    }

    static func ungroup(stackID: UUID, in stacks: [DesktopManualStack]) -> [DesktopManualStack] {
        stacks.filter { $0.id != stackID }
    }

    static func rename(stackID: UUID, to title: String, in stacks: [DesktopManualStack]) -> [DesktopManualStack] {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return stacks }
        return stacks.map { stack in
            guard stack.id == stackID else { return stack }
            var copy = stack
            copy.title = trimmed
            return copy
        }
    }

    private static func removeFromAll(_ names: Set<String>, in stacks: [DesktopManualStack]) -> [DesktopManualStack] {
        stacks.compactMap { stack in
            var copy = stack
            copy.filenames.removeAll { names.contains($0) }
            return copy.filenames.isEmpty ? nil : copy
        }
    }

    private static func deduplicated(_ items: [String]) -> [String] {
        var seen: Set<String> = []
        return items.filter { seen.insert($0).inserted }
    }
}

enum DesktopStackPopoverLayout {
    static func metrics(itemCount: Int, mode: DesktopStackDisplayMode) -> (columns: Int, size: CGSize) {
        let count = max(1, itemCount)
        switch mode {
        case .grid3x3:
            return (3, CGSize(width: 296, height: 316))
        case .grid5x5:
            return (5, CGSize(width: 448, height: 420))
        case .adaptive:
            let cols: Int
            switch count {
            case 1: cols = 1
            case 2...4: cols = 2
            case 5...9: cols = 3
            case 10...16: cols = 4
            default: cols = 5
            }
            let rows = Int(ceil(Double(count) / Double(cols)))
            let width = min(460, max(168, CGFloat(cols) * 86 + 32))
            let height = min(420, max(154, CGFloat(rows) * 84 + 62))
            return (cols, CGSize(width: width, height: height))
        }
    }
}
