import AppKit
import SwiftUI

// Phase 5i — the glance page: hero scene, next-hours strip and one Hourly | Daily | Details panel.
// Never scrolls, every datum has a single home, and the whole pane is one sky split into tiles.

private enum GlanceSegment: CaseIterable { case hourly, daily, details }
private enum HourlySeries: CaseIterable { case precipitation, humidity, wind, sky }

struct WeatherGlanceView: View {
    let env: TileEnv
    @ObservedObject var service: WeatherService
    let state: WeatherState
    let detail: WeatherDetail
    let units: Units
    let width: CGFloat
    let height: CGFloat
    let animate: Bool
    let heroStyle: WeatherHeroStyle

    @State private var segment: GlanceSegment = .hourly
    private let gap = WidgetMetrics.gap

    var body: some View {
        let tint = SkyTint.tint(condition: state.conditionFamily, isNight: state.isNight)
        let heroH: CGFloat = heroStyle == .scene ? 262 : 214
        let stripH: CGFloat = 92, segH: CGFloat = 36
        let panelH = max(220, height - heroH - stripH - segH - 3 * gap)
        VStack(spacing: gap) {
            hero(tint: tint, height: heroH).widgetEntrance(0)
            HourStrip(env: env.sky(tint, at: 0.30), hours: Array(detail.hourly.prefix(6)), units: units, width: width, height: stripH).widgetEntrance(1)
            segmentControl(env.sky(tint, at: 0.52), height: segH).widgetEntrance(2)
            panel(env.sky(tint, at: 0.78), height: panelH).widgetEntrance(3)
        }
        .frame(width: width, height: height, alignment: .top)
    }

    // MARK: Hero

    @ViewBuilder private func hero(tint: SkyTint, height: CGFloat) -> some View {
        switch heroStyle {
        case .scene: SceneHero(env: env, service: service, state: state, detail: detail, units: units, tint: tint, width: width, height: height, animate: animate)
        case .classic: HeroTile(env: env, service: service, state: state, units: units, width: width, height: height, animate: animate)
        }
    }

    // MARK: Segment control

    private func segmentControl(_ e: TileEnv, height: CGFloat) -> some View {
        HStack(spacing: 4) {
            ForEach(GlanceSegment.allCases, id: \.self) { s in
                Button { segment = s } label: {
                    Group {
                        switch s { case .hourly: Text("Hourly"); case .daily: Text("Daily"); case .details: Text("Details") }
                    }
                    .font(.system(size: 12, weight: .bold)).frame(maxWidth: .infinity).frame(height: height - 8)
                    .background(Capsule().fill(segment == s ? e.text.opacity(0.18) : .clear))
                }.buttonStyle(.plain)
            }
        }
        .foregroundColor(e.text)
        .padding(4)
        .frame(width: width, height: height)
        .tileSurface(e, radius: height / 2)
    }

    // MARK: Panel

    @ViewBuilder private func panel(_ e: TileEnv, height: CGFloat) -> some View {
        Group {
            switch segment {
            case .hourly: HourlySegment(env: e, detail: detail, units: units)
            case .daily: DailySegment(env: e, detail: detail, units: units, height: height, currentCelsius: state.temperatureCelsius)
            case .details: DetailGrid(env: e, detail: detail, units: units)
            }
        }
        .foregroundColor(e.text)
        .padding(14)
        .frame(width: width, height: height, alignment: .top)
        .tileSurface(e)
    }
}

// MARK: - Scene hero

struct SceneHero: View {
    let env: TileEnv
    @ObservedObject var service: WeatherService
    let state: WeatherState
    let detail: WeatherDetail
    let units: Units
    let tint: SkyTint
    let width: CGFloat
    let height: CGFloat
    let animate: Bool
    @State private var searching = false
    @State private var showingWarnings = false

    var body: some View {
        let ink = tint.prefersDarkText ? Color(white: 0.10) : Color.white
        let warnings = WeatherWarningEngine.warnings(for: detail, thresholds: WeatherPrefs.thresholds())
        ZStack(alignment: .top) {
            MountainScene(tint: tint, condition: state.conditionFamily, isNight: state.isNight)
            WeatherEffectsView(plan: WeatherEffectPlan.plan(condition: state.conditionFamily, isNight: state.isNight), animate: animate, cloudOpacity: 0.45)
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    if !service.savedCities.cities.isEmpty {
                        Button { service.step(by: -1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain)
                    }
                    Text(verbatim: state.cityName).font(.system(size: 14, weight: .bold)).lineLimit(1)
                    if !service.savedCities.cities.isEmpty {
                        Button { service.step(by: 1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain)
                    }
                    Spacer()
                    if let top = warnings.first {
                        Button { showingWarnings.toggle() } label: {
                            HStack(spacing: 4) { Image(systemName: top.kind.symbolName); weatherWarningTitle(top.kind) }
                                .font(.system(size: 11, weight: .bold)).padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(top.severity == .severe ? Color.red.opacity(0.85) : Color.orange.opacity(0.85)))
                                .foregroundColor(.white)
                        }.buttonStyle(.plain)
                        .popover(isPresented: $showingWarnings) {
                            WarningsTile(env: env, warnings: warnings, units: units, width: 280)
                        }
                    }
                    Button { searching.toggle() } label: { Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .semibold)) }
                        .buttonStyle(.plain)
                        .popover(isPresented: $searching) { CitySearchPopover(service: service, close: { searching = false }) }
                }
                Text(verbatim: units.t(state.temperatureCelsius))
                    .font(.system(size: 78, weight: .light, design: .rounded)).minimumScaleFactor(0.6).padding(.top, 6)
                Text(state.conditionText).font(.system(size: 16, weight: .semibold))
                HStack(spacing: 6) {
                    Text("Feels Like"); Text(verbatim: units.t(detail.apparent))
                    Text(verbatim: "·")
                    Text(verbatim: "↑ \(units.t(state.highCelsius))  ↓ \(units.t(state.lowCelsius))")
                }.font(.system(size: 12, weight: .semibold)).opacity(0.92)
            }
            .foregroundColor(ink)
            .shadow(color: .black.opacity(tint.prefersDarkText ? 0 : 0.25), radius: 3, y: 1)
            .padding(14)
        }
        .frame(width: width, height: height)
        .tileSurface(env.sky(tint, at: 0.5), radius: WidgetMetrics.radius)
        .clipShape(RoundedRectangle(cornerRadius: WidgetMetrics.radius, style: .continuous))
    }
}

/// Layered mountain/horizon scene: sky gradient, sun or moon, three ridges, horizon haze.
struct MountainScene: View {
    let tint: SkyTint
    let condition: WeatherCondition
    let isNight: Bool

    var body: some View {
        Canvas { gc, size in
            let w = size.width, h = size.height
            func col(_ c: TileRGB, _ a: Double = 1) -> Color { Color(red: c.r, green: c.g, blue: c.b).opacity(a) }
            gc.fill(Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(Gradient(colors: [col(tint.top), col(tint.bottom)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))

            // Sun / moon sitting low behind the main peak.
            let center = CGPoint(x: w * 0.5, y: h * 0.60), r = h * 0.10
            let veiled = condition == .cloudy || condition == .fog || condition == .rain || condition == .showers || condition == .drizzle || condition == .thunderstorm
            let discAlpha = veiled ? 0.35 : 1.0
            if isNight {
                gc.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)), with: .color(Color(red: 0.97, green: 0.96, blue: 0.88).opacity(discAlpha)))
                let cut = CGRect(x: center.x - r + r * 0.55, y: center.y - r - r * 0.18, width: 2 * r, height: 2 * r)
                gc.fill(Path(ellipseIn: cut), with: .color(col(tint.mix(0.55))))
            } else {
                gc.fill(Path(ellipseIn: CGRect(x: center.x - r * 2.2, y: center.y - r * 2.2, width: r * 4.4, height: r * 4.4)),
                        with: .radialGradient(Gradient(colors: [Color.white.opacity(0.45 * discAlpha), .clear]), center: center, startRadius: r * 0.5, endRadius: r * 2.2))
                gc.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)), with: .color(Color(red: 1, green: 0.95, blue: 0.72).opacity(discAlpha)))
            }

            // Ridges, far → near.
            let band = h * 0.42
            for layer in 0..<3 {
                let base = h * (0.66 + 0.09 * Double(layer))
                var p = Path()
                var edge = Path()
                p.move(to: CGPoint(x: 0, y: h))
                var x = 0.0
                while x <= w + 4 {
                    let pt = CGPoint(x: x, y: base + band * 0.35 - band * SceneGeometry.ridge(x: x / w, layer: layer))
                    p.addLine(to: pt)
                    x == 0 ? edge.move(to: pt) : edge.addLine(to: pt)
                    x += 4
                }
                p.addLine(to: CGPoint(x: w, y: h)); p.closeSubpath()
                let c = tint.ridges[layer]
                let light = TileRGB(r: min(1, c.r + 0.22), g: min(1, c.g + 0.22), b: min(1, c.b + 0.22))
                gc.fill(p, with: .linearGradient(Gradient(colors: [col(light), col(c)]), startPoint: CGPoint(x: 0, y: base - band * 0.6), endPoint: CGPoint(x: 0, y: h)))
                gc.stroke(edge, with: .color(Color.white.opacity(0.30 - 0.08 * Double(layer))), lineWidth: 1.3)
            }
            // Horizon haze.
            gc.fill(Path(CGRect(x: 0, y: h * 0.62, width: w, height: h * 0.14)),
                    with: .linearGradient(Gradient(colors: [.clear, Color.white.opacity(isNight ? 0.04 : 0.12), .clear]), startPoint: CGPoint(x: 0, y: h * 0.62), endPoint: CGPoint(x: 0, y: h * 0.76)))
        }
    }
}

// MARK: - Next hours strip

private struct HourStrip: View {
    let env: TileEnv
    let hours: [WeatherHourPoint]
    let units: Units
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(hours.enumerated()), id: \.element.id) { i, h in
                VStack(spacing: 3) {
                    Text(verbatim: units.t(h.temperature)).font(.system(size: 14, weight: .bold))
                    Image(systemName: WeatherResponseParsing.mapWeatherCode(code: h.code).symbol)
                        .symbolRenderingMode(.multicolor).font(.system(size: 20)).frame(height: 24)
                    if i == 0 { Text("Now").font(.system(size: 10, weight: .semibold)).foregroundColor(env.secondary) }
                    else { Text(verbatim: h.hourLabel).font(.system(size: 10, weight: .medium)).foregroundColor(env.secondary) }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundColor(env.text)
        .frame(width: width, height: height)
        .tileSurface(env)
    }
}

// MARK: - Segments

private struct HourlySegment: View {
    let env: TileEnv
    let detail: WeatherDetail
    let units: Units
    @State private var series: HourlySeries = .precipitation

    var body: some View {
        let hours = detail.hourly
        let temps = hours.map { units.temp.convert($0.temperature) }, feels = hours.map { units.temp.convert($0.apparent) }
        let lo = (temps + feels).min() ?? 0, hi = (temps + feels).max() ?? 1
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Temperature").font(.system(size: 13, weight: .bold))
                Spacer()
                Text(verbatim: "↑ \(Int(hi.rounded()))°  ↓ \(Int(lo.rounded()))°").font(.system(size: 11, weight: .bold)).foregroundColor(env.secondary)
            }
            Canvas { gc, size in
                let span = max(hi - lo, 1)
                func pt(_ i: Int, _ v: Double) -> CGPoint {
                    CGPoint(x: size.width * Double(i) / Double(max(hours.count - 1, 1)), y: size.height * (1 - 0.1 - 0.8 * (v - lo) / span))
                }
                func line(_ v: [Double]) -> Path { var p = Path(); for (i, x) in v.enumerated() { i == 0 ? p.move(to: pt(i, x)) : p.addLine(to: pt(i, x)) }; return p }
                var fill = line(temps); fill.addLine(to: CGPoint(x: size.width, y: size.height)); fill.addLine(to: CGPoint(x: 0, y: size.height)); fill.closeSubpath()
                gc.fill(fill, with: .linearGradient(Gradient(colors: [env.text.opacity(0.28), env.text.opacity(0)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                gc.stroke(line(feels), with: .color(env.text.opacity(0.7)), style: StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
                gc.stroke(line(temps), with: .color(env.text), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
            }
            .frame(maxHeight: .infinity)
            timeAxis(hours)
            Divider().opacity(0.3)
            HStack(spacing: 6) {
                ForEach(HourlySeries.allCases, id: \.self) { s in chip(s) }
            }
            seriesChart(hours).frame(height: 84)
            timeAxis(hours)
        }
    }

    private func timeAxis(_ hours: [WeatherHourPoint]) -> some View {
        HStack {
            ForEach([0, 12, 24, 36, max(hours.count - 1, 0)], id: \.self) { i in
                Text(verbatim: hours.indices.contains(i) ? hours[i].hourLabel : "").font(.system(size: 9)).foregroundColor(env.secondary)
                if i != max(hours.count - 1, 0) { Spacer(minLength: 0) }
            }
        }
    }

    private func chip(_ s: HourlySeries) -> some View {
        let now = detail.hourly.first
        let (icon, value): (String, String) = {
            switch s {
            case .precipitation: return ("drop.fill", String(format: "%.1f", detail.precipitation))
            case .humidity: return ("humidity.fill", "\(Int(detail.humidity))%")
            case .wind: return ("wind", "\(Int(units.wind.convert(kmh: detail.windSpeed)))")
            case .sky: return ("cloud.fill", "\(Int(now?.cloudCover ?? detail.cloudCover))%")
            }
        }()
        return Button { series = s } label: {
            HStack(spacing: 3) { Image(systemName: icon); Text(verbatim: value) }
                .font(.system(size: 11, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 5)
                .background(Capsule().fill(series == s ? env.text.opacity(0.2) : env.hairline))
        }.buttonStyle(.plain)
    }

    private func seriesChart(_ hours: [WeatherHourPoint]) -> some View {
        Canvas { gc, size in
            let values: [Double] = hours.map {
                switch series {
                case .precipitation: return $0.precipitation + $0.snowfall
                case .humidity: return $0.humidity
                case .wind: return units.wind.convert(kmh: $0.windSpeed)
                case .sky: return $0.cloudCover
                }
            }
            let maxV = max(values.max() ?? 1, series == .precipitation ? 1 : 10)
            let bw = size.width / Double(max(values.count, 1))
            if series == .precipitation {
                for (i, v) in values.enumerated() {
                    let hgt = size.height * v / maxV
                    gc.fill(Path(roundedRect: CGRect(x: Double(i) * bw + 0.5, y: size.height - hgt, width: max(bw - 1, 1), height: hgt), cornerRadius: 1.5), with: .color(env.text.opacity(0.85)))
                }
            } else {
                var p = Path()
                for (i, v) in values.enumerated() {
                    let pt = CGPoint(x: size.width * Double(i) / Double(max(values.count - 1, 1)), y: size.height * (1 - 0.9 * v / maxV))
                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
                var area = p; area.addLine(to: CGPoint(x: size.width, y: size.height)); area.addLine(to: CGPoint(x: 0, y: size.height)); area.closeSubpath()
                gc.fill(area, with: .color(env.text.opacity(0.18)))
                gc.stroke(p, with: .color(env.text), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

private struct DailySegment: View {
    let env: TileEnv
    let detail: WeatherDetail
    let units: Units
    let height: CGFloat
    let currentCelsius: Double
    @State private var page = 0

    var body: some View {
        let rowH = DailyRangeRows.rowHeight
        let size = max(4, Int((height - 28 - 30 - 30) / rowH))
        let pages = max(1, (detail.daily.count + size - 1) / size)
        let rows = Array(detail.daily.dropFirst(page * size).prefix(size))
        VStack(spacing: 4) {
            HStack {
                arrow("chevron.left", enabled: page > 0) { page -= 1 }
                Spacer()
                Text(verbatim: "\(detail.daily.count)").font(.system(size: 13, weight: .bold)).opacity(0)
                Spacer()
                arrow("chevron.right", enabled: page < pages - 1) { page += 1 }
            }
            .overlay(Text("Daily Forecast").font(.system(size: 13, weight: .bold)))
            DailyRangeRows(env: env, days: rows, units: units, currentCelsius: page == 0 ? currentCelsius : nil)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Image(systemName: "drop.fill"); Text(verbatim: String(format: "%.1f mm", detail.daily.map(\.precipSum).reduce(0, +)))
                Image(systemName: "snowflake"); Text(verbatim: String(format: "%.1f cm", detail.daily.map(\.snowSum).reduce(0, +)))
                Spacer()
            }.font(.system(size: 11, weight: .bold)).foregroundColor(env.secondary)
        }
    }

    private func arrow(_ name: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 12, weight: .bold)).frame(width: 28, height: 24)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(env.hairline))
        }.buttonStyle(.plain).opacity(enabled ? 1 : 0.35).disabled(!enabled)
    }
}
