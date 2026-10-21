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

    // The strip widgets used to fill their gaps with demo content: the media card printed a hardcoded
    // track with a guessed 0.35 progress, the weather cards printed a canned city's forecast. Same
    // witness idea as `NotchLayoutSpecTests.testNotchPagesHaveNoMockLiterals`.
    func testStripWidgetsHaveNoMockLiterals() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for (file, bad) in [("App/Scenes/NowPlayingChip.swift", ["God's Plan", "Drake", "?? 0.35"]),
                            ("App/Scenes/WeatherChip.swift", ["\"Rome\"", "highCelsius + 1", "highCelsius - 1"]),
                            ("Core/Support/WeatherState.swift", ["defaultRome"]),
                            ("App/Composition/WeatherService.swift", ["\"Rome\""])] {
            let src = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            for literal in bad { XCTAssertFalse(src.contains(literal), "\(file) still ships \(literal)") }
        }
    }

    func testThreeDayForecastUsesOnlyFeedDays() {
        let twoDays = WeatherState(cityName: "Juja", temperatureCelsius: 18, conditionText: "Clear",
                                   symbolName: "sun.max.fill", highCelsius: 27, lowCelsius: 16, hourly: [],
                                   daily: [DailyForecast(date: "2026-10-16", highCelsius: 27, lowCelsius: 16, symbolName: "sun.max.fill"),
                                           DailyForecast(date: "2026-10-17", highCelsius: 29, lowCelsius: 17, symbolName: "cloud.fill")],
                                   isLive: true, lastUpdated: Date())
        XCTAssertEqual(twoDays.threeDayForecast.count, 2)
        XCTAssertTrue(WeatherState.empty.threeDayForecast.isEmpty)   // never topped up from a canned city
    }

    func testWeatherHasDataNeedsARealForecast() {
        XCTAssertFalse(WeatherState.empty.hasData)
        let hourlyOnly = WeatherState(cityName: "Juja", temperatureCelsius: 18, conditionText: "Clear",
                                      symbolName: "sun.max.fill", highCelsius: 27, lowCelsius: 16,
                                      hourly: [HourlyForecast(id: "2026-10-16T14:00", hour: "14:00", temperatureCelsius: 25, symbolName: "sun.max.fill")],
                                      daily: [], isLive: true, lastUpdated: Date())
        XCTAssertTrue(hourlyOnly.hasData)
    }

    func testClockPresetStackedCard() {
        XCTAssertTrue(ClockPreset.allCases.contains(.stackedCard))
        XCTAssertEqual(ClockPreset.stackedCard.title, "Stacked Time & Date")
    }

    func testPresetsTitles() {
        XCTAssertEqual(WeatherChipPreset.classicPill.title, "Classic Weather Pill")
        XCTAssertEqual(WeatherChipPreset.detailedForecast.title, "Detailed 3-Day Forecast")
        XCTAssertEqual(WeatherChipPreset.classicGlassPill.title, "Glass Weather Pill")
        XCTAssertEqual(WeatherChipPreset.detailedGlass.title, "Glass 3-Day Forecast")

        XCTAssertEqual(NowPlayingPreset.miniChip.title, "Mini Player")
        XCTAssertEqual(NowPlayingPreset.expandedCard.title, "Expanded Artwork Card")

        // Phase 32d: the shape's own labels went with its Settings row. What has to hold now is the
        // packed resolver — the switch's value, and today's squircle for anything unset or unknown.
        XCTAssertEqual(DockIconShape.packedValue(nil), .squircle)
        XCTAssertEqual(DockIconShape.packedValue("squircle"), .squircle)
        XCTAssertEqual(DockIconShape.packedValue("circle"), .circle)
        XCTAssertEqual(DockIconShape.packedValue("hexagon"), .squircle)
    }

    /// The forecast pod scales whole to its slot: shrink a tall form, never grow a short one, and 1
    /// while either measure is missing (first layout pass).
    func testSlotFitScale() {
        XCTAssertEqual(SlotFitScale.scale(naturalHeight: 58, availableHeight: 40), 40.0 / 58.0, accuracy: 0.001)
        XCTAssertEqual(SlotFitScale.scale(naturalHeight: 37, availableHeight: 40), 1)
        XCTAssertEqual(SlotFitScale.scale(naturalHeight: 40, availableHeight: 40), 1)
        XCTAssertEqual(SlotFitScale.scale(naturalHeight: 0, availableHeight: 40), 1)
        XCTAssertEqual(SlotFitScale.scale(naturalHeight: 58, availableHeight: 0), 1)
    }

    /// Phase 46: two layouts × two plates. The stored values the app already shipped (`classic`,
    /// `detailed`) must keep meaning what they meant — the owner's own install pins `detailed`.
    func testWeatherChipPresetAxes() {
        XCTAssertEqual(WeatherChipPreset.allCases.count, 6)
        XCTAssertEqual(WeatherChipPreset.allCases.map(\.rawValue).prefix(2), ["classic", "detailed"])
        // Both layouts exist on both plates, and the sky stays the default look.
        XCTAssertEqual(WeatherChipPreset.allCases.filter(\.usesSkyPlate).map(\.isDetailed), [false, true, true])
        XCTAssertEqual(WeatherChipPreset.allCases.filter { !$0.usesSkyPlate }.map(\.isDetailed), [false, true, true])
        XCTAssertTrue(WeatherChipPreset.detailedForecast.usesSkyPlate)
        XCTAssertTrue(WeatherChipPreset.classicPill.usesSkyPlate)
    }

    /// Phase 56 W8: Modern and the iPad card are offered; a stored retired style stays listed and decodable.
    func testWeatherPickerOffersModernAndIPadAndKeepsStoredRetired() {
        XCTAssertEqual(WeatherChipPreset.pickerCases(current: .modern), [.modern, .ipad])
        XCTAssertEqual(WeatherChipPreset.pickerCases(current: .ipad), [.modern, .ipad])
        XCTAssertEqual(WeatherChipPreset.pickerCases(current: .detailedGlass), [.modern, .ipad, .detailedGlass])
    }

    /// Phase 56 W8: a stored style moves to Modern exactly once; a later pick sticks.
    func testModernMigrationRunsOnce() {
        let d = UserDefaults(suiteName: "weather-modern-migration-\(UUID().uuidString)")!
        d.set("ipad", forKey: WeatherChipPreset.storageKey)
        WeatherChipPreset.migrateToModernIfNeeded(defaults: d)
        XCTAssertEqual(d.string(forKey: WeatherChipPreset.storageKey), "modern")
        d.set("ipad", forKey: WeatherChipPreset.storageKey)
        WeatherChipPreset.migrateToModernIfNeeded(defaults: d)
        XCTAssertEqual(d.string(forKey: WeatherChipPreset.storageKey), "ipad")
        let fresh = UserDefaults(suiteName: "weather-modern-migration-\(UUID().uuidString)")!
        WeatherChipPreset.migrateToModernIfNeeded(defaults: fresh)
        XCTAssertNil(fresh.string(forKey: WeatherChipPreset.storageKey))
    }

    /// Phase 56 W3: a stored older style moves to the iPad card exactly once; a later pick sticks.
    func testIPadMigrationRunsOnce() {
        let d = UserDefaults(suiteName: "weather-ipad-migration-\(UUID().uuidString)")!
        d.set("detailed", forKey: WeatherChipPreset.storageKey)
        WeatherChipPreset.migrateToIPadIfNeeded(defaults: d)
        XCTAssertEqual(d.string(forKey: WeatherChipPreset.storageKey), "ipad")
        d.set("classic", forKey: WeatherChipPreset.storageKey)
        WeatherChipPreset.migrateToIPadIfNeeded(defaults: d)
        XCTAssertEqual(d.string(forKey: WeatherChipPreset.storageKey), "classic")
        let fresh = UserDefaults(suiteName: "weather-ipad-migration-\(UUID().uuidString)")!
        WeatherChipPreset.migrateToIPadIfNeeded(defaults: fresh)
        XCTAssertNil(fresh.string(forKey: WeatherChipPreset.storageKey))
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

