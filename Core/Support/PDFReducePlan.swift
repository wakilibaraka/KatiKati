import AppKit
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Phase 22e: the pure numbers behind "reduce PDF size" — page raster scale and JPEG quality. The
/// platform half (`ShelfActions.reducePDF`) applies them and fails closed if PDFKit can't read a page.
enum PDFReducePlan {
    static let defaultQuality = 0.6
    /// How much to shrink each page's raster. 0.75 keeps A4 around 130 dpi at 100 %.
    static let defaultScale = 0.75

    /// JPEG quality for the rasterised pages, floored so text stays legible.
    static func quality(_ requested: Double) -> Double {
        requested.isFinite ? min(max(requested, 0.2), 0.9) : defaultQuality
    }

    /// Scaled page size keeping the aspect ratio; clamped to 10–100 % and never below 1×1.
    static func renderedSize(width: Double, height: Double, scale: Double = PDFReducePlan.defaultScale)
        -> (width: Double, height: Double) {
        let s = scale.isFinite ? min(max(scale, 0.1), 1) : defaultScale
        return (max(1, width * s), max(1, height * s))
    }
}

/// 55c: the image half of the shelf's reduce action — the same 75 % / 60 % numbers as a PDF, expressed
/// as a longest-edge cap so an aspect ratio is kept without touching alpha.
enum ImageReducePlan {
    static let defaultQuality = 0.6
    static let defaultScale = 0.75

    static func quality(_ requested: Double) -> Double {
        requested.isFinite ? min(max(requested, 0.2), 0.9) : defaultQuality
    }

    /// Longest-edge cap for the downscale; clamped to 10–100 % and never below 1 pixel.
    static func maxPixelSize(longestEdge: Int, scale: Double = ImageReducePlan.defaultScale) -> Int {
        let s = scale.isFinite ? min(max(scale, 0.1), 1) : defaultScale
        return max(1, Int((Double(longestEdge) * s).rounded()))
    }
}

// MARK: - Phase 60: Shelf / File Tray Transforms (Slice D-TrayTransform)

/// Target formats for 1-click shelf image conversion.
enum ImageTargetFormat: String, CaseIterable, Sendable {
    case png
    case jpeg
    case webp

    var fileExtension: String { rawValue }

    var uniformTypeIdentifier: String {
        switch self {
        case .png: return "public.png"
        case .jpeg: return "public.jpeg"
        case .webp: return "org.webmproject.webp"
        }
    }
}

/// Pure planning logic for shelf and file tray operations (background removal, zip archive, conversion, PDF combine).
enum FileTransformPlan {
    /// Supported image extensions for Vision foreground instance mask background removal.
    static let bgRemovalExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff"]

    /// Returns whether a file is eligible for on-device background removal.
    static func canRemoveBackground(for fileURL: URL) -> Bool {
        bgRemovalExtensions.contains(fileURL.pathExtension.lowercased())
    }

    /// Destination URL for background-removed image: "<name>_nobg.png" in the same directory.
    static func noBackgroundDestination(for fileURL: URL) -> URL {
        let dir = fileURL.deletingLastPathComponent()
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        return dir.appendingPathComponent("\(baseName)_nobg.png")
    }

    /// Destination URL for archive: single file -> "<name>.zip", multiple -> "Archive.zip".
    static func zipDestination(for urls: [URL]) -> URL? {
        guard let first = urls.first else { return nil }
        let dir = first.deletingLastPathComponent()
        if urls.count == 1 {
            let baseName = first.deletingPathExtension().lastPathComponent
            return dir.appendingPathComponent("\(baseName).zip")
        }
        return dir.appendingPathComponent("Archive.zip")
    }

    /// Destination URL for image format conversion: "<name>.<ext>"
    static func convertedDestination(for fileURL: URL, format: ImageTargetFormat) -> URL {
        let dir = fileURL.deletingLastPathComponent()
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        return dir.appendingPathComponent("\(baseName).\(format.fileExtension)")
    }

    /// Destination URL for combined PDF from multiple files.
    static func combinedPDFDestination(for urls: [URL]) -> URL? {
        guard let first = urls.first else { return nil }
        let dir = first.deletingLastPathComponent()
        if urls.count == 1 {
            let baseName = first.deletingPathExtension().lastPathComponent
            return dir.appendingPathComponent("\(baseName)_combined.pdf")
        }
        return dir.appendingPathComponent("Combined.pdf")
    }
}

// MARK: - SLICE DP-1: Droppy Customization Models, File Tray & Transform Engine

enum DroppyGlassMaterial: String, CaseIterable, Codable, Identifiable, Sendable {
    case dynamicGlass, liquidGlass, solidOLED
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dynamicGlass: return "Dynamic Glass"
        case .liquidGlass: return "Liquid Glass"
        case .solidOLED: return "Solid OLED"
        }
    }
    var baseTransparency: Double {
        switch self {
        case .dynamicGlass: return 0.38
        case .liquidGlass: return 0.68
        case .solidOLED: return 0.0
        }
    }
    func resolvedTransparency(isLowPowerMode: Bool) -> Double { isLowPowerMode ? 0.0 : baseTransparency }
    func shouldRenderBlur(isLowPowerMode: Bool) -> Bool { !isLowPowerMode && self != .solidOLED }
}

enum DroppyAccentTheme: String, CaseIterable, Codable, Identifiable, Sendable {
    case oceanBlue, emberOrange, mintGreen, violetPulse, graphite
    var id: String { rawValue }
    var title: String {
        switch self {
        case .oceanBlue: return "Ocean Blue"
        case .emberOrange: return "Ember Orange"
        case .mintGreen: return "Mint Green"
        case .violetPulse: return "Violet Pulse"
        case .graphite: return "Graphite"
        }
    }
    var hex: String {
        switch self {
        case .oceanBlue: return "#0A84FF"
        case .emberOrange: return "#FF9F0A"
        case .mintGreen: return "#30D158"
        case .violetPulse: return "#BF5AF2"
        case .graphite: return "#8E8E93"
        }
    }
}

enum DroppyShelfWidgetKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case fileTray, pomodoro, clipboardNotes, systemStats
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fileTray: return "File Tray"
        case .pomodoro: return "Pomodoro"
        case .clipboardNotes: return "Clipboard & Notes"
        case .systemStats: return "System Stats"
        }
    }
    var symbol: String {
        switch self {
        case .fileTray: return "tray.and.arrow.down.fill"
        case .pomodoro: return "timer"
        case .clipboardNotes: return "doc.on.clipboard"
        case .systemStats: return "gauge.medium"
        }
    }
}

final class DroppyShelfConfigStore: ObservableObject {
    static let orderKey = "com.katikati.droppy.shelfOrder"
    static let hiddenKey = "com.katikati.droppy.shelfHidden"
    static let glassKey = "com.katikati.droppy.glassMaterial"
    static let accentKey = "com.katikati.droppy.accentTheme"

    @Published private(set) var order: [DroppyShelfWidgetKind]
    @Published private(set) var hidden: Set<DroppyShelfWidgetKind>
    @Published private(set) var glassMaterial: DroppyGlassMaterial
    @Published private(set) var accentTheme: DroppyAccentTheme
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.order = Self.decodeOrder(defaults.string(forKey: Self.orderKey) ?? "")
        self.hidden = Self.decodeHidden(defaults.string(forKey: Self.hiddenKey) ?? "")
        self.glassMaterial = DroppyGlassMaterial(rawValue: defaults.string(forKey: Self.glassKey) ?? "") ?? .dynamicGlass
        self.accentTheme = DroppyAccentTheme(rawValue: defaults.string(forKey: Self.accentKey) ?? "") ?? .oceanBlue
    }

    func visibleWidgets() -> [DroppyShelfWidgetKind] { order.filter { !hidden.contains($0) } }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        order.move(fromOffsets: fromOffsets, toOffset: toOffset)
        defaults.set(Self.encodeOrder(order), forKey: Self.orderKey)
    }

    func setHidden(_ kind: DroppyShelfWidgetKind, _ isHidden: Bool) {
        if isHidden { hidden.insert(kind) } else { hidden.remove(kind) }
        defaults.set(Self.encodeHidden(hidden), forKey: Self.hiddenKey)
    }

    func setGlassMaterial(_ material: DroppyGlassMaterial) {
        glassMaterial = material
        defaults.set(material.rawValue, forKey: Self.glassKey)
    }

    func setAccentTheme(_ theme: DroppyAccentTheme) {
        accentTheme = theme
        defaults.set(theme.rawValue, forKey: Self.accentKey)
    }

    func reset() {
        order = DroppyShelfWidgetKind.allCases
        hidden = []
        glassMaterial = .dynamicGlass
        accentTheme = .oceanBlue
        defaults.set(Self.encodeOrder(order), forKey: Self.orderKey)
        defaults.set("", forKey: Self.hiddenKey)
        defaults.set(glassMaterial.rawValue, forKey: Self.glassKey)
        defaults.set(accentTheme.rawValue, forKey: Self.accentKey)
    }

    static func encodeOrder(_ list: [DroppyShelfWidgetKind]) -> String { list.map(\.rawValue).joined(separator: ",") }
    static func encodeHidden(_ set: Set<DroppyShelfWidgetKind>) -> String { set.map(\.rawValue).sorted().joined(separator: ",") }
    static func decodeOrder(_ raw: String) -> [DroppyShelfWidgetKind] {
        var result: [DroppyShelfWidgetKind] = []
        for token in raw.split(separator: ",") {
            if let k = DroppyShelfWidgetKind(rawValue: String(token)), !result.contains(k) { result.append(k) }
        }
        for k in DroppyShelfWidgetKind.allCases where !result.contains(k) { result.append(k) }
        return result
    }
    static func decodeHidden(_ raw: String) -> Set<DroppyShelfWidgetKind> {
        Set(raw.split(separator: ",").compactMap { DroppyShelfWidgetKind(rawValue: String($0)) })
    }
}

struct DroppyFileTrayItem: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var path: String
    var isPinned: Bool
    var addedAt: Date
    var url: URL { URL(fileURLWithPath: path) }
    var fileName: String { url.lastPathComponent }
    init(id: UUID = UUID(), path: String, isPinned: Bool = false, addedAt: Date = Date()) {
        self.id = id; self.path = path; self.isPinned = isPinned; self.addedAt = addedAt
    }
}

final class DroppyFileTrayStore: ObservableObject {
    static let itemsKey = "com.katikati.droppy.fileTrayItems"
    @Published private(set) var items: [DroppyFileTrayItem] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.itemsKey),
           let decoded = try? JSONDecoder().decode([DroppyFileTrayItem].self, from: data) {
            self.items = Self.sorted(decoded)
        }
    }

    func add(urls: [URL], now: Date = Date()) {
        for url in urls {
            let clean = url.standardizedFileURL.path
            guard !clean.isEmpty else { continue }
            if let idx = items.firstIndex(where: { URL(fileURLWithPath: $0.path).standardizedFileURL.path == clean }) {
                items[idx].addedAt = now
            } else {
                items.append(DroppyFileTrayItem(path: clean, isPinned: false, addedAt: now))
            }
        }
        items = Self.sorted(items)
        persist()
    }

    func remove(id: UUID) { items.removeAll { $0.id == id }; persist() }
    func togglePin(id: UUID) {
        if let i = items.firstIndex(where: { $0.id == id }) { items[i].isPinned.toggle(); items = Self.sorted(items); persist() }
    }
    func clearUnpinned() { items.removeAll { !$0.isPinned }; persist() }
    func clearAll() { items.removeAll(); persist() }

    private func persist() { if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: Self.itemsKey) } }
    private static func sorted(_ list: [DroppyFileTrayItem]) -> [DroppyFileTrayItem] {
        list.sorted { a, b in a.isPinned != b.isPinned ? a.isPinned : a.addedAt > b.addedAt }
    }
}

enum FileTransformEngine {
    enum TransformError: Error, Equatable { case emptyInput, unreadableSource, transformFailed }

    static func zipFiles(_ urls: [URL], destination: URL? = nil) throws -> URL {
        guard !urls.isEmpty, let out = destination ?? FileTransformPlan.zipDestination(for: urls) else { throw TransformError.emptyInput }
        let fm = FileManager.default
        for u in urls where !fm.fileExists(atPath: u.path) { throw TransformError.unreadableSource }
        let stage = fm.temporaryDirectory.appendingPathComponent("droppy-zip-\(UUID().uuidString)", isDirectory: true)
        let bundle = stage.appendingPathComponent(out.deletingPathExtension().lastPathComponent, isDirectory: true)
        try fm.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }
        for u in urls {
            var target = bundle.appendingPathComponent(u.lastPathComponent)
            if fm.fileExists(atPath: target.path) {
                target = bundle.appendingPathComponent("\(UUID().uuidString.prefix(4))_\(u.lastPathComponent)")
            }
            try fm.copyItem(at: u, to: target)
        }
        try? fm.removeItem(at: out)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        proc.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", bundle.path, out.path]
        try proc.run(); proc.waitUntilExit()
        guard proc.terminationStatus == 0, fm.fileExists(atPath: out.path) else { throw TransformError.transformFailed }
        return out
    }

    static func resizeImage(at url: URL, scale: Double = ImageReducePlan.defaultScale, quality: Double = ImageReducePlan.defaultQuality, destination: URL? = nil) throws -> URL {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0 else {
            throw TransformError.unreadableSource
        }
        let maxPx = ImageReducePlan.maxPixelSize(longestEdge: max(w, h), scale: scale)
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maxPx]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { throw TransformError.transformFailed }
        let isPNG = (destination?.pathExtension.lowercased() ?? url.pathExtension.lowercased()) == "png"
        let out = destination ?? url.deletingLastPathComponent().appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)_resized.\(isPNG ? "png" : "jpg")")
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, (isPNG ? "public.png" : "public.jpeg") as CFString, 1, nil) else {
            throw TransformError.transformFailed
        }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: ImageReducePlan.quality(quality)] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw TransformError.transformFailed }
        return out
    }

    static func mergePDFs(_ urls: [URL], destination: URL? = nil) throws -> URL {
        guard !urls.isEmpty, let out = destination ?? FileTransformPlan.combinedPDFDestination(for: urls) else { throw TransformError.emptyInput }
        let merged = PDFDocument()
        for url in urls {
            if let doc = PDFDocument(url: url), doc.pageCount > 0 {
                for i in 0..<doc.pageCount { if let p = doc.page(at: i) { merged.insert(p, at: merged.pageCount) } }
            } else if let img = NSImage(contentsOf: url), let page = PDFPage(image: img) {
                merged.insert(page, at: merged.pageCount)
            } else {
                throw TransformError.unreadableSource
            }
        }
        guard merged.pageCount > 0, merged.write(to: out) else { throw TransformError.transformFailed }
        return out
    }
}
