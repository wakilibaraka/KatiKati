import XCTest
@testable import KatiKati

final class PDFReducePlanTests: XCTestCase {

    func testQualityClampsToLegibleRange() {
        XCTAssertEqual(PDFReducePlan.quality(0.6), 0.6)
        XCTAssertEqual(PDFReducePlan.quality(0.05), 0.2)
        XCTAssertEqual(PDFReducePlan.quality(2), 0.9)
        XCTAssertEqual(PDFReducePlan.quality(.nan), PDFReducePlan.defaultQuality)
    }

    func testRenderedSizeKeepsAspectAndClamps() {
        let full = PDFReducePlan.renderedSize(width: 600, height: 800, scale: 1)
        XCTAssertEqual(full.width, 600)
        XCTAssertEqual(full.height, 800)
        let half = PDFReducePlan.renderedSize(width: 600, height: 800, scale: 0.5)
        XCTAssertEqual(half.width, 300)
        XCTAssertEqual(half.height, 400)
        let floored = PDFReducePlan.renderedSize(width: 600, height: 800, scale: -3)
        XCTAssertEqual(floored.width, 60, "scale floors at 10 %")
        let tiny = PDFReducePlan.renderedSize(width: 1, height: 1, scale: 0.1)
        XCTAssertEqual(tiny.width, 1)
        XCTAssertEqual(tiny.height, 1)
    }
}

/// 55c: the image reduce numbers.
final class ImageReducePlanTests: XCTestCase {
    func testQualityClampsToLegibleRange() {
        XCTAssertEqual(ImageReducePlan.quality(0.6), 0.6)
        XCTAssertEqual(ImageReducePlan.quality(0.01), 0.2)
        XCTAssertEqual(ImageReducePlan.quality(5), 0.9)
        XCTAssertEqual(ImageReducePlan.quality(.infinity), ImageReducePlan.defaultQuality)
    }

    func testPixelCapClampsAndRounds() {
        XCTAssertEqual(ImageReducePlan.maxPixelSize(longestEdge: 4000), 3000)
        XCTAssertEqual(ImageReducePlan.maxPixelSize(longestEdge: 1001, scale: 0.5), 501)
        XCTAssertEqual(ImageReducePlan.maxPixelSize(longestEdge: 4000, scale: 0), 400, "scale floors at 10 %")
        XCTAssertEqual(ImageReducePlan.maxPixelSize(longestEdge: 1, scale: 0.1), 1)
        XCTAssertEqual(ImageReducePlan.maxPixelSize(longestEdge: 4000, scale: .nan), 3000)
    }
}

// MARK: - Phase 60: Shelf / File Tray Transforms (Slice D-TrayTransform)

final class FileTransformPlanTests: XCTestCase {
    func testBackgroundRemovalEligibilityAndDestination() {
        let png = URL(fileURLWithPath: "/Users/test/photo.png")
        let heic = URL(fileURLWithPath: "/Users/test/portrait.HEIC")
        let pdf = URL(fileURLWithPath: "/Users/test/document.pdf")

        XCTAssertTrue(FileTransformPlan.canRemoveBackground(for: png))
        XCTAssertTrue(FileTransformPlan.canRemoveBackground(for: heic))
        XCTAssertFalse(FileTransformPlan.canRemoveBackground(for: pdf))

        let noBg = FileTransformPlan.noBackgroundDestination(for: png)
        XCTAssertEqual(noBg.path, "/Users/test/photo_nobg.png")
    }

    func testZipDestination() {
        let single = [URL(fileURLWithPath: "/Users/test/report.docx")]
        XCTAssertEqual(FileTransformPlan.zipDestination(for: single)?.path, "/Users/test/report.zip")

        let multiple = [
            URL(fileURLWithPath: "/Users/test/img1.png"),
            URL(fileURLWithPath: "/Users/test/img2.png")
        ]
        XCTAssertEqual(FileTransformPlan.zipDestination(for: multiple)?.path, "/Users/test/Archive.zip")

        XCTAssertNil(FileTransformPlan.zipDestination(for: []))
    }

    func testImageConversionDestination() {
        let img = URL(fileURLWithPath: "/Users/test/graphic.png")
        XCTAssertEqual(FileTransformPlan.convertedDestination(for: img, format: .webp).path, "/Users/test/graphic.webp")
        XCTAssertEqual(FileTransformPlan.convertedDestination(for: img, format: .jpeg).path, "/Users/test/graphic.jpeg")
        XCTAssertEqual(ImageTargetFormat.webp.uniformTypeIdentifier, "org.webmproject.webp")
    }

    func testCombinedPDFDestination() {
        let single = [URL(fileURLWithPath: "/Users/test/page1.png")]
        XCTAssertEqual(FileTransformPlan.combinedPDFDestination(for: single)?.path, "/Users/test/page1_combined.pdf")

        let multi = [
            URL(fileURLWithPath: "/Users/test/page1.png"),
            URL(fileURLWithPath: "/Users/test/page2.png")
        ]
        XCTAssertEqual(FileTransformPlan.combinedPDFDestination(for: multi)?.path, "/Users/test/Combined.pdf")
        XCTAssertNil(FileTransformPlan.combinedPDFDestination(for: []))
    }
}
