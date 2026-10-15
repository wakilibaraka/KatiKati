import AppKit
import CoreGraphics
import ScreenCaptureKit

// Phase 9c — window-content thumbnails for the hover preview. Captured ONLY while the chip panel is
// open (never at rest): one capture on open, refreshed at ≤ 2 Hz while visible. Needs the Screen
// Recording permission; without it `isAuthorized` is false and the panel falls back to icon + title.
//
// ScreenCaptureKit since 2026-10-15: `CGWindowListCreateImage` is obsoleted in macOS 15 (the SDK
// rejects it outright at this floor). A `desktopIndependentWindow` filter captures the window alone,
// whatever covers it, which is what `.optionIncludingWindow` used to give us.

enum WindowThumbnailCapture {
    static var isAuthorized: Bool { CGPreflightScreenCaptureAccess() }

    /// Asks the system for Screen Recording (shows the one-time prompt). Never called implicitly.
    @discardableResult
    static func requestAuthorization() -> Bool { CGRequestScreenCaptureAccess() }

    /// Captures `windowID` scaled to fit `maxPixelSize` (aspect preserved). The capture runs off the
    /// caller's actor; `nil` = nothing to show (minimised / off-space / not authorised / refused).
    static func capture(windowID: CGWindowID, maxPixelSize: CGSize) async -> NSImage? {
        guard isAuthorized else { return nil }
        guard let window = try? await SCShareableContent
            .excludingDesktopWindows(false, onScreenWindowsOnly: false)
            .windows
            .first(where: { $0.windowID == windowID }) else { return nil }
        // The output size is the configuration's, in pixels; the window is scaled to it. A window
        // frame is in points, and a thumbnail never upscales, so the scale is capped at 1.
        let source = window.frame.size
        let scale = min(maxPixelSize.width / source.width, maxPixelSize.height / source.height, 1)
        let pixels = CGSize(width: (source.width * scale).rounded(), height: (source.height * scale).rounded())
        guard pixels.width > 8, pixels.height > 8 else { return nil }
        let configuration = SCStreamConfiguration()
        configuration.width = Int(pixels.width)
        configuration.height = Int(pixels.height)
        configuration.showsCursor = false
        guard let cg = try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window),
            configuration: configuration
        ) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
