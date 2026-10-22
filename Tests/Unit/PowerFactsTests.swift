import XCTest

// 59c — the battery's non-percentage readings. The rules that matter: macOS's 65535 / -1 "still
// calculating" sentinels are nil rather than a 65535-minute estimate, and a discharging amperage
// arrives as an unsigned wrap that must not read as sixteen gigawatts.

final class PowerFactsTests: XCTestCase {
    func testTimeToEmptyAndFullRejectSentinels() {
        XCTAssertEqual(PowerFacts.secondsRemaining(powerSource: ["Time to Empty": 31], isCharging: false), 1860)
        XCTAssertEqual(PowerFacts.secondsRemaining(powerSource: ["Time to Full Charge": 45], isCharging: true), 2700)
        XCTAssertNil(PowerFacts.secondsRemaining(powerSource: ["Time to Empty": 65535], isCharging: false))
        XCTAssertNil(PowerFacts.secondsRemaining(powerSource: ["Time to Empty": -1], isCharging: false))
        XCTAssertNil(PowerFacts.secondsRemaining(powerSource: ["Time to Empty": 0], isCharging: false))
        XCTAssertNil(PowerFacts.secondsRemaining(powerSource: [:], isCharging: false))
        // Each state reads its own key only: "Time to Empty" says nothing about a charge in progress.
        XCTAssertNil(PowerFacts.secondsRemaining(powerSource: ["Time to Empty": 31], isCharging: true))
    }

    func testWattsReadMilliAmpsAndSurviveTheSignedWrap() {
        XCTAssertEqual(PowerFacts.watts(amperage: 3735, millivolts: 12510) ?? 0, 46.7, accuracy: 0.05)
        XCTAssertNil(PowerFacts.watts(amperage: -1200, millivolts: 12000), "on battery nothing flows in")
        let wrapped = Int64(bitPattern: UInt64.max - 1199) // -1200 as the unsigned 64-bit wrap
        XCTAssertNil(PowerFacts.watts(amperage: wrapped, millivolts: 12000),
                     "the wrap must not read as billions of watts")
        XCTAssertNil(PowerFacts.watts(amperage: 500, millivolts: 0))
        XCTAssertNil(PowerFacts.watts(amperage: nil, millivolts: 12000))
    }

    func testDurationAndSummaryHideMissingFields() {
        XCTAssertEqual(PowerFacts.durationText(5040), "1h 24m")
        XCTAssertEqual(PowerFacts.durationText(59), "1m")
        XCTAssertNil(PowerFacts.durationText(nil))
        XCTAssertNil(PowerFacts.durationText(0))

        let charging = PowerFacts(secondsRemaining: 5040, watts: 18.2, thermal: .fair,
                                  isLowPowerMode: true, isCharging: true)
        XCTAssertEqual(charging.summary, "1h 24m to full · 18.2 W · Fair · Low Power Mode")
        let onBattery = PowerFacts(secondsRemaining: 1860, thermal: .nominal, isCharging: false)
        XCTAssertEqual(onBattery.summary, "31m left", "a nominal thermal state is not worth a word")
        XCTAssertNil(PowerFacts.empty.summary, "a Mac with no battery shows nothing, not zeros")
    }

    func testThermalStateMapping() {
        XCTAssertEqual(PowerThermal(.nominal), .nominal)
        XCTAssertEqual(PowerThermal(.fair), .fair)
        XCTAssertEqual(PowerThermal(.serious), .serious)
        XCTAssertEqual(PowerThermal(.critical), .critical)
        XCTAssertEqual(PowerThermal(.serious).name, "Serious")
    }
}
