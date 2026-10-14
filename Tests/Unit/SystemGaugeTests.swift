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

        XCTAssertEqual(DockIconShape.squircle.title, "Standard Squircle")
        XCTAssertEqual(DockIconShape.circle.title, "Circular Icons")
    }
}
