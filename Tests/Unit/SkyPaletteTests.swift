import XCTest
@testable import KatiKati

final class SkyPaletteTests: XCTestCase {
    func testAllThirtyLooksAreDistinctAndInRange() {
        var seen = Set<String>()
        for phase in SolarPhase.allCases {
            for sky in WallpaperSky.allCases {
                let s = SkyPalette.stops(phase: phase, sky: sky)
                for c in [s.top, s.bottom] {
                    XCTAssertTrue((0...1).contains(c.r) && (0...1).contains(c.g) && (0...1).contains(c.b))
                }
                seen.insert("\(s.top)\(s.bottom)")
            }
        }
        XCTAssertEqual(seen.count, 30)
    }

    func testClearKeepsBaseAndStormIsDarkerThanClearByDay() {
        let clear = SkyPalette.stops(phase: .day, sky: .clear)
        XCTAssertEqual(clear.top, SkyRGB(r: 48.0 / 255, g: 140.0 / 255, b: 236.0 / 255))
        let storm = SkyPalette.stops(phase: .day, sky: .storm)
        XCTAssertLessThan(storm.top.b, clear.top.b)
    }

    func testSunTimesParse() throws {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let t = try XCTUnwrap(SunTimes.parse(sunrise: "2026-10-11T07:12", sunset: "2026-10-11T18:22", calendar: cal))
        XCTAssertEqual(cal.component(.hour, from: t.sunrise!), 7)
        XCTAssertEqual(cal.component(.minute, from: t.sunset!), 22)
        XCTAssertNil(SunTimes.parse(sunrise: nil, sunset: "2026-10-11T18:22", calendar: cal))
        XCTAssertNil(SunTimes.parse(sunrise: "garbage", sunset: "x", calendar: cal))
    }
}
