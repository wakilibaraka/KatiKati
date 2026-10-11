import XCTest
@testable import KatiKati

final class WeatherEffectsTests: XCTestCase {
    func testEveryConditionHasAPlanAndStormsFlash() {
        for c in WeatherCondition.allCases {
            for night in [false, true] { XCTAssertFalse(WeatherEffectPlan.plan(condition: c, isNight: night).isStatic, "\(c) night=\(night)") }
        }
        XCTAssertTrue(WeatherEffectPlan.plan(condition: .thunderstorm, isNight: false).thunder)
        XCTAssertGreaterThan(WeatherEffectPlan.plan(condition: .showers, isNight: false).rainDrops,
                             WeatherEffectPlan.plan(condition: .drizzle, isNight: false).rainDrops)
        XCTAssertGreaterThan(WeatherEffectPlan.plan(condition: .clear, isNight: true).stars, 0)
        XCTAssertTrue(WeatherEffectPlan.plan(condition: .clear, isNight: false).sunGlow)
        XCTAssertEqual(WeatherEffectPlan.plan(condition: .clear, isNight: true).rainDrops, 0)
    }

    func testDeterministicAndBounded() {
        XCTAssertEqual(WeatherEffects.rain(count: 50, at: 3.7), WeatherEffects.rain(count: 50, at: 3.7))
        for t in stride(from: 0.0, through: 120.0, by: 7.3) {
            for d in WeatherEffects.rain(count: 120, at: t) { XCTAssertTrue((0..<1).contains(d.x) && (0..<1).contains(d.y)) }
            for f in WeatherEffects.snow(count: 80, at: t) { XCTAssertTrue((0..<1).contains(f.x) && (0..<1).contains(f.y)) }
            for c in WeatherEffects.clouds(count: 6, at: t) { XCTAssertTrue((-0.3...1.3).contains(c.x)) }
            for s in WeatherEffects.stars(count: 40, at: t) { XCTAssertTrue((0...1).contains(s.alpha) && s.y < 0.75) }
        }
    }

    func testMotionAdvancesAndWraps() {
        let a = WeatherEffects.rain(count: 10, at: 0), b = WeatherEffects.rain(count: 10, at: 0.1)
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(zip(a, b).allSatisfy { $0.0.y != $0.1.y })
        let c0 = WeatherEffects.clouds(count: 3, at: 0), c1 = WeatherEffects.clouds(count: 3, at: 10)
        XCTAssertTrue(zip(c0, c1).contains { $0.1.x != $0.0.x }, "clouds drift")
        // A full wrap period returns every cloud to the same place.
        let speed0 = 0.012 + WeatherEffects.unit(0, 2) * 0.02
        XCTAssertEqual(WeatherEffects.clouds(count: 1, at: 1 / speed0)[0].x, WeatherEffects.clouds(count: 1, at: 0)[0].x, accuracy: 1e-6)
    }

    func testFlashIsBriefAndOccursInManyBlocks() {
        var lit = 0, total = 0
        for i in 0..<6000 {
            let f = WeatherEffects.flash(at: Double(i) * 0.01)
            XCTAssertTrue((0...1).contains(f))
            total += 1; if f > 0 { lit += 1 }
        }
        XCTAssertGreaterThan(lit, 0)
        XCTAssertLessThan(Double(lit) / Double(total), 0.15, "flashes are brief")
        XCTAssertEqual(WeatherEffects.pulse(at: 0), 0.5, accuracy: 1e-9)
    }
}
