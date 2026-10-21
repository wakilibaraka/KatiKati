import SwiftUI

/// Phase 56 W12: Glance, the full-screen weather page. One screen, no tabs, no scrolling: the reading and
/// condition over a flat-vector landscape, the next 24 hours as a curve with rain bars (hover scrubs the
/// reading), seven glass day columns, and six detail tiles. `WeatherGlanceSpec.columns` picks the arrangement.
struct WeatherFullScreenView: View {
    @ObservedObject var service: WeatherService
    let state: WeatherState
    let detail: WeatherDetail
    let units: Units
    let width: CGFloat
    let height: CGFloat
    let animate: Bool

    @AppStorage(WeatherUnits.temperatureKey) private var tempUnit: TemperatureUnit = .celsius
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrub: Int?
    @State private var searching = false

    private var glass: some ShapeStyle { Color.white.opacity(0.16) }
    private var accent: Color {
        let c = WeatherGlanceSpec.palette(condition: state.conditionFamily, isNight: state.isNight).accent
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    var body: some View {
        let cols = WeatherGlanceSpec.columns(forWidth: width)
        let wide = cols > 1
        ZStack {
            WeatherScenery(condition: state.conditionFamily, isNight: state.isNight, animate: animate)
            VStack(spacing: 14) {
                topBar
                if wide {
                    HStack(alignment: .top, spacing: 18) {
                        hero(wide: true).frame(maxWidth: .infinity, alignment: .leading)
                        VStack(spacing: 12) { hourly; days }.frame(width: width * (cols == 3 ? 0.5 : 0.52))
                    }
                } else {
                    hero(wide: false)
                    hourly
                    days
                }
                Spacer(minLength: 0)
                tiles(columns: wide ? 6 : 3)
            }
            .padding(wide ? 28 : 18)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.18), radius: 6, y: 1)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Top bar and hero

    private var topBar: some View {
        HStack(spacing: 10) {
            if !service.savedCities.cities.isEmpty {
                Button { service.step(by: -1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain)
            }
            Text(verbatim: state.cityName).font(.system(size: 17, weight: .medium)).lineLimit(1)
            if !service.savedCities.cities.isEmpty {
                Button { service.step(by: 1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain)
            }
            Button { searching.toggle() } label: { Image(systemName: "magnifyingglass") }.buttonStyle(.plain)
                .popover(isPresented: $searching) { CitySearchPopover(service: service, close: { searching = false }) }
            Spacer()
            if let notice = WeatherNotice(isLive: state.isLive, staleness: WeatherStaleness(lastUpdated: state.lastUpdated)) {
                Button { Task { await service.refresh() } } label: {
                    Group { notice == .offline ? Text("Offline") : Text("Updating") }
                        .font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(glass))
                }.buttonStyle(.plain)
            }
            Button { WidgetPanelController.weather.close() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).keyboardShortcut(.cancelAction).help(Text("Close"))
        }
        .font(.system(size: 14, weight: .medium))
    }

    private func hero(wide: Bool) -> some View {
        let hour = scrub.flatMap { detail.hourly.indices.contains($0) ? detail.hourly[$0] : nil }
        let shownC = hour?.temperature ?? state.temperatureCelsius
        let numeral = wide ? min(220, height * 0.27) : 96
        let family = hour.map { WeatherResponseParsing.mapWeatherCode(code: $0.code).text } ?? state.conditionText
        return VStack(alignment: .leading, spacing: 4) {
            Button { tempUnit = tempUnit == .celsius ? .fahrenheit : .celsius } label: {
                Text(verbatim: units.t(shownC)).font(.system(size: numeral, weight: .ultraLight)).kerning(-numeral / 18).monospacedDigit()
                    .contentTransition(.numericText(value: shownC)).lineLimit(1).minimumScaleFactor(0.5)
            }
            .buttonStyle(.plain).help(Text("Switch between °C and °F"))
            .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: shownC)
            Text(verbatim: family).font(.system(size: wide ? 34 : 24, weight: .semibold))
            Text(verbatim: hour.map { "\($0.hourLabel) · \(units.t($0.apparent))" }
                 ?? "↑ \(units.t(state.highCelsius))  ↓ \(units.t(state.lowCelsius))  ·  \(units.t(detail.apparent))")
                .font(.system(size: 15)).opacity(0.9)
        }
    }

    // MARK: 24 hours

    private var hourly: some View {
        let hours = Array(detail.hourly.prefix(24))
        let fr = WeatherModernSpec.fractions(hours.map(\.temperature))
        return VStack(alignment: .leading, spacing: 4) {
            caption(Text("Next 24 hours"))
            GeometryReader { geo in
                Canvas { ctx, size in
                    let n = max(hours.count - 1, 1)
                    func x(_ i: Int) -> CGFloat { 8 + CGFloat(i) * (size.width - 16) / CGFloat(n) }
                    for (i, h) in hours.enumerated() where h.precipProbability > 5 {
                        let bh = CGFloat(h.precipProbability / 100) * size.height * 0.45
                        ctx.fill(Path(roundedRect: CGRect(x: x(i) - 3, y: size.height - bh, width: 6, height: bh), cornerRadius: 3), with: .color(.white.opacity(0.35)))
                    }
                    let pts = fr.enumerated().map { CGPoint(x: x($0), y: 14 + (1 - CGFloat($1)) * (size.height * 0.55 - 14)) }
                    var line = Path(); line.addLines(pts)
                    ctx.stroke(line, with: .color(.white), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    let d = pts[min(scrub ?? 0, pts.count - 1)]
                    ctx.fill(Path(ellipseIn: CGRect(x: d.x - 6, y: d.y - 6, width: 12, height: 12)), with: .color(accent))
                }
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
            .frame(height: 96)
            HStack {
                ForEach([0, 6, 12, 18, 23].filter { hours.indices.contains($0) }, id: \.self) { i in
                    if i == 0 { Text("Now") } else { Text(verbatim: hours[i].hourLabel) }
                    if i != 23 { Spacer(minLength: 0) }
                }
            }
            .font(.system(size: 11)).monospacedDigit().opacity(0.8)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(glass))
    }

    // MARK: 7 days

    private var days: some View {
        HStack(spacing: 6) {
            ForEach(Array(detail.daily.prefix(7).enumerated()), id: \.element.id) { i, d in
                VStack(spacing: 6) {
                    Group { if i == 0 { Text("Today") } else { Text(verbatim: DailyTile.weekday(d.date)) } }.font(.system(size: 12)).opacity(0.85)
                    Image(systemName: WeatherResponseParsing.mapWeatherCode(code: d.code).symbol)
                        .symbolRenderingMode(.multicolor).font(.system(size: 20)).frame(height: 24)
                    Text(verbatim: units.t(d.high)).font(.system(size: 17, weight: .semibold)).monospacedDigit()
                    Text(verbatim: units.t(d.low)).font(.system(size: 13)).monospacedDigit().opacity(0.7)
                }
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(glass))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(i == 0 ? String(localized: "Today") : DailyTile.weekday(d.date)), \(units.t(d.low)) – \(units.t(d.high))"))
            }
        }
    }

    // MARK: Tiles

    private func tiles(columns: Int) -> some View {
        let sun = WeatherDetailBands.sunFraction(sunrise: detail.sunrise, sunset: detail.sunset, nowMinutes: nowMinutes)
        let items: [(Text, String, Text, Double?)] = [
            (Text("UV Index"), String(format: "%.0f", detail.uvIndex), UVLevel(index: detail.uvIndex).name, UVLevel.fraction(index: detail.uvIndex)),
            (Text("Wind"), WeatherUnits.wind(detail.windSpeed, units.wind), Text(verbatim: WeatherUnits.compass(detail.windDirection)), nil),
            (Text("Sunset"), clock(detail.sunset), Text(verbatim: clock(detail.sunrise)), sun),
            (Text("Humidity"), "\(Int(detail.humidity.rounded()))%", Text(verbatim: units.t(detail.dewPoint)), detail.humidity / 100),
            (Text("Pressure"), "\(Int(detail.pressure.rounded())) hPa", Text(verbatim: ""), nil),
            (Text("Visibility"), String(format: "%.0f km", detail.visibilityMeters / 1000), Text(verbatim: String(format: "%.1f mm", detail.precipitation)), nil),
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
            ForEach(items.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 3) {
                    caption(items[i].0)
                    Text(verbatim: items[i].1).font(.system(size: 22, weight: .light)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    items[i].2.font(.system(size: 12)).opacity(0.8).lineLimit(1)
                    if let f = items[i].3 {
                        Capsule().fill(Color.white.opacity(0.25)).frame(height: 4)
                            .overlay(alignment: .leading) { GeometryReader { g in Circle().fill(accent).frame(width: 8, height: 8).offset(x: (g.size.width - 8) * min(max(f, 0), 1), y: -2) } }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(glass))
            }
        }
    }

    private func caption(_ t: Text) -> some View { t.font(.system(size: 12)).opacity(0.85) }
    private func clock(_ iso: String?) -> String { String(iso?.split(separator: "T").last ?? "--:--") }
    private var nowMinutes: Int {
        // The first hourly point is the current hour in the location's own clock.
        WeatherDetailBands.minutes(detail.hourly.first?.time ?? "") ?? 12 * 60
    }
}

/// Glance while there is no forecast yet: the needs-location prompt or the loading skeleton, on the same sky.
struct WeatherFullScreenWaiting: View {
    @ObservedObject var service: WeatherService
    let state: WeatherState
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let env = TileEnv(palette: .classic, isDark: true)
        ZStack(alignment: .topTrailing) {
            WeatherScenery(condition: state.conditionFamily, isNight: state.isNight, animate: false)
            Group {
                if service.needsLocation { NeedsLocationTile(env: env, service: service, width: 340) }
                else { WeatherLoadingTile(env: env, width: 340) }
            }
            .frame(width: width, height: height)
            Button { WidgetPanelController.weather.close() } label: { Image(systemName: "xmark").foregroundStyle(.white) }
                .buttonStyle(.plain).keyboardShortcut(.cancelAction).padding(20).help(Text("Close"))
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
