import AppKit
import Foundation
import QuickLookThumbnailing

/// Bounded LRU icon and QuickLook thumbnail cache for desktop folder boxes.
@MainActor
enum DesktopThumbnailCache {
    private static let icons: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 200
        return cache
    }()

    private static let thumbnails: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 200
        return cache
    }()

    static func clearAll() {
        icons.removeAllObjects()
        thumbnails.removeAllObjects()
    }

    /// The profile's MB budget applies to both caches; costs are approximate RGBA bytes.
    static func applyBudget(megabytes: Int) {
        let limit = max(1, megabytes) * 1024 * 1024
        icons.totalCostLimit = limit
        thumbnails.totalCostLimit = limit
    }

    static func icon(for path: String, size: CGFloat) -> NSImage {
        let key = "\(path)|\(Int(size.rounded()))" as NSString
        if let cached = icons.object(forKey: key) { return cached }
        let base = NSWorkspace.shared.icon(forFile: path)
        let copy = (base.copy() as? NSImage) ?? base
        copy.size = NSSize(width: size, height: size)
        icons.setObject(copy, forKey: key, cost: Int(size * size * 4))
        return copy
    }

    static func cachedThumbnail(path: String, modified: Date?, size: CGFloat, scale: CGFloat) -> NSImage? {
        thumbnails.object(forKey: thumbnailKey(path: path, modified: modified, size: size, scale: scale))
    }

    static func loadThumbnail(path: String, modified: Date?, size: CGFloat, scale: CGFloat) async -> NSImage? {
        let key = thumbnailKey(path: path, modified: modified, size: size, scale: scale)
        if let hit = thumbnails.object(forKey: key) { return hit }

        let request = QLThumbnailGenerator.Request(
            fileAt: URL(fileURLWithPath: path),
            size: CGSize(width: size, height: size),
            scale: max(1, scale),
            representationTypes: .thumbnail
        )
        request.iconMode = true

        let image: NSImage? = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
                if let rep {
                    continuation.resume(returning: NSImage(cgImage: rep.cgImage, size: NSSize(width: size, height: size)))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
        if let image { thumbnails.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height * 4)) }
        return image
    }

    private static func thumbnailKey(path: String, modified: Date?, size: CGFloat, scale: CGFloat) -> NSString {
        "\(path)|\(modified?.timeIntervalSinceReferenceDate ?? 0)|\(Int(size.rounded()))|\(Int(scale.rounded()))" as NSString
    }
}
