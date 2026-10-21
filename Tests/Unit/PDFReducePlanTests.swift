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
