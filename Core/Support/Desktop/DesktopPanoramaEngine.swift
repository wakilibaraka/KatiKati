import CoreGraphics
import Foundation

struct DesktopPanoramaSlice: Equatable, Sendable {
    let imageDrawSize: CGSize
    let imageOriginInWidget: CGPoint
    let normalizedCropRect: CGRect
    let pixelCropRect: CGRect
}

/// Pure coordinate-mapping engine projecting a shared screen-space wallpaper across individual floating widgets.
enum DesktopPanoramaEngine {
    static func slice(
        widgetFrame: CGRect,
        canvasBounds: CGRect,
        imageSize: CGSize,
        scaleMode: DesktopPanoramaScaleMode = .aspectFill
    ) -> DesktopPanoramaSlice? {
        guard widgetFrame.width > 0,
              widgetFrame.height > 0,
              canvasBounds.width > 0,
              canvasBounds.height > 0,
              imageSize.width > 0,
              imageSize.height > 0
        else { return nil }

        let scaleX = canvasBounds.width / imageSize.width
        let scaleY = canvasBounds.height / imageSize.height
        let scale = scaleMode == .aspectFill ? max(scaleX, scaleY) : min(scaleX, scaleY)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)

        // Convert AppKit bottom-left coordinates (+Y up) to top-left SwiftUI canvas coordinates (+Y down).
        let widgetTopLeftInCanvas = CGPoint(
            x: widgetFrame.minX - canvasBounds.minX,
            y: canvasBounds.maxY - widgetFrame.maxY
        )
        let imageOriginInCanvas = CGPoint(
            x: (canvasBounds.width - drawSize.width) / 2.0,
            y: (canvasBounds.height - drawSize.height) / 2.0
        )
        let originInWidget = CGPoint(
            x: imageOriginInCanvas.x - widgetTopLeftInCanvas.x,
            y: imageOriginInCanvas.y - widgetTopLeftInCanvas.y
        )

        let rawUV = CGRect(
            x: (widgetTopLeftInCanvas.x - imageOriginInCanvas.x) / drawSize.width,
            y: (widgetTopLeftInCanvas.y - imageOriginInCanvas.y) / drawSize.height,
            width: widgetFrame.width / drawSize.width,
            height: widgetFrame.height / drawSize.height
        )
        let unitSquare = CGRect(x: 0, y: 0, width: 1, height: 1)
        let clampedUV = rawUV.intersects(unitSquare) ? rawUV.intersection(unitSquare) : .zero
        let pixelRect = CGRect(
            x: clampedUV.minX * imageSize.width,
            y: clampedUV.minY * imageSize.height,
            width: clampedUV.width * imageSize.width,
            height: clampedUV.height * imageSize.height
        )

        return DesktopPanoramaSlice(
            imageDrawSize: drawSize,
            imageOriginInWidget: originInWidget,
            normalizedCropRect: clampedUV,
            pixelCropRect: pixelRect
        )
    }
}
