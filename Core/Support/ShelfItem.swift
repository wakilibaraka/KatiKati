import Foundation
import UniformTypeIdentifiers

// Dropover-style shelf — the pure model and policy. `ShelfStore` (app layer) owns persistence and file
// I/O; everything that is a decision (ordering, pinning, expiry, migration) lives here and is unit-tested.
// Dual-compiled.

/// How dropped files are kept.
enum ShelfStorage: String, CaseIterable, Sendable {
    /// The shelf remembers the path; the file stays where it is (default).
    case reference
    /// The shelf copies the file into an app-owned folder so it survives the original being moved.
    case copy
}

struct ShelfItem: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var path: String
    var isPinned: Bool
    var addedAt: Date
    /// `true` when `path` is a copy owned by the shelf (deleted on removal).
    var isOwnedCopy: Bool

    init(id: UUID = UUID(), path: String, isPinned: Bool = false, addedAt: Date, isOwnedCopy: Bool = false) {
        self.id = id
        self.path = path
        self.isPinned = isPinned
        self.addedAt = addedAt
        self.isOwnedCopy = isOwnedCopy
    }
}

enum ShelfPolicy {
    static let expiryChoices = [1, 3, 7]
    static let presentationStyleKey = "com.katikati.shelf.presentationStyle"
    static let showTextExcerptKey = "com.katikati.shelf.showTextExcerpt"
    static let notchAutoOpenOnDragKey = "com.katikati.shelf.notchAutoOpenOnDrag"
    static let syncNotchTrayKey = "com.katikati.shelf.syncNotchTray"
    static let hideExamplePreviewKey = "com.katikati.shelf.hideExamplePreview"

    static func isExampleURL(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix("Example_") || url.path.contains("/ShelfExamples/")
    }

    /// Pinned first, then newest first. Stable for equal dates.
    static func ordered(_ items: [ShelfItem]) -> [ShelfItem] {
        items.enumerated().sorted { a, b in
            if a.element.isPinned != b.element.isPinned { return a.element.isPinned }
            if a.element.addedAt != b.element.addedAt { return a.element.addedAt > b.element.addedAt }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// Adds new paths (deduped, empties dropped). A path already on the shelf is moved to "now" and keeps
    /// its pin. Returns the items unchanged-ordered; use `ordered` for display.
    static func stashing(_ items: [ShelfItem], adding entries: [(path: String, isOwnedCopy: Bool)], now: Date) -> [ShelfItem] {
        var result = items
        var seen = Set<String>()
        for entry in entries where !entry.path.isEmpty && seen.insert(entry.path).inserted {
            if let i = result.firstIndex(where: { $0.path == entry.path }) {
                result[i].addedAt = now
            } else {
                result.append(ShelfItem(path: entry.path, addedAt: now, isOwnedCopy: entry.isOwnedCopy))
            }
        }
        return result
    }

    static func togglingPin(_ items: [ShelfItem], id: UUID) -> [ShelfItem] {
        items.map { var i = $0; if i.id == id { i.isPinned.toggle() }; return i }
    }

    static func removing(_ items: [ShelfItem], path: String) -> [ShelfItem] {
        items.filter { $0.path != path }
    }

    /// Unpinned items older than `days` are expired; pinned items never are.
    static func expired(_ items: [ShelfItem], now: Date, days: Int) -> (kept: [ShelfItem], dropped: [ShelfItem]) {
        let limit = TimeInterval(max(0, days)) * 86_400
        var kept: [ShelfItem] = [], dropped: [ShelfItem] = []
        for item in items {
            if !item.isPinned, now.timeIntervalSince(item.addedAt) > limit { dropped.append(item) } else { kept.append(item) }
        }
        return (kept, dropped)
    }

    static func clearingUnpinned(_ items: [ShelfItem]) -> (kept: [ShelfItem], dropped: [ShelfItem]) {
        (items.filter(\.isPinned), items.filter { !$0.isPinned })
    }

    /// Old installs stored a bare newest-first path list; keep that order via descending timestamps.
    static func migrated(paths: [String], now: Date) -> [ShelfItem] {
        paths.enumerated().map { ShelfItem(path: $1, addedAt: now.addingTimeInterval(-Double($0))) }
    }
}

/// Visual layout mode for the Dock Shelf popup (`image_35a2a0.jpg` card stack vs compact icon grid).
enum ShelfPresentationStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case floatingCardStack
    case compactFileTray

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .floatingCardStack: return String(localized: "Floating Card Stack")
        case .compactFileTray: return String(localized: "Compact Tray Grid")
        }
    }
}

/// Card archetype matching the floating Shelf stack design.
enum ShelfCardArchetype: String, Equatable, Sendable {
    case richTextOrWikiCard
    case chatOrSnippetCard
    case mediaCanvasCard
    case fileDocumentCard
}

/// Pure visual presentation descriptor for one parked Shelf item.
struct ShelfCardPresentation: Equatable, Sendable {
    var archetype: ShelfCardArchetype
    var title: String
    var subtitle: String
    var excerpt: String?
    var badgeText: String
    var badgeSymbol: String
    var tiltDegrees: Double
    var usesLightCardSurface: Bool

    private static let stackTilts: [Double] = [-1.8, 1.4, -1.1, 1.6]
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "webp", "gif", "svg", "tiff"]
    private static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]
    private static let webExtensions: Set<String> = ["webloc", "url", "html", "htm"]
    private static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "rtf", "log", "json", "csv", "swift", "py", "ts", "js", "yaml", "yml"
    ]

    static func classify(
        url: URL,
        index: Int = 0,
        showTextExcerpt: Bool = true,
        maxExcerptLength: Int = 280
    ) -> ShelfCardPresentation {
        let ext = url.pathExtension.lowercased()
        let tilt = stackTilts[abs(index) % stackTilts.count]
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        let baseName = url.deletingPathExtension().lastPathComponent
        let fileName = url.lastPathComponent
        let sizeText = formattedFileSize(url: url, isDirectory: isDirectory)

        if !isDirectory && (imageExtensions.contains(ext) || videoExtensions.contains(ext) || ext == "pdf") {
            let isVideo = videoExtensions.contains(ext)
            let isPDF = ext == "pdf"
            return ShelfCardPresentation(
                archetype: .mediaCanvasCard,
                title: fileName,
                subtitle: sizeText,
                excerpt: nil,
                badgeText: ext.isEmpty ? "MEDIA" : ext.uppercased(),
                badgeSymbol: isPDF ? "doc.richtext.fill" : (isVideo ? "film.fill" : "photo.fill"),
                tiltDegrees: tilt,
                usesLightCardSurface: false
            )
        }

        let utType = UTType(filenameExtension: ext)
        let isWeb = webExtensions.contains(ext)
        let isTextLike = !isDirectory && (isWeb || textExtensions.contains(ext) || (utType?.conforms(to: .plainText) ?? false))

        if isTextLike {
            let rawText = showTextExcerpt ? readTextPreview(url: url) : nil
            let parsed = parseTextCard(rawText: rawText, fallbackTitle: baseName.isEmpty ? fileName : baseName, maxLength: maxExcerptLength)
            let lowerName = fileName.lowercased()
            let isSnippet = lowerName.hasPrefix("snippet") || lowerName.hasPrefix("chat") || lowerName.hasPrefix("note")
                || url.path.contains("/KatiKati/Shelf/")
            let archetype: ShelfCardArchetype = isSnippet ? .chatOrSnippetCard : .richTextOrWikiCard
            return ShelfCardPresentation(
                archetype: archetype,
                title: parsed.title,
                subtitle: sizeText,
                excerpt: showTextExcerpt ? parsed.excerpt : nil,
                badgeText: isWeb ? "WEB" : (isSnippet ? "NOTE" : (ext.isEmpty ? "TEXT" : ext.uppercased())),
                badgeSymbol: isWeb ? "globe" : (isSnippet ? "text.bubble.fill" : "doc.text.fill"),
                tiltDegrees: tilt,
                usesLightCardSurface: true
            )
        }

        return ShelfCardPresentation(
            archetype: .fileDocumentCard,
            title: fileName,
            subtitle: sizeText,
            excerpt: nil,
            badgeText: isDirectory ? "DIR" : (ext.isEmpty ? "FILE" : ext.uppercased()),
            badgeSymbol: isDirectory ? "folder.fill" : "doc.fill",
            tiltDegrees: tilt,
            usesLightCardSurface: false
        )
    }

    private static func readTextPreview(url: URL, byteLimit: Int = 2048) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: byteLimit)) ?? Data()
        guard !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    private static func parseTextCard(rawText: String?, fallbackTitle: String, maxLength: Int) -> (title: String, excerpt: String?) {
        guard let rawText else { return (fallbackTitle, nil) }
        let lines = rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return (fallbackTitle, nil) }

        var title = fallbackTitle
        var bodyLines = lines
        if let first = lines.first, first.hasPrefix("#") {
            let heading = first.drop(while: { $0 == "#" || $0 == " " })
            if !heading.isEmpty {
                title = String(heading)
                bodyLines = Array(lines.dropFirst())
            }
        }
        let bodySource = bodyLines.isEmpty ? lines : bodyLines
        let joined = bodySource.joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty else { return (title, nil) }
        if joined.count <= maxLength {
            return (title, joined)
        }
        let cutoff = joined.index(joined.startIndex, offsetBy: max(1, maxLength))
        return (title, String(joined[..<cutoff]).trimmingCharacters(in: .whitespacesAndNewlines) + "…")
    }

    private static func formattedFileSize(url: URL, isDirectory: Bool) -> String {
        if isDirectory { return "Folder" }
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey]), let bytes = values.fileSize {
            return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        }
        let ext = url.pathExtension.uppercased()
        return ext.isEmpty ? "File" : ext
    }
}

/// Pure batch transform actions eligible for parked Shelf items.
enum ShelfBatchTransformAction: Equatable, Identifiable, Sendable {
    case zipItems
    case mergeToPDF
    case convertImages(format: ImageTargetFormat)
    case copyAllPaths
    case airDropShare

    var id: String {
        switch self {
        case .zipItems: return "zipItems"
        case .mergeToPDF: return "mergeToPDF"
        case .convertImages(let format): return "convert.\(format.rawValue)"
        case .copyAllPaths: return "copyAllPaths"
        case .airDropShare: return "airDropShare"
        }
    }

    var title: String {
        switch self {
        case .zipItems: return String(localized: "Zip")
        case .mergeToPDF: return String(localized: "Merge PDF")
        case .convertImages(let format): return format.rawValue.uppercased()
        case .copyAllPaths: return String(localized: "Copy Paths")
        case .airDropShare: return String(localized: "AirDrop")
        }
    }

    private static let convertibleImageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "webp", "tiff", "gif"]

    static func eligibleActions(for urls: [URL]) -> [ShelfBatchTransformAction] {
        guard !urls.isEmpty else { return [] }
        let exts = urls.map { $0.pathExtension.lowercased() }
        let hasImages = exts.contains { convertibleImageExtensions.contains($0) }
        let hasPDF = exts.contains("pdf")

        var actions: [ShelfBatchTransformAction] = [.zipItems]
        if hasImages || hasPDF {
            actions.append(.mergeToPDF)
        }
        if hasImages {
            for format in ImageTargetFormat.allCases {
                actions.append(.convertImages(format: format))
            }
        }
        actions.append(.copyAllPaths)
        actions.append(.airDropShare)
        return actions
    }
}
