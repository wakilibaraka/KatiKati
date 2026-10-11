import AppKit
import SwiftUI

// Phase 5g-D/E/F — the weather tile stack (left side). Same solid-tile system, layouts and palette
// as the calendar; the hero tile carries the condition-driven animated background. Data comes from
// the shared `WeatherService` (Open-Meteo); warnings are derived from the forecast.

enum WeatherPanelHost {
    /// Set once by `AppDelegate` so the panel controller (which has no view-tree environment) can reach it.
    @MainActor static var service: WeatherService?
}

enum WeatherPrefs {
    static let animationsKey = "com.katikati.weather.animationsEnabled"

    static func thresholds() -> WeatherThresholds {
        UserDefaults.standard.data(forKey: WeatherThresholds.storageKey)
            .flatMap { try? JSONDecoder().decode(WeatherThresholds.self, from: $0) } ?? .default
    }
}

struct WeatherPanelView: View {
    let layout: CalendarPanelLayout
    let width: CGFloat
    let maxHeight: CGFloat
    let onHeight: (CGFloat) -> Void

    var body: some View {
        if let service = WeatherPanelHost.service {
            WeatherTiles(service: service, layout: layout, width: width, maxHeight: maxHeight, onHeight: onHeight)
        }
    }
}

private struct WeatherTiles: View {
    @ObservedObject var service: WeatherService
    let layout: CalendarPanelLayout
    let width: CGFloat
    let maxHeight: CGFloat
    let onHeight: (CGFloat) -> Void

    @AppStorage(TilePalette.storageKey) private var palette: TilePalette = .classic
    @AppStorage(WeatherUnits.temperatureKey) private var tempUnit: TemperatureUnit = .celsius
    @AppStorage(WeatherUnits.windKey) private var windUnit: WindSpeedUnit = .kmh
    @AppStorage(WeatherPrefs.animationsKey) private var animationsEnabled = true
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var panelState: WidgetPanelState

    private let gutter: CGFloat = 8
    private let gap: CGFloat = 10

    var body: some View {
        let env = TileEnv(palette: palette, isDark: colorScheme == .dark)
        let u = Units(temp: tempUnit, wind: windUnit)
        let state = service.currentState
        let animate = animationsEnabled && panelState.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let inner = width - 2 * gutter
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: gap) {
                if service.needsLocation && state.detail == nil {
                    NeedsLocationTile(env: env, service: service, width: inner)
                } else {
                    HeroTile(env: env, service: service, state: state, units: u, width: inner,
                             height: layout == .mac ? 214 : (layout == .ipad ? 236 : 262), animate: animate)
                        .widgetEntrance(0)
                    let warnings = state.detail.map { WeatherWarningEngine.warnings(for: $0, thresholds: WeatherPrefs.thresholds()) } ?? []
                    if !warnings.isEmpty { WarningsTile(env: env, warnings: warnings, units: u, width: inner).widgetEntrance(1) }
                    if let d = state.detail {
                        switch layout {
                        case .mac: macTiles(env: env, units: u, detail: d, inner: inner)
                        case .ipad: ipadTiles(env: env, units: u, detail: d, inner: inner)
                        case .tall: macTiles(env: env, units: u, detail: d, inner: inner)
                        }
                    }
                }
                Text(verbatim: "Open-Meteo.com").font(.system(size: 9, weight: .semibold)).foregroundColor(.white.opacity(0.8))
                    .shadow(color: .black.opacity(0.5), radius: 2)
            }
            .padding(gutter)
            .frame(width: width)
            .background(GeometryReader { Color.clear.preference(key: PanelHeightKey.self, value: $0.size.height) })
        }
        .onPreferenceChange(PanelHeightKey.self) { onHeight($0) }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { Task { await service.refresh() } }
    }

    private func macTiles(env: TileEnv, units: Units, detail: WeatherDetail, inner: CGFloat) -> some View {
        VStack(spacing: gap) {
            HourlyTile(env: env, detail: detail, units: units, width: inner).widgetEntrance(1)
            TrendTile(env: env, detail: detail, units: units, width: inner).widgetEntrance(2)
            DailyTile(env: env, detail: detail, units: units, width: inner, pageSize: 8).widgetEntrance(3)
            DetailsTile(env: env, detail: detail, units: units, width: inner, columns: 2).widgetEntrance(4)
        }
    }

    private func ipadTiles(env: TileEnv, units: Units, detail: WeatherDetail, inner: CGFloat) -> some View {
        let left = (inner - gap) * 0.58, right = inner - gap - left
        return VStack(spacing: gap) {
            HourlyTile(env: env, detail: detail, units: units, width: inner, columns: 12).widgetEntrance(1)
            HStack(alignment: .top, spacing: gap) {
                TrendTile(env: env, detail: detail, units: units, width: left)
                DailyTile(env: env, detail: detail, units: units, width: right, pageSize: 7)
            }.widgetEntrance(2)
            DetailsTile(env: env, detail: detail, units: units, width: inner, columns: 5).widgetEntrance(3)
        }
    }
}

struct Units { let temp: TemperatureUnit; let wind: WindSpeedUnit
    func t(_ c: Double) -> String { WeatherUnits.degrees(c, temp) }
}

// MARK: - Hero

private struct HeroTile: View {
    let env: TileEnv
    @ObservedObject var service: WeatherService
    let state: WeatherState
    let units: Units
    let width: CGFloat
    let height: CGFloat
    let animate: Bool
    @State private var searching = false

    var body: some View {
        let family = state.conditionFamily
        let (a, b) = WeatherArt.stops(condition: family, isNight: state.isNight)
        let plan = WeatherEffectPlan.plan(condition: family, isNight: state.isNight)
        let dark = plan.cloudDarkness * 0.45
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing)
            Color.black.opacity(dark)
            WeatherEffectsView(plan: plan, animate: animate)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if !service.savedCities.cities.isEmpty {
                        Button { service.step(by: -1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: state.cityName).font(.system(size: 17, weight: .bold)).lineLimit(1)
                        Text(state.conditionText).font(.system(size: 12, weight: .medium)).opacity(0.9).lineLimit(1)
                    }
                    if !service.savedCities.cities.isEmpty {
                        Button { service.step(by: 1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain)
                    }
                    Spacer()
                    Button { searching.toggle() } label: { Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .semibold)) }
                        .buttonStyle(.plain)
                        .popover(isPresented: $searching) { CitySearchPopover(service: service, close: { searching = false }) }
                }
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: units.t(state.temperatureCelsius))
                            .font(.system(size: 68, weight: .light, design: .rounded)).minimumScaleFactor(0.6)
                        HStack(spacing: 5) {
                            Text("Feels Like"); Text(verbatim: units.t(state.detail?.apparent ?? state.temperatureCelsius))
                        }.font(.system(size: 12, weight: .semibold))
                        Text(verbatim: "↑ \(units.t(state.highCelsius))   ↓ \(units.t(state.lowCelsius))")
                            .font(.system(size: 12, weight: .semibold)).opacity(0.9)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        WeatherIllustration(condition: family, isNight: state.isNight, size: 74)
                        if let d = state.detail {
                            HStack(spacing: 4) {
                                Image(systemName: "sunrise.fill"); Text(verbatim: clock(d.sunrise))
                                Image(systemName: "sunset.fill"); Text(verbatim: clock(d.sunset))
                            }.font(.system(size: 11, weight: .semibold)).opacity(0.95)
                        }
                    }
                }
            }
            .foregroundColor(.white)
            .padding(14)
        }
        .frame(width: width, height: height)
        .tileSurface(env)
        .environment(\.colorScheme, .dark)
    }

    private func clock(_ iso: String?) -> String { String(iso?.split(separator: "T").last ?? "--:--") }
}

/// Condition-driven animated background (rain, snow, thunder, clouds, stars, sun glow, fog).
struct WeatherEffectsView: View {
    let plan: WeatherEffectPlan
    let animate: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animate)) { ctx in
            let t = animate ? ctx.date.timeIntervalSinceReferenceDate : 12
            Canvas { gc, size in draw(&gc, size, t) }
        }
        .allowsHitTesting(false)
    }

    private func draw(_ gc: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let w = size.width, h = size.height
        if plan.sunGlow {
            let r = h * (0.55 + 0.08 * WeatherEffects.pulse(at: t))
            let c = CGPoint(x: w * 0.82, y: h * 0.18)
            gc.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                    with: .radialGradient(Gradient(colors: [Color.yellow.opacity(0.65), Color.orange.opacity(0.0)]),
                                          center: c, startRadius: 0, endRadius: r))
        }
        for s in WeatherEffects.stars(count: plan.stars, at: t) {
            gc.fill(Path(ellipseIn: CGRect(x: s.x * w, y: s.y * h, width: s.radius * 2, height: s.radius * 2)), with: .color(.white.opacity(s.alpha)))
        }
        let tint = 1 - plan.cloudDarkness * 0.55
        for c in WeatherEffects.clouds(count: plan.clouds, at: t) {
            let cw = w * 0.42 * c.scale, ch = cw * 0.38, x = c.x * w, y = c.y * h
            for (dx, dy, k) in [(0.0, 0.25, 0.9), (0.28, 0.0, 0.7), (0.55, 0.22, 0.8)] {
                gc.fill(Path(ellipseIn: CGRect(x: x + dx * cw, y: y + dy * ch, width: cw * k * 0.55, height: ch * k)),
                        with: .color(Color(white: tint).opacity(c.alpha * 0.55)))
            }
        }
        if plan.fog {
            for i in 0..<3 {
                let drift = (WeatherEffects.pulse(at: t + Double(i) * 3, period: 14) - 0.5) * w * 0.25
                gc.fill(Path(roundedRect: CGRect(x: -w * 0.1 + drift, y: h * (0.35 + 0.18 * Double(i)), width: w * 1.2, height: h * 0.14), cornerRadius: h * 0.07),
                        with: .color(.white.opacity(0.22)))
            }
        }
        for d in WeatherEffects.rain(count: plan.rainDrops, at: t) {
            var p = Path(); let x = d.x * w, y = d.y * h
            p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x - d.length * w * 0.12, y: y + d.length * h))
            gc.stroke(p, with: .color(.white.opacity(d.alpha)), lineWidth: 1.2)
        }
        for f in WeatherEffects.snow(count: plan.snowflakes, at: t) {
            gc.fill(Path(ellipseIn: CGRect(x: f.x * w, y: f.y * h, width: f.radius * 2, height: f.radius * 2)), with: .color(.white.opacity(f.alpha)))
        }
        if plan.thunder {
            let f = WeatherEffects.flash(at: t)
            if f > 0 { gc.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.45 * f))) }
        }
    }
}

// MARK: - Warnings

private struct WarningsTile: View {
    let env: TileEnv
    let warnings: [WeatherWarning]
    let units: Units
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(warnings) { w in
                HStack(spacing: 8) {
                    Image(systemName: w.kind.symbolName).font(.system(size: 16, weight: .bold)).foregroundColor(color(w.severity))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 0) {
                        title(w.kind).font(.system(size: 13, weight: .bold))
                        Text(verbatim: detail(w)).font(.system(size: 10, weight: .medium)).foregroundColor(env.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            Text("Forecast-based").font(.system(size: 9, weight: .semibold)).foregroundColor(env.secondary)
        }
        .foregroundColor(env.text)
        .padding(12)
        .frame(width: width, alignment: .leading)
        .tileSurface(env)
    }

    @ViewBuilder private func title(_ k: WeatherWarningKind) -> some View {
        switch k {
        case .heat: Text("Heat")
        case .freeze: Text("Freeze")
        case .heavyRain: Text("Heavy rain")
        case .snow: Text("Snow")
        case .wind: Text("Strong wind")
        case .thunderstorm: Text("Thunderstorms")
        case .uv: Text("High UV")
        }
    }

    private func detail(_ w: WeatherWarning) -> String {
        let value: String
        switch w.kind {
        case .heat, .freeze: value = units.t(w.peak)
        case .heavyRain: value = String(format: "%.1f mm/h", w.peak)
        case .snow: value = String(format: "%.0f cm", w.peak)
        case .wind: value = WeatherUnits.wind(w.peak, units.wind)
        case .thunderstorm: value = "\(Int(w.peak))%"
        case .uv: value = String(format: "%.0f", w.peak)
        }
        return "\(whenLabel(w.start)) · \(value)"
    }

    /// `2026-10-11T14:00` → "Sun 14:00"; `2026-10-12` → "Mon".
    private func whenLabel(_ iso: String) -> String {
        let parts = iso.split(separator: "T")
        let day = DailyTile.weekday(String(parts.first ?? ""))
        return parts.count > 1 ? "\(day) \(parts[1])" : day
    }

    private func color(_ s: WeatherWarningSeverity) -> Color {
        switch s { case .advisory: return .yellow; case .warning: return .orange; case .severe: return .red }
    }
}

// MARK: - Hourly

private enum HourlyMetric: CaseIterable { case sky, humidity, wind }

private struct HourlyTile: View {
    let env: TileEnv
    let detail: WeatherDetail
    let units: Units
    let width: CGFloat
    @State private var page = 0
    @State private var metric: HourlyMetric = .sky
    var columns = 6

    var body: some View {
        let pages = max(1, (detail.hourly.count + columns - 1) / columns)
        let slice = Array(detail.hourly.dropFirst(page * columns).prefix(columns))
        VStack(spacing: 8) {
            HStack {
                arrow("chevron.left", enabled: page > 0) { page -= 1 }
                Spacer()
                Text("Hourly Forecast").font(.system(size: 15, weight: .bold))
                Spacer()
                arrow("chevron.right", enabled: page < pages - 1) { page += 1 }
            }
            HStack(alignment: .top, spacing: 0) {
                ForEach(slice) { h in
                    VStack(spacing: 4) {
                        Text(verbatim: units.t(h.temperature)).font(.system(size: 13, weight: .bold))
                        Image(systemName: WeatherResponseParsing.mapWeatherCode(code: h.code).symbol)
                            .symbolRenderingMode(.multicolor).font(.system(size: 20)).frame(height: 24)
                        Text(verbatim: h.hourLabel).font(.system(size: 10, weight: .medium)).foregroundColor(env.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 6) {
                chip(.sky, "cloud.fill") { Text("Sky") }
                chip(.humidity, "drop.fill") { Text("Humidity") }
                chip(.wind, "wind") { Text("Wind") }
            }
            VStack(spacing: 6) {
                metricRow(slice, primary: true, icon: icons.0)
                metricRow(slice, primary: false, icon: icons.1)
            }
        }
        .foregroundColor(env.text)
        .padding(12)
        .frame(width: width)
        .tileSurface(env)
    }

    private var icons: (String, String) {
        switch metric {
        case .sky: return ("cloud.fill", "cloud.rain.fill")
        case .humidity: return ("drop.fill", "thermometer")
        case .wind: return ("wind", "tornado")
        }
    }

    private func metricRow(_ slice: [WeatherHourPoint], primary: Bool, icon: String) -> some View {
        HStack(spacing: 0) {
            Image(systemName: icon).font(.system(size: 10)).foregroundColor(env.secondary).frame(width: 16)
            ForEach(slice) { h in
                VStack(spacing: 0) {
                    Text(verbatim: value(h, primary: primary)).font(.system(size: 12, weight: .semibold)).minimumScaleFactor(0.7).lineLimit(1)
                    if metric == .sky && !primary {
                        Text(verbatim: String(format: "%.1f", h.precipitation)).font(.system(size: 9)).foregroundColor(env.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(env.hairline))
    }

    private func value(_ h: WeatherHourPoint, primary: Bool) -> String {
        switch metric {
        case .sky: return primary ? "\(Int(h.cloudCover))%" : "\(Int(h.precipProbability))%"
        case .humidity: return primary ? "\(Int(h.humidity))%" : units.t(h.apparent)
        case .wind: return primary ? "\(Int(units.wind.convert(kmh: h.windSpeed)))" : "\(Int(units.wind.convert(kmh: h.windGusts)))"
        }
    }

    private func chip<L: View>(_ m: HourlyMetric, _ icon: String, @ViewBuilder label: () -> L) -> some View {
        Button { metric = m } label: {
            HStack(spacing: 4) { Image(systemName: icon); label() }
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .background(Capsule().fill(metric == m ? env.accent(.calendar).opacity(0.22) : env.hairline))
                .overlay(Capsule().stroke(metric == m ? env.accent(.calendar) : .clear, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private func arrow(_ name: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 12, weight: .bold)).frame(width: 28, height: 24)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(env.hairline))
        }.buttonStyle(.plain).opacity(enabled ? 1 : 0.35).disabled(!enabled)
    }
}

// MARK: - Trends (temperature line + precipitation bars)

private struct TrendTile: View {
    let env: TileEnv
    let detail: WeatherDetail
    let units: Units
    let width: CGFloat

    var body: some View {
        let hours = detail.hourly
        let temps = hours.map { units.temp.convert($0.temperature) }
        let feels = hours.map { units.temp.convert($0.apparent) }
        let lo = (temps + feels).min() ?? 0, hi = (temps + feels).max() ?? 1
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Temperature").font(.system(size: 14, weight: .bold))
                Spacer()
                legend(env.accent(.calendar), dashed: false) { Text("Temperature") }
                legend(env.accent(.alarms), dashed: true) { Text("Feels Like") }
            }
            Canvas { gc, size in
                let span = max(hi - lo, 1)
                func pt(_ i: Int, _ v: Double) -> CGPoint {
                    CGPoint(x: size.width * Double(i) / Double(max(hours.count - 1, 1)), y: size.height * (1 - 0.1 - 0.8 * (v - lo) / span))
                }
                for k in 0...3 {
                    var g = Path(); let y = size.height * (0.1 + 0.8 * Double(k) / 3)
                    g.move(to: CGPoint(x: 0, y: y)); g.addLine(to: CGPoint(x: size.width, y: y))
                    gc.stroke(g, with: .color(env.hairline), lineWidth: 1)
                }
                func line(_ v: [Double]) -> Path {
                    var p = Path()
                    for (i, x) in v.enumerated() { i == 0 ? p.move(to: pt(i, x)) : p.addLine(to: pt(i, x)) }
                    return p
                }
                var fill = line(temps)
                fill.addLine(to: CGPoint(x: size.width, y: size.height)); fill.addLine(to: CGPoint(x: 0, y: size.height)); fill.closeSubpath()
                gc.fill(fill, with: .linearGradient(Gradient(colors: [env.accent(.calendar).opacity(0.30), env.accent(.calendar).opacity(0)]),
                                                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                gc.stroke(line(feels), with: .color(env.accent(.alarms)), style: StrokeStyle(lineWidth: 1.6, dash: [4, 3]))
                gc.stroke(line(temps), with: .color(env.accent(.calendar)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                if let first = temps.first {
                    let p = pt(0, first)
                    gc.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(env.accent(.calendar)))
                }
            }
            .frame(height: 104)
            HStack {
                ForEach([0, 12, 24, 36, max(hours.count - 1, 0)], id: \.self) { i in
                    Text(verbatim: hours.indices.contains(i) ? hours[i].hourLabel : "").font(.system(size: 9)).foregroundColor(env.secondary)
                    if i != max(hours.count - 1, 0) { Spacer(minLength: 0) }
                }
            }
            HStack {
                Text(verbatim: "\(Int(hi.rounded()))°").font(.system(size: 10, weight: .bold))
                Text(verbatim: "\(Int(lo.rounded()))°").font(.system(size: 10, weight: .bold)).foregroundColor(env.secondary)
                Spacer()
            }
            Text("Precipitation").font(.system(size: 14, weight: .bold)).padding(.top, 2)
            Canvas { gc, size in
                let maxMM = max(hours.map(\.precipitation).max() ?? 0, 1)
                let maxCM = max(hours.map(\.snowfall).max() ?? 0, 0.5)
                let bw = size.width / Double(max(hours.count, 1))
                for (i, h) in hours.enumerated() {
                    let x = Double(i) * bw
                    let rain = size.height * h.precipitation / maxMM
                    gc.fill(Path(CGRect(x: x + 0.5, y: size.height - rain, width: max(bw - 1, 1), height: rain)), with: .color(Color.blue.opacity(0.75)))
                    let snow = size.height * h.snowfall / maxCM
                    gc.fill(Path(CGRect(x: x + 0.5, y: size.height - snow, width: max(bw - 1, 1), height: snow)), with: .color(Color.cyan.opacity(0.9)))
                }
            }
            .frame(height: 46)
            HStack(spacing: 10) {
                Text("Total next 16 days").font(.system(size: 10, weight: .semibold)).foregroundColor(env.secondary)
                Spacer()
                Image(systemName: "drop.fill").foregroundColor(.blue)
                Text(verbatim: String(format: "%.1f mm", detail.daily.map(\.precipSum).reduce(0, +))).font(.system(size: 11, weight: .bold))
                Image(systemName: "snowflake").foregroundColor(.cyan)
                Text(verbatim: String(format: "%.1f cm", detail.daily.map(\.snowSum).reduce(0, +))).font(.system(size: 11, weight: .bold))
            }.font(.system(size: 11))
        }
        .foregroundColor(env.text)
        .padding(12)
        .frame(width: width, alignment: .topLeading)
        .tileSurface(env)
    }

    private func legend<L: View>(_ color: Color, dashed: Bool, @ViewBuilder _ label: () -> L) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: dashed ? 8 : 10, height: 2.5)
            label().font(.system(size: 9, weight: .semibold)).foregroundColor(env.secondary)
        }
    }
}

// MARK: - Daily

struct DailyTile: View {
    let env: TileEnv
    let detail: WeatherDetail
    let units: Units
    let width: CGFloat
    let pageSize: Int
    @State private var page = 0

    var body: some View {
        let pages = max(1, (detail.daily.count + pageSize - 1) / pageSize)
        let rows = Array(detail.daily.dropFirst(page * pageSize).prefix(pageSize))
        let lo = detail.daily.map(\.low).min() ?? 0, hi = max(detail.daily.map(\.high).max() ?? 1, lo + 1)
        VStack(spacing: 6) {
            HStack {
                arrow("chevron.left", enabled: page > 0) { page -= 1 }
                Spacer()
                Text("Daily Forecast").font(.system(size: 14, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                arrow("chevron.right", enabled: page < pages - 1) { page += 1 }
            }
            ForEach(rows) { d in
                HStack(spacing: 6) {
                    dayLabel(d).font(.system(size: 11, weight: .semibold)).frame(width: 34, alignment: .leading)
                    Image(systemName: WeatherResponseParsing.mapWeatherCode(code: d.code).symbol)
                        .symbolRenderingMode(.multicolor).font(.system(size: 15)).frame(width: 22)
                    Text(verbatim: d.precipProbabilityMax >= 10 ? "\(Int(d.precipProbabilityMax))%" : "")
                        .font(.system(size: 9, weight: .semibold)).foregroundColor(.blue).frame(width: 28, alignment: .leading)
                    Text(verbatim: units.t(d.low)).font(.system(size: 11)).foregroundColor(env.secondary).frame(width: 30, alignment: .trailing)
                    GeometryReader { geo in
                        let a = (d.low - lo) / (hi - lo), b = (d.high - lo) / (hi - lo)
                        ZStack(alignment: .leading) {
                            Capsule().fill(env.hairline)
                            Capsule().fill(LinearGradient(colors: [.cyan, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(6, geo.size.width * (b - a))).offset(x: geo.size.width * a)
                        }
                    }.frame(height: 5)
                    Text(verbatim: units.t(d.high)).font(.system(size: 11, weight: .bold)).frame(width: 30, alignment: .trailing)
                }
                .frame(height: 26)
            }
        }
        .foregroundColor(env.text)
        .padding(12)
        .frame(width: width, alignment: .top)
        .tileSurface(env)
    }

    @ViewBuilder private func dayLabel(_ d: WeatherDayPoint) -> some View {
        if d.id == detail.daily.first?.id { Text("Today") } else { Text(verbatim: Self.weekday(d.date)) }
    }

    /// `yyyy-MM-dd` is a location-local calendar date: parse and format in UTC so the weekday never shifts.
    static func weekday(_ iso: String) -> String {
        let p = DateFormatter(); p.dateFormat = "yyyy-MM-dd"; p.timeZone = TimeZone(identifier: "UTC")
        guard let date = p.date(from: iso) else { return iso }
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("EEE"); f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }

    private func arrow(_ name: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 12, weight: .bold)).frame(width: 28, height: 24)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(env.hairline))
        }.buttonStyle(.plain).opacity(enabled ? 1 : 0.35).disabled(!enabled)
    }
}

// MARK: - Details

private struct StatCell: Identifiable {
    let id: String
    let icon: String
    let label: AnyView
    let value: String
    let sub: String?
}

private struct DetailsTile: View {
    let env: TileEnv
    let detail: WeatherDetail
    let units: Units
    let width: CGFloat
    let columns: Int

    var body: some View {
        let cells = stats()
        let rows = stride(from: 0, to: cells.count, by: columns).map { Array(cells[$0..<min($0 + columns, cells.count)]) }
        VStack(spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(row) { c in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) { Image(systemName: c.icon); c.label }
                                .font(.system(size: 10, weight: .semibold)).foregroundColor(env.secondary)
                            Text(verbatim: c.value).font(.system(size: 16, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                            if let sub = c.sub { Text(verbatim: sub).font(.system(size: 9)).foregroundColor(env.secondary).lineLimit(1) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if row.count < columns { ForEach(0..<(columns - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 1) } }
                }
            }
        }
        .foregroundColor(env.text)
        .padding(14)
        .frame(width: width, alignment: .topLeading)
        .tileSurface(env)
    }

    private func stats() -> [StatCell] {
        let now = Date()
        func clock(_ iso: String?) -> String { String(iso?.split(separator: "T").last ?? "--:--") }
        return [
            StatCell(id: "uv", icon: "sun.max.fill", label: AnyView(Text("UV Index")), value: String(format: "%.0f", detail.uvIndex), sub: nil),
            StatCell(id: "pressure", icon: "gauge", label: AnyView(Text("Pressure")), value: "\(Int(detail.pressure)) hPa", sub: nil),
            StatCell(id: "visibility", icon: "eye.fill", label: AnyView(Text("Visibility")), value: String(format: "%.0f km", detail.visibilityMeters / 1000), sub: nil),
            StatCell(id: "dew", icon: "drop.degreesign", label: AnyView(Text("Dew Point")), value: units.t(detail.dewPoint), sub: nil),
            StatCell(id: "precip", icon: "drop.fill", label: AnyView(Text("Precipitation")), value: String(format: "%.1f mm", detail.daily.first?.precipSum ?? 0), sub: nil),
            StatCell(id: "cloud", icon: "cloud.fill", label: AnyView(Text("Cloud Cover")), value: "\(Int(detail.cloudCover))%", sub: nil),
            StatCell(id: "wind", icon: "wind", label: AnyView(Text("Wind")), value: WeatherUnits.wind(detail.windSpeed, units.wind),
                     sub: WeatherUnits.compass(detail.windDirection) + " · " + WeatherUnits.wind(detail.windGusts, units.wind)),
            StatCell(id: "moon", icon: MoonPhase.symbolName(at: now), label: AnyView(Text("Moon")),
                     value: "\(Int((MoonPhase.illumination(at: now) * 100).rounded()))%", sub: nil),
            StatCell(id: "sunrise", icon: "sunrise.fill", label: AnyView(Text("Sunrise")), value: clock(detail.sunrise), sub: nil),
            StatCell(id: "sunset", icon: "sunset.fill", label: AnyView(Text("Sunset")), value: clock(detail.sunset), sub: nil),
        ]
    }
}

// MARK: - Location

private struct NeedsLocationTile: View {
    let env: TileEnv
    @ObservedObject var service: WeatherService
    let width: CGFloat
    @State private var searching = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "location.slash.fill").font(.system(size: 28)).foregroundColor(env.secondary)
            Text("Allow location or search for a city").font(.system(size: 13, weight: .semibold)).multilineTextAlignment(.center)
            Button { searching.toggle() } label: { Label { Text("Add City") } icon: { Image(systemName: "magnifyingglass") } }
                .popover(isPresented: $searching) { CitySearchPopover(service: service, close: { searching = false }) }
        }
        .foregroundColor(env.text)
        .padding(20)
        .frame(width: width)
        .tileSurface(env)
    }
}

private struct CitySearchPopover: View {
    @ObservedObject var service: WeatherService
    let close: () -> Void
    @State private var query = ""
    @State private var results: [SavedCity] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Search city", text: $query).textFieldStyle(.roundedBorder)
            Button { service.select(.current); close() } label: {
                Label { Text("Use Current Location") } icon: { Image(systemName: "location.fill") }
            }.buttonStyle(.plain).font(.system(size: 12))
            if !service.savedCities.cities.isEmpty { Divider() }
            ForEach(service.savedCities.cities) { c in
                HStack {
                    Button { service.select(.city(c.id)); close() } label: { Text(verbatim: c.name).font(.system(size: 12, weight: .semibold)) }.buttonStyle(.plain)
                    Spacer()
                    Button { service.removeCity(id: c.id) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                }
            }
            if !results.isEmpty { Divider() }
            ForEach(results) { c in
                Button { service.addCity(c); close() } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: c.name).font(.system(size: 12, weight: .semibold))
                        Text(verbatim: c.subtitle).font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }.buttonStyle(.plain)
            }
        }
        .padding(12).frame(width: 260)
        .task(id: query) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            results = await service.searchCities(query)
        }
    }
}
