import SwiftUI

// Phase 56 W4 — the detail bands of the weather design language, shared by the panel segments:
// 7-day range rows, then UV pill, sun arc, rain chart, wind dial and small number cells in a grid whose
// column count follows the width (1 / 2 / 3).

/// Cool-to-warm colour of a temperature, for the range bars.
private func rangeTint(_ celsius: Double) -> Color {
    let t = min(max((celsius + 10) / 50, 0), 1)
    return Color(hue: 0.58 - 0.53 * t, saturation: 0.75, brightness: 0.95)
}

struct DailyRangeRows: View {
    let env: TileEnv
    let days: [WeatherDayPoint]
    let units: Units
    /// Today's current temperature; non-nil only when the first row is today (it gets the "now" dot).
    let currentCelsius: Double?

    static let rowHeight: CGFloat = 34

    var body: some View {
        let weekLow = days.map(\.low).min() ?? 0, weekHigh = days.map(\.high).max() ?? 1
        VStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.id) { i, d in
                let range = TemperatureRange(low: d.low, high: d.high, weekLow: weekLow, weekHigh: weekHigh)
                HStack(spacing: 8) {
                    Group { if i == 0, currentCelsius != nil { Text("Today") } else { Text(verbatim: DailyTile.weekday(d.date)) } }
                        .font(.system(size: 12, weight: .semibold)).frame(width: 40, alignment: .leading)
                    VStack(spacing: 0) {
                        Image(systemName: WeatherResponseParsing.mapWeatherCode(code: d.code).symbol)
                            .symbolRenderingMode(.multicolor).font(.system(size: 15))
                        Text(verbatim: d.precipProbabilityMax >= 10 ? "\(Int(d.precipProbabilityMax))%" : " ")
                            .font(.system(size: 9, weight: .bold)).foregroundColor(.cyan)
                    }.frame(width: 28)
                    Text(verbatim: units.t(d.low)).font(.system(size: 12).monospacedDigit()).foregroundColor(env.secondary)
                        .frame(width: 34, alignment: .trailing)
                    GeometryReader { geo in
                        let w = geo.size.width
                        ZStack(alignment: .leading) {
                            Capsule().fill(env.hairline)
                            Capsule().fill(LinearGradient(colors: [rangeTint(d.low), rangeTint(d.high)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(6, w * (range.end - range.start))).offset(x: w * range.start)
                            if i == 0, let now = currentCelsius {
                                Circle().fill(.white).overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
                                    .frame(width: 7, height: 7)
                                    .offset(x: w * range.marker(current: now, low: d.low, high: d.high) - 3.5)
                            }
                        }.frame(maxHeight: .infinity)
                    }.frame(height: 6)
                    Text(verbatim: units.t(d.high)).font(.system(size: 12, weight: .bold).monospacedDigit())
                        .frame(width: 34, alignment: .trailing)
                }
                .frame(height: Self.rowHeight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(i == 0 && currentCelsius != nil ? String(localized: "Today") : DailyTile.weekday(d.date)), \(units.t(d.low)) – \(units.t(d.high))"))
                if i < days.count - 1 { Divider().opacity(0.2) }
            }
        }
    }
}

private struct BandCard<Content: View>: View {
    let env: TileEnv
    let icon: String
    let title: Text
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) { Image(systemName: icon); title }
                .font(.system(size: 11, weight: .semibold)).foregroundColor(env.secondary)
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(env.hairline.opacity(0.5)))
    }
}

private struct UVBand: View {
    let env: TileEnv
    let index: Double

    var body: some View {
        let level = UVLevel(index: index)
        BandCard(env: env, icon: "sun.max.fill", title: Text("UV Index")) {
            Text(verbatim: String(format: "%.0f", index)).font(.system(size: 22, weight: .bold).monospacedDigit())
            level.name.font(.system(size: 11, weight: .semibold)).foregroundColor(env.secondary)
            GeometryReader { geo in
                Capsule().fill(LinearGradient(colors: [.green, .yellow, .orange, .red, .purple], startPoint: .leading, endPoint: .trailing))
                    .overlay(alignment: .leading) {
                        Circle().fill(.white).overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1)).frame(width: 9, height: 9)
                            .offset(x: (geo.size.width - 9) * UVLevel.fraction(index: index))
                    }
            }.frame(height: 5)
        }
    }

}

extension UVLevel {
    var name: Text {
        switch self {
        case .low: return Text("Low")
        case .moderate: return Text("Moderate")
        case .high: return Text("High")
        case .veryHigh: return Text("Very High")
        case .extreme: return Text("Extreme")
        }
    }
}

private struct SunBand: View {
    let env: TileEnv
    let detail: WeatherDetail

    var body: some View {
        let nowMinutes = (WeatherDetailBands.minutes(detail.hourly.first?.time) ?? 12 * 60) / 60 * 60
            + Calendar.current.component(.minute, from: Date())
        let fraction = WeatherDetailBands.sunFraction(sunrise: detail.sunrise, sunset: detail.sunset, nowMinutes: nowMinutes)
        BandCard(env: env, icon: "sunrise.fill", title: Text("Sunrise")) {
            ZStack(alignment: .bottom) {
                SunArcShape().stroke(env.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                if let f = fraction {
                    SunArcShape().trim(from: 0, to: f).stroke(Color.orange, lineWidth: 2)
                    GeometryReader { geo in
                        let p = SunArcShape.point(in: geo.size, at: f)
                        Circle().fill(Color.yellow).frame(width: 10, height: 10).position(p)
                    }
                }
            }.frame(height: 40)
            HStack {
                Text(verbatim: clock(detail.sunrise)); Spacer(); Text(verbatim: clock(detail.sunset))
            }.font(.system(size: 11, weight: .semibold).monospacedDigit())
        }
    }

    private func clock(_ iso: String?) -> String { String(iso?.split(separator: "T").last ?? "--:--") }
}

/// Half-ellipse from the left horizon to the right horizon.
private struct SunArcShape: Shape {
    static func point(in size: CGSize, at f: Double) -> CGPoint {
        let a = Double.pi * (1 - f)
        return CGPoint(x: size.width / 2 + cos(a) * size.width / 2, y: size.height - sin(a) * size.height)
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        for i in 0...40 {
            let pt = Self.point(in: rect.size, at: Double(i) / 40)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        return p
    }
}

private struct RainBand: View {
    let env: TileEnv
    let detail: WeatherDetail

    var body: some View {
        let hours = Array(detail.hourly.prefix(12))
        let total = hours.map(\.precipitation).reduce(0, +)
        BandCard(env: env, icon: "drop.fill", title: Text("Precipitation")) {
            Text(verbatim: String(format: "%.1f mm", total)).font(.system(size: 22, weight: .bold).monospacedDigit())
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(hours) { h in
                    Capsule().fill(Color.cyan.opacity(h.precipProbability > 0 ? 0.9 : 0.25))
                        .frame(height: max(3, 26 * h.precipProbability / 100))
                }
            }.frame(height: 26, alignment: .bottom)
        }
    }
}

private struct WindBand: View {
    let env: TileEnv
    let detail: WeatherDetail
    let units: Units

    var body: some View {
        BandCard(env: env, icon: "wind", title: Text("Wind")) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(env.secondary.opacity(0.5), lineWidth: 1.5)
                    Image(systemName: "location.north.fill").font(.system(size: 14))
                        .rotationEffect(.degrees(detail.windDirection + 180)) // arrow points where the wind blows to
                }.frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: WeatherUnits.wind(detail.windSpeed, units.wind)).font(.system(size: 16, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(verbatim: WeatherUnits.compass(detail.windDirection)).font(.system(size: 11)).foregroundColor(env.secondary)
                    Text(verbatim: WeatherUnits.wind(detail.windGusts, units.wind)).font(.system(size: 11)).foregroundColor(env.secondary).lineLimit(1)
                }
            }
        }
    }
}

private struct NumberBand: View {
    let env: TileEnv
    let icon: String
    let title: Text
    let value: String

    var body: some View {
        BandCard(env: env, icon: icon, title: title) {
            Text(verbatim: value).font(.system(size: 20, weight: .bold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

/// The detail bands in a grid whose columns follow the available width.
struct DetailGrid: View {
    let env: TileEnv
    let detail: WeatherDetail
    let units: Units

    var body: some View {
        GeometryReader { geo in
            let n = WeatherDetailBands.columns(forWidth: geo.size.width)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: n), spacing: 8) {
                    UVBand(env: env, index: detail.uvIndex)
                    WindBand(env: env, detail: detail, units: units)
                    SunBand(env: env, detail: detail)
                    RainBand(env: env, detail: detail)
                    NumberBand(env: env, icon: "humidity.fill", title: Text("Humidity"), value: "\(Int(detail.humidity))%")
                    NumberBand(env: env, icon: "thermometer.medium", title: Text("Feels Like"), value: units.t(detail.apparent))
                    NumberBand(env: env, icon: "gauge", title: Text("Pressure"), value: "\(Int(detail.pressure)) hPa")
                    NumberBand(env: env, icon: "eye.fill", title: Text("Visibility"), value: String(format: "%.0f km", detail.visibilityMeters / 1000))
                }
            }
        }
    }
}
