import AppKit
import Foundation
import ImageIO

enum DesktopAssetKind: String, Sendable {
    case panorama
    case widgetBackground
    case widgetIcon

    var maxPixelDimension: Int {
        switch self {
        case .panorama: return 3840
        case .widgetBackground: return 1280
        case .widgetIcon: return 128
        }
    }
}

private final class DesktopAssetCacheBox: @unchecked Sendable {
    let storage: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 48
        return cache
    }()
}

/// Manages imported custom icons/backgrounds/panoramas and serves bounded downsampled `NSImage` assets.
enum DesktopAssetStore {
    private static let cacheBox = DesktopAssetCacheBox()

    nonisolated static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support
            .appendingPathComponent("KatiKati", isDirectory: true)
            .appendingPathComponent("DesktopAssets", isDirectory: true)
    }

    nonisolated static func importImage(
        from sourceURL: URL,
        kind: DesktopAssetKind,
        directory: URL = defaultDirectory
    ) throws -> URL {
        guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              CGImageSourceGetCount(imageSource) > 0
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension.lowercased()
        let dest = directory.appendingPathComponent("\(kind.rawValue)-\(UUID().uuidString).\(ext)", isDirectory: false)
        try fm.copyItem(at: sourceURL, to: dest)
        return dest
    }

    nonisolated static func decodedImage(at path: String, maxPixelDimension: Int) -> NSImage? {
        guard !path.isEmpty else { return nil }
        let modStamp = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)?
            .timeIntervalSinceReferenceDate ?? 0
        let key = "\(path)|\(Int(modStamp.rounded()))|\(maxPixelDimension)" as NSString
        if let hit = cacheBox.storage.object(forKey: key) {
            return hit
        }

        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelDimension),
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cacheBox.storage.setObject(image, forKey: key)
        return image
    }

    nonisolated static func pruneUnusedAssets(
        referencedPaths: Set<String>,
        in directory: URL = defaultDirectory
    ) {
        let fm = FileManager.default
        let normalizedRefs = Set(referencedPaths.map(FilePathNormalization.normalized))
        guard let entries = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for url in entries {
            let norm = FilePathNormalization.normalized(url.path)
            if !normalizedRefs.contains(norm) {
                try? fm.removeItem(at: url)
            }
        }
    }

    nonisolated static func clearCache() {
        cacheBox.storage.removeAllObjects()
    }
}
