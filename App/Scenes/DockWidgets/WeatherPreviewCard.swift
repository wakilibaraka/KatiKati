import SwiftUI

/// Hover preview for the weather widget: Now (condition, feels-like, low–high bar, detail grid), Hourly and Daily.
struct WeatherPreviewCard: View {
    @EnvironmentObject private var weatherService: WeatherService
    @AppStorage(WeatherUnits.temperatureKey) private var temperatureUnit: TemperatureUnit = .celsius
    @AppStorage(WeatherUnits.windKey) private var windUnit: WindSpeedUnit = .kmh
    @State private var tab = Tab.now

    private enum Tab: CaseIterable { case now, hourly, daily }

    var body: some View {
        let state = weatherService.currentState
        DockPreviewCard {
            VStack(alignment: .leading, spacing: 12) {
                header(state)
                tabs
                if let detail = state.detail {
                    switch tab {
                    case .now: nowGrid(state, detail)
                    case .hourly: hourly(detail)
                    case .daily: daily(state, detail)
                    }
                } else {
                    Text("No forecast yet").dockCaption()
                }
            }
        }
    }

    private func t(_ celsius: Double) -> String { WeatherUnits.degrees(celsius, temperatureUnit) }

    private func header(_ state: WeatherState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: state.cityName).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(verbatim: t(state.temperatureCelsius)).font(.system(size: 40, weight: .light)).monospacedDigit()
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Image(systemName: state.glyphName).symbolRenderingMode(.multicolor).font(.system(size: 26))
                    Text(verbatim: state.conditionText).dockCaption()
                    if let feels = state.detail?.apparent {
                        Text(verbatim: String(localized: "Feels like") + " " + t(feels)).dockCaption()
                    }
                }
            }
            HStack(spacing: 8) {
                Text(verbatim: t(state.lowCelsius)).dockCaption()
                RangeBar(low: state.lowCelsius, high: state.highCelsius, current: state.temperatureCelsius)
                    .frame(height: 5)
                Text(verbatim: t(state.highCelsius)).dockCaption()
            }
        }
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { item in
                Button { tab = item } label: {
                    label(item)
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                        .background(Capsule().fill(tab == item ? Color.white.opacity(0.16) : .clear))
                        .opacity(tab == item ? 1 : DockWidgetStyle.secondaryOpacity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private func label(_ tab: Tab) -> Text {
        switch tab {
        case .now: return Text("Now")
        case .hourly: return Text("Hourly")
        case .daily: return Text("Daily")
        }
    }

    private func nowGrid(_ state: WeatherState, _ d: WeatherDetail) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            cell(Text("Humidity"), "\(Int(d.humidity.rounded()))%")
            cell(Text("Wind"), WeatherUnits.wind(d.windSpeed, windUnit))
            cell(Text("Direction"), WeatherUnits.compass(d.windDirection))
            cell(Text("UV Index"), "\(Int(d.uvIndex.rounded()))")
            cell(Text("Pressure"), "\(Int(d.pressure.rounded())) hPa")
            cell(Text("Sunrise"), Self.clock(d.sunrise))
        }
    }

    private func cell(_ title: Text, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            title.dockCaption()
            Text(verbatim: value).font(.system(size: 13, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private func hourly(_ d: WeatherDetail) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(Array(d.hourly.prefix(12).enumerated()), id: \.element.id) { index, hour in
                    VStack(spacing: 5) {
                        Group { if index == 0 { Text("Now") } else { Text(verbatim: hour.hourLabel) } }.dockCaption()
                        Image(systemName: WeatherResponseParsing.mapWeatherCode(code: hour.code).symbol)
                            .symbolRenderingMode(.multicolor).font(.system(size: 16))
                        Text(verbatim: t(hour.temperature)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                        Text(verbatim: hour.precipProbability >= 10 ? "\(Int(hour.precipProbability))%" : " ")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(.cyan)
                    }
                }
            }
        }
    }

    private func daily(_ state: WeatherState, _ d: WeatherDetail) -> some View {
        let days = Array(d.daily.prefix(5))
        let weekLow = days.map(\.low).min() ?? 0, weekHigh = days.map(\.high).max() ?? 1
        return VStack(spacing: 7) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                HStack(spacing: 8) {
                    Group { if index == 0 { Text("Today") } else { Text(verbatim: DailyTile.weekday(day.date)) } }
                        .font(.system(size: 12, weight: .medium)).frame(width: 42, alignment: .leading)
                    Image(systemName: WeatherResponseParsing.mapWeatherCode(code: day.code).symbol)
                        .symbolRenderingMode(.multicolor).font(.system(size: 14)).frame(width: 22)
                    Text(verbatim: t(day.low)).dockCaption().frame(width: 30, alignment: .trailing)
                    RangeBar(low: day.low, high: day.high, current: index == 0 ? state.temperatureCelsius : nil,
                             weekLow: weekLow, weekHigh: weekHigh)
                        .frame(height: 5)
                    Text(verbatim: t(day.high)).font(.system(size: 12, weight: .semibold)).monospacedDigit().frame(width: 30, alignment: .trailing)
                }
            }
        }
    }

    private static func clock(_ iso: String?) -> String { String(iso?.split(separator: "T").last ?? "--:--") }
}

/// Low–high capsule, optionally with a "now" dot. Without a week range it fills the bar (today's own range).
private struct RangeBar: View {
    let low: Double
    let high: Double
    var current: Double?
    var weekLow: Double?
    var weekHigh: Double?

    var body: some View {
        let range = TemperatureRange(low: low, high: high, weekLow: weekLow ?? low, weekHigh: weekHigh ?? high)
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule()
                    .fill(LinearGradient(colors: [.cyan, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, w * (range.end - range.start))).offset(x: w * range.start)
                if let current {
                    Circle().fill(.white).frame(width: 7, height: 7)
                        .offset(x: w * range.marker(current: current, low: low, high: high) - 3.5)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}
