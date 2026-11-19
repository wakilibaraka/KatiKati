import CoreGraphics
import XCTest

final class DesktopPanoramaTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func testScreenSizedImageFlipsAppKitYToTopLeftUVsAndAlignsCorners() throws {
        let imageSize = CGSize(width: 1920, height: 1080)
        // Top-left quadrant in AppKit coords (+Y up): y in [540, 1080].
        let topLeftWidget = CGRect(x: 0, y: 540, width: 480, height: 540)
        let tlSlice = try XCTUnwrap(DesktopPanoramaEngine.slice(
            widgetFrame: topLeftWidget, canvasBounds: screen, imageSize: imageSize
        ))
        XCTAssertEqual(tlSlice.imageOriginInWidget, .zero)
        XCTAssertEqual(tlSlice.normalizedCropRect, CGRect(x: 0, y: 0, width: 0.25, height: 0.5))

        // Bottom-right quadrant in AppKit coords: x in [960, 1920], y in [0, 270].
        let bottomRightWidget = CGRect(x: 960, y: 0, width: 960, height: 270)
        let brSlice = try XCTUnwrap(DesktopPanoramaEngine.slice(
            widgetFrame: bottomRightWidget, canvasBounds: screen, imageSize: imageSize
        ))
        XCTAssertEqual(brSlice.imageOriginInWidget.x, -960, accuracy: 0.001)
        XCTAssertEqual(brSlice.imageOriginInWidget.y, -810, accuracy: 0.001)
        XCTAssertEqual(brSlice.normalizedCropRect, CGRect(x: 0.5, y: 0.75, width: 0.5, height: 0.25))
    }

    func testUltraWideAspectFillVsAspectFit() throws {
        // 21:9 image on 16:9 canvas.
        let ultraWide = CGSize(width: 2520, height: 1080)
        let fullCanvas = screen
        let fill = try XCTUnwrap(DesktopPanoramaEngine.slice(
            widgetFrame: fullCanvas, canvasBounds: screen, imageSize: ultraWide, scaleMode: .aspectFill
        ))
        XCTAssertEqual(fill.imageDrawSize, CGSize(width: 2520, height: 1080))
        XCTAssertEqual(fill.imageOriginInWidget.x, -300, accuracy: 0.001)

        let fit = try XCTUnwrap(DesktopPanoramaEngine.slice(
            widgetFrame: fullCanvas, canvasBounds: screen, imageSize: ultraWide, scaleMode: .aspectFit
        ))
        XCTAssertLessThan(fit.imageDrawSize.height, 1080)
        XCTAssertEqual(fit.imageDrawSize.width, 1920, accuracy: 0.01)
    }

    func testAdjacentWidgetsShareExactUVSeam() throws {
        let imageSize = CGSize(width: 3840, height: 2160)
        let left = CGRect(x: 200, y: 300, width: 300, height: 280)
        let right = CGRect(x: 500, y: 300, width: 300, height: 280)
        let leftSlice = try XCTUnwrap(DesktopPanoramaEngine.slice(
            widgetFrame: left, canvasBounds: screen, imageSize: imageSize
        ))
        let rightSlice = try XCTUnwrap(DesktopPanoramaEngine.slice(
            widgetFrame: right, canvasBounds: screen, imageSize: imageSize
        ))
        XCTAssertEqual(leftSlice.normalizedCropRect.maxX, rightSlice.normalizedCropRect.minX, accuracy: 0.0001)
        XCTAssertEqual(leftSlice.normalizedCropRect.minY, rightSlice.normalizedCropRect.minY, accuracy: 0.0001)
    }

    func testZeroDimensionsReturnNil() {
        XCTAssertNil(DesktopPanoramaEngine.slice(widgetFrame: .zero, canvasBounds: screen, imageSize: CGSize(width: 100, height: 100)))
        XCTAssertNil(DesktopPanoramaEngine.slice(widgetFrame: CGRect(x: 0, y: 0, width: 100, height: 100), canvasBounds: .zero, imageSize: CGSize(width: 100, height: 100)))
        XCTAssertNil(DesktopPanoramaEngine.slice(widgetFrame: CGRect(x: 0, y: 0, width: 100, height: 100), canvasBounds: screen, imageSize: .zero))
    }
}
