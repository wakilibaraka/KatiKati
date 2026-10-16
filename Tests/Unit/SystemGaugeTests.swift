import XCTest
@testable import KatiKati

final class SystemGaugeTests: XCTestCase {
    func testSystemGaugeMetricsComputeNormal() {
        let metrics = SystemGaugeMetrics.compute(usedMemory: 8_000_000_000, totalMemory: 16_000_000_000, cpuUsage: 0.25)
        XCTAssertEqual(metrics.ramPercentage, 50)
        XCTAssertEqual(metrics.cpuPressure, 0.25)
        XCTAssertEqual(metrics.pressureLevel, .normal)
    }

    func testSystemGaugeMetricsWarningThreshold() {
        let metricsCPU = SystemGaugeMetrics.compute(usedMemory: 4_000_000_000, totalMemory: 16_000_000_000, cpuUsage: 0.65)
        XCTAssertEqual(metricsCPU.pressureLevel, .warning)

        let metricsRAM = SystemGaugeMetrics.compute(usedMemory: 13_000_000_000, totalMemory: 16_000_000_000, cpuUsage: 0.10)
        XCTAssertEqual(metricsRAM.ramPercentage, 81)
        XCTAssertEqual(metricsRAM.pressureLevel, .warning)
    }

    func testSystemGaugeMetricsCriticalThreshold() {
        let metricsCPU = SystemGaugeMetrics.compute(usedMemory: 4_000_000_000, totalMemory: 16_000_000_000, cpuUsage: 0.92)
        XCTAssertEqual(metricsCPU.pressureLevel, .critical)

        let metricsRAM = SystemGaugeMetrics.compute(usedMemory: 15_500_000_000, totalMemory: 16_000_000_000, cpuUsage: 0.10)
        XCTAssertEqual(metricsRAM.ramPercentage, 96)
        XCTAssertEqual(metricsRAM.pressureLevel, .critical)
    }

    func testSystemGaugeMetricsClampingAndZeroDivision() {
        let zeroTotal = SystemGaugeMetrics.compute(usedMemory: 100, totalMemory: 0, cpuUsage: -0.5)
        XCTAssertEqual(zeroTotal.ramPercentage, 0)
        XCTAssertEqual(zeroTotal.cpuPressure, 0.0)

        let overflow = SystemGaugeMetrics.compute(usedMemory: 200, totalMemory: 100, cpuUsage: 1.5)
        XCTAssertEqual(overflow.ramPercentage, 100)
        XCTAssertEqual(overflow.cpuPressure, 1.0)
    }

    func testWeatherStateDefaultRome() {
        let state = WeatherState.defaultRome
        XCTAssertEqual(state.cityName, "Rome")
        XCTAssertEqual(state.temperatureCelsius, 26)
        XCTAssertEqual(state.threeDayForecast.count, 3)
        XCTAssertEqual(state.threeDayForecast[0].date, "Thu")
        XCTAssertEqual(state.threeDayForecast[0].highCelsius, 30)
    }

    func testClockPresetStackedCard() {
        XCTAssertTrue(ClockPreset.allCases.contains(.stackedCard))
        XCTAssertEqual(ClockPreset.stackedCard.title, "Stacked Time & Date")
    }

    func testPresetsTitles() {
        XCTAssertEqual(WeatherChipPreset.classicPill.title, "Classic Weather Pill")
        XCTAssertEqual(WeatherChipPreset.detailedForecast.title, "Detailed 3-Day Forecast")

        XCTAssertEqual(NowPlayingPreset.miniChip.title, "Mini Player")
        XCTAssertEqual(NowPlayingPreset.expandedCard.title, "Expanded Artwork Card")

        // Phase 32d: the shape's own labels went with its Settings row. What has to hold now is the
        // packed resolver — the switch's value, and today's squircle for anything unset or unknown.
        XCTAssertEqual(DockIconShape.packedValue(nil), .squircle)
        XCTAssertEqual(DockIconShape.packedValue("squircle"), .squircle)
        XCTAssertEqual(DockIconShape.packedValue("circle"), .circle)
        XCTAssertEqual(DockIconShape.packedValue("hexagon"), .squircle)
    }

    func testWiFiVolumeDotsActiveCalculation() {
        // Muted should always be 0 active dots
        let mutedDots = VolumeStatus(level: 0.8, isMuted: true).isMuted ? 0 : Int(round(0.8 * 12.0))
        XCTAssertEqual(mutedDots, 0)

        // 0% volume -> 0 dots
        let zeroDots = Int(round(0.0 * 12.0))
        XCTAssertEqual(zeroDots, 0)

        // 50% volume -> 6 dots
        let halfDots = Int(round(0.5 * 12.0))
        XCTAssertEqual(halfDots, 6)

        // 75% volume -> 9 dots
        let threeQuarterDots = Int(round(0.75 * 12.0))
        XCTAssertEqual(threeQuarterDots, 9)

        // 100% volume -> 12 dots
        let fullDots = Int(round(1.0 * 12.0))
        XCTAssertEqual(fullDots, 12)
    }

    func testWiFiVolumeDotsGeometryContainment() {
        let radius: Double = 14.0
        for index in 0..<12 {
            let angle = -90.0 + Double(index) * 30.0
            let rad = angle * .pi / 180.0
            let x = radius * cos(rad)
            let y = radius * sin(rad)
            let distance = sqrt(x * x + y * y)

            // Ensure every dot is precisely at radius 14.0
            XCTAssertEqual(distance, radius, accuracy: 0.001)

            // Ensure dot is within the 40x40 frame (coordinates between -20 and +20)
            XCTAssertGreaterThanOrEqual(x, -20.0)
            XCTAssertLessThanOrEqual(x, 20.0)
            XCTAssertGreaterThanOrEqual(y, -20.0)
            XCTAssertLessThanOrEqual(y, 20.0)
        }
    }
}

