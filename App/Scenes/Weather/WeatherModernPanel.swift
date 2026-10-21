import SwiftUI

/// Phase 56 W9: the Modern weather panel. One flat graphite plate split by hairlines: reading, the next
/// 24 hours as a line (hover scrubs the reading), UV / Wind / Sun, then monochrome range-bar days.
/// Never scrolls: the day list takes whatever height is left (3 to 7 rows).
struct WeatherModernPanel: View {
    @ObservedObject var service: WeatherService
    let state: WeatherState
    let detail: WeatherDetail
    let units: Units
    let width: CGFloat
    let height: CGFloat

    @AppStorage(WeatherUnits.temperatureKey) private var tempUnit: TemperatureUnit = .celsius
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrub: Int?
    @State private var searching = false

    private static let ink = Color(white: 0.96)
    private static let env = TileEnv(palette: .classic, isDark: true)
    private let rowH: CGFloat = 28

    private var accent: Color {
        let c = WeatherModernSpec.accent(condition: state.conditionFamily, isNight: state.isNight)
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    var body: some View {
        let notice = WeatherNotice(isLive: state.isLive, staleness: WeatherStaleness(lastUpdated: state.lastUpdated))
        let plateH = height - (notice == nil ? 0 : 28 + WidgetMetrics.gap)
        let rows = max(3, min(7, Int((plateH - 32 - 372) / rowH)))
        VStack(spacing: WidgetMetrics.gap) {
            if let notice { WeatherNoticeBar(env: Self.env, notice: notice, updated: state.lastUpdated, service: service, width: width) }
            VStack(alignment: .leading, spacing: 14) {
                header
                rule
                hourly(Array(detail.hourly.prefix(24)))
                rule
                tiles
                rule
                days(rows)
            }
            .padding(16)
            .frame(width: width, height: plateH, alignment: .top)
            .foregroundStyle(Self.ink)
            .background(RoundedRectangle(cornerRadius: WidgetMetrics.radius, style: .continuous).fill(Color(white: 0.085)))
            .overlay(RoundedRectangle(cornerRadius: WidgetMetrics.radius, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: WidgetMetrics.radius, style: .continuous))
            .widgetEntrance(0)
        }
        .frame(width: width, height: height, alignment: .top)
    }

    private var rule: some View { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }

    private func caption(_ t: Text) -> some View { t.font(.system(size: 11)).opacity(0.58) }

    // MARK: Reading

    private var header: some View {
        let hour = scrub.flatMap { detail.hourly.indices.contains($0) ? detail.hourly[$0] : nil }
        let shownC = hour?.temperature ?? state.temperatureCelsius
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 7, height: 7)
                if !service.savedCities.cities.isEmpty {
                    Button { service.step(by: -1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain)
                }
                Text(verbatim: state.cityName).font(.system(size: 13)).opacity(0.7).lineLimit(1)
                if !service.savedCities.cities.isEmpty {
                    Button { service.step(by: 1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain)
                }
                Spacer()
                Button { searching.toggle() } label: { Image(systemName: "magnifyingglass") }.buttonStyle(.plain)
                    .popover(isPresented: $searching) { CitySearchPopover(service: service, close: { searching = false }) }
            }
            .font(.system(size: 12))
            Button { tempUnit = tempUnit == .celsius ? .fahrenheit : .celsius } label: {
                Text(verbatim: units.t(shownC)).font(.system(size: 64, weight: .light)).kerning(-2).monospacedDigit()
                    .contentTransition(.numericText(value: shownC))
            }
            .buttonStyle(.plain)
            .help(Text("Switch between °C and °F"))
            .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: shownC)
            if let hour {
                Text(verbatim: "\(hour.hourLabel) · \(WeatherResponseParsing.mapWeatherCode(code: hour.code).text)").font(.system(size: 13))
            } else {
                Text(verbatim: "\(state.conditionText) · ↑ \(units.t(state.highCelsius))  ↓ \(units.t(state.lowCelsius))").font(.system(size: 13))
            }
        }
        .frame(height: 100, alignment: .top)
    }

    // MARK: Next 24 hours

    private func hourly(_ hours: [WeatherHourPoint]) -> some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                HourLine(fractions: WeatherModernSpec.fractions(hours.map(\.temperature)), accent: accent, dot: scrub ?? 0)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let p):
                            let i = Int((p.x / max(geo.size.width, 1) * Double(hours.count - 1)).rounded())
                            scrub = i <= 0 ? nil : min(i, hours.count - 1)
                        case .ended: scrub = nil
                        }
                    }
            }
            .frame(height: 52)
            HStack {
                ForEach([0, 6, 12, 18, 23].filter { hours.indices.contains($0) }, id: \.self) { i in
                    if i == 0 { Text("Now") } else { Text(verbatim: hours[i].hourLabel) }
                    if i != 23 { Spacer(minLength: 0) }
                }
            }
            .font(.system(size: 11)).monospacedDigit().opacity(0.58)
        }
        .frame(height: 76)
    }

    // MARK: UV / Wind / Sun

    private var tiles: some View {
        let level = UVLevel(index: detail.uvIndex)
        return HStack(alignment: .top, spacing: 12) {
            tile(Text("UV Index"), value: String(format: "%.0f", detail.uvIndex), note: level.name) {
                GeometryReader { geo in
                    Capsule().fill(Color.white.opacity(0.12)).overlay(alignment: .leading) {
                        Circle().fill(accent).frame(width: 7, height: 7).offset(x: (geo.size.width - 7) * UVLevel.fraction(index: detail.uvIndex))
                    }
                }.frame(height: 4)
            }
            tile(Text("Wind"), value: WeatherUnits.wind(detail.windSpeed, units.wind), note: Text(verbatim: WeatherUnits.compass(detail.windDirection))) { EmptyView() }
            tile(Text("Sunset"), value: clock(detail.sunset), note: Text(verbatim: clock(detail.sunrise))) { EmptyView() }
        }
        .frame(height: 62, alignment: .top)
    }

    private func tile<Extra: View>(_ title: Text, value: String, note: Text, @ViewBuilder extra: () -> Extra) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            caption(title)
            Text(verbatim: value).font(.system(size: 20, weight: .light)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            note.font(.system(size: 11)).opacity(0.58).lineLimit(1)
            extra()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func clock(_ iso: String?) -> String { String(iso?.split(separator: "T").last ?? "--:--") }

    // MARK: Days

    private func days(_ count: Int) -> some View {
        let list = Array(detail.daily.prefix(count))
        let weekLow = list.map(\.low).min() ?? 0, weekHigh = list.map(\.high).max() ?? 1
        return VStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element.id) { i, d in
                let range = TemperatureRange(low: d.low, high: d.high, weekLow: weekLow, weekHigh: weekHigh)
                HStack(spacing: 10) {
                    Group { if i == 0 { Text("Today") } else { Text(verbatim: DailyTile.weekday(d.date)) } }
                        .font(.system(size: 13)).frame(width: 44, alignment: .leading)
                    Text(verbatim: units.t(d.low)).font(.system(size: 13)).monospacedDigit().opacity(0.58).frame(width: 36, alignment: .trailing)
                    GeometryReader { geo in
                        let w = geo.size.width
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.10))
                            Capsule().fill(Color.white.opacity(0.75)).frame(width: max(5, w * (range.end - range.start))).offset(x: w * range.start)
                            if i == 0 {
                                Circle().fill(accent).frame(width: 7, height: 7)
                                    .offset(x: w * range.marker(current: state.temperatureCelsius, low: d.low, high: d.high) - 3.5)
                            }
                        }.frame(maxHeight: .infinity)
                    }.frame(height: 4)
                    Text(verbatim: units.t(d.high)).font(.system(size: 13)).monospacedDigit().frame(width: 36, alignment: .trailing)
                }
                .frame(height: rowH)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(i == 0 ? String(localized: "Today") : DailyTile.weekday(d.date)), \(units.t(d.low)) – \(units.t(d.high))"))
            }
        }
    }
}
