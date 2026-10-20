import XCTest
@testable import KatiKati

final class ArtworkAccentTests: XCTestCase {
    func testNoHueMeansNoAccent() {
        XCTAssertNil(ArtworkAccent.reduce(red: 0.02, green: 0.02, blue: 0.03), "near-black")
        XCTAssertNil(ArtworkAccent.reduce(red: 0.98, green: 0.98, blue: 0.97), "near-white")
        XCTAssertNil(ArtworkAccent.reduce(red: 0.5, green: 0.5, blue: 0.5), "grey")
    }

    func testDullColourIsLiftedIntoRange() throws {
        let a = try XCTUnwrap(ArtworkAccent.reduce(red: 0.20, green: 0.15, blue: 0.14))
        let hi = max(a.red, a.green, a.blue), lo = min(a.red, a.green, a.blue)
        XCTAssertGreaterThanOrEqual(hi, ArtworkAccent.brightnessRange.lowerBound - 1e-9)
        XCTAssertGreaterThanOrEqual((hi - lo) / hi, ArtworkAccent.saturationRange.lowerBound - 1e-9)
        XCTAssertEqual(a.red, hi, "stays red-dominant")
    }

    func testGarishColourIsPulledDown() throws {
        let a = try XCTUnwrap(ArtworkAccent.reduce(red: 0, green: 1, blue: 0))
        let hi = max(a.red, a.green, a.blue), lo = min(a.red, a.green, a.blue)
        XCTAssertLessThanOrEqual(hi, ArtworkAccent.brightnessRange.upperBound + 1e-9)
        XCTAssertLessThanOrEqual((hi - lo) / hi, ArtworkAccent.saturationRange.upperBound + 1e-9)
        XCTAssertEqual(a.green, hi, "stays green-dominant")
    }

    func testHuePreservedAcrossSectors() throws {
        for (rgb, dominant) in [((0.8, 0.3, 0.2), 0), ((0.3, 0.8, 0.2), 1), ((0.2, 0.3, 0.8), 2), ((0.8, 0.2, 0.7), 0)] {
            let a = try XCTUnwrap(ArtworkAccent.reduce(red: rgb.0, green: rgb.1, blue: rgb.2))
            let channels = [a.red, a.green, a.blue]
            XCTAssertEqual(channels.firstIndex(of: channels.max()!), dominant)
        }
    }

    func testOutOfRangeInputIsClamped() {
        XCTAssertNotNil(ArtworkAccent.reduce(red: 2, green: -1, blue: 0.1))
    }
}
