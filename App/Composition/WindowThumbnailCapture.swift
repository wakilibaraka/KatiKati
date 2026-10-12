import AppKit
import CoreGraphics

// Phase 9c — window-content thumbnails for the hover preview. Captured ONLY while the chip panel is
// open (never at rest): one capture on open, refreshed at ≤ 2 Hz while visible. Needs the Screen
// Recording permission; without it `isAuthorized` is false and the panel falls back to icon + title.

enum WindowThumbnailCapture {
    static var isAuthorized: Bool { CGPreflightScreenCaptureAccess() }

    /// Asks the system for Screen Recording (shows the one-time prompt). Never called implicitly.
    @discardableResult
    static func requestAuthorization() -> Bool { CGRequestScreenCaptureAccess() }

    private static let queue = DispatchQueue(label: "com.katikati.windowThumbnail", qos: .userInitiated)

    /// Captures `windowID` scaled to fit `maxPixelSize` (aspect preserved). Calls back on the main queue;
    /// `nil` = nothing to show (minimised / off-space / not authorised).
    static func capture(windowID: CGWindowID, maxPixelSize: CGSize, completion: @escaping (NSImage?) -> Void) {
        guard isAuthorized else {
            completion(nil)
            return
        }
        queue.async {
            let image = Self.captureSync(windowID: windowID, maxPixelSize: maxPixelSize)
            DispatchQueue.main.async { completion(image) }
        }
    }

    private static func captureSync(windowID: CGWindowID, maxPixelSize: CGSize) -> NSImage? {
        guard let cg = CGWindowListCreateImage(
            .null, .optionIncludingWindow, windowID, [.boundsIgnoreFraming, .bestResolution]
        ), cg.width > 8, cg.height > 8 else { return nil }
        let scale = min(maxPixelSize.width / CGFloat(cg.width), maxPixelSize.height / CGFloat(cg.height), 1)
        guard scale < 1 else { return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)) }
        let w = max(1, Int(CGFloat(cg.width) * scale)), h = max(1, Int(CGFloat(cg.height) * scale))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: cg.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let scaled = ctx.makeImage() else { return nil }
        return NSImage(cgImage: scaled, size: NSSize(width: w, height: h))
    }
}
