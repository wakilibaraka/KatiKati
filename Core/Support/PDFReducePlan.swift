import Foundation

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
