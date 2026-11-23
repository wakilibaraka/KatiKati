import SwiftUI

/// Redesigned Dark-Glass Weather Hero + 3-Page Hybrid Scrollable Carousel.
struct WeatherModernChip: View {
    let state: WeatherState
    let size: WidgetSize
    @EnvironmentObject private var weatherService: WeatherService
    @ObservedObject private var telemetry = DockTelemetryFeed.shared
    @ObservedObject private var calendarFeed = DockCalendarFeed.shared
    @ObservedObject private var focus = ProductivityServices.shared.focus
    @AppStorage(WidgetMotionPreset.storageKey) private var motionPreset: WidgetMotionPreset = .default
    @AppStorage(WeatherUnits.temperatureKey) private var tempUnit: TemperatureUnit = .celsius
    @AppStorage(WeatherUnits.windKey) private var windUnit: WindSpeedUnit = .kmh
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var naturalHeight: CGFloat = 0
    @AppStorage("com.katikati.weather.modernChip.page") private var storedPageIndex: Int = 0

    private var pageIndex: Int {
        WidgetPageCycle.clamped(storedPageIndex, count: 3)
    }

    private func stepPage(_ delta: Int) {
        let next = WidgetPageCycle.next(current: pageIndex, count: 3, delta: delta)
        if reduceMotion {
            storedPageIndex = next
        } else {
            withAnimation(.snappy(duration: 0.22)) {
                storedPageIndex = next
            }
        }
    }

    private static let ink = Color(white: 0.96)
    private var accent: Color {
        let c = WeatherModernSpec.accent(condition: state.conditionFamily, isNight: state.isNight)
        return Color(red: c.r, green: c.g, blue: c.b)
    }
    private var reading: Int { Int(tempUnit.convert(state.temperatureCelsius).rounded()) }
    private var plate: LinearGradient {
        let sky = SkyTint.tint(condition: state.conditionFamily, isNight: state.isNight)
        let topTint = Color(red: sky.top.r * 0.34 + 0.06, green: sky.top.g * 0.34 + 0.06, blue: sky.top.b * 0.38 + 0.08)
        let botTint = Color(red: sky.bottom.r * 0.22 + 0.05, green: sky.bottom.g * 0.22 + 0.05, blue: sky.bottom.b * 0.28 + 0.07)
        return LinearGradient(colors: [topTint, botTint], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        HStack(spacing: 5) {
            GeometryReader { geo in
                activePageBody
                    .frame(width: geo.size.width)
                    .background(ContentHeightReader())
                    .scaleEffect(SlotFitScale.scale(naturalHeight: naturalHeight, availableHeight: geo.size.height), anchor: .center)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .onPreferenceChange(ContentHeightKey.self) { naturalHeight = $0 }
            }

            if size != .small {
                pagerDots
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .foregroundStyle(Self.ink)
        .dockTileChrome(isHovered: isHovered, fill: plate)
        .overlay(
            VerticalWheelScrollNSViewRepresentable { step in
                stepPage(step)
            }
        )
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
        .dockReadingMorph(motionPreset.effective(reduceMotion: reduceMotion), value: reading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(state.cityName), \(reading)°, \(state.conditionText)"))
        .accessibilityAddTraits(.isButton)
    }

    private var pagerDots: some View {
        WidgetPagerDotsStrip(
            pageCount: 3,
            currentPage: pageIndex,
            axis: .vertical,
            activeColor: Self.ink,
            inactiveColor: Self.ink.opacity(0.32)
        ) {
            stepPage(1)
        }
    }

    @ViewBuilder
    private var activePageBody: some View {
        if size == .small || pageIndex == 0 {
            heroPage
        } else if pageIndex == 1 {
            slotView(weatherService.carouselConfig.page2)
        } else {
            slotView(weatherService.carouselConfig.page3)
        }
    }

    /// Page 1: Dark-glass atmospheric hero card (city top-left, big thin temp bottom-left,
    /// multicolor glyph top-right, condition + H/L bottom-right).
    private var heroPage: some View {
        let hi = Int(tempUnit.convert(state.highCelsius).rounded())
        let lo = Int(tempUnit.convert(state.lowCelsius).rounded())
        return VStack(spacing: 1) {
            HStack(spacing: 4) {
                Text(verbatim: state.cityName)
                    .font(.system(size: 10.5, weight: .medium))
                    .opacity(0.86)
                    .lineLimit(1)
                if !state.isLive || WeatherStaleness(lastUpdated: state.lastUpdated) == .old {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8.5))
                        .opacity(0.65)
                }
                Spacer(minLength: 4)
                Image(systemName: state.glyphName)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 13.5, weight: .medium))
            }

            HStack(alignment: .bottom, spacing: 4) {
                Text(verbatim: "\(reading)°")
                    .font(.system(size: 22, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .kerning(-0.8)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if size != .small {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(verbatim: state.conditionText)
                            .font(.system(size: 9.5, weight: .medium))
                            .opacity(0.86)
                            .lineLimit(1)
                        Text(verbatim: "H:\(hi)° L:\(lo)°")
                            .font(.system(size: 9, weight: .regular))
                            .monospacedDigit()
                            .opacity(0.62)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func slotView(_ mode: WeatherCarouselSlotMode) -> some View {
        switch mode {
        case .hourlyCurve: hourlyCurveView
        case .savedCities: savedCitiesView
        case .conditionsDetail: conditionsDetailView
        case .focusCompanion: focusCompanionView
        case .systemVitals: systemVitalsView
        case .nextCalendar: nextCalendarView
        }
    }

    private var hourlyCurveView: some View {
        let slots = WeatherHourSlot.slots(from: state, count: size == .large ? 6 : 4)
        let rainPct = Int((state.detail?.hourly.first?.precipProbability ?? state.detail?.daily.first?.precipProbabilityMax ?? 0).rounded())
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(reading)°")
                    .font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(verbatim: "☂ \(rainPct)%")
                    .font(.system(size: 9.5, weight: .medium)).monospacedDigit().opacity(0.75)
            }
            if slots.count > 1 {
                VStack(spacing: 2) {
                    HourLine(fractions: WeatherModernSpec.fractions(slots.map(\.temperatureCelsius)), accent: accent)
                        .frame(height: 18)
                    HStack {
                        ForEach(slots) { slot in
                            if slot.isNow { Text("Now") } else { Text(verbatim: slot.hour) }
                            if slot.id != slots.last?.id { Spacer(minLength: 0) }
                        }
                    }
                    .font(.system(size: 9.5, weight: .regular)).monospacedDigit().lineLimit(1).opacity(0.68)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var savedCitiesView: some View {
        let pinned = weatherService.carouselConfig.pinnedLocationTokens
        let tokens = pinned.isEmpty
            ? Array(([WeatherLocationSelection.current.token] + weatherService.savedCities.cities.map { WeatherLocationSelection.city($0.id).token }).prefix(3))
            : pinned
        return HStack(spacing: 6) {
            ForEach(tokens, id: \.self) { token in
                let st = weatherService.cachedStatesByToken[token]
                let cityLabel = st?.cityName ?? cityNameForToken(token)
                let deg = st.map { "\(Int(tempUnit.convert($0.temperatureCelsius).rounded()))°" } ?? "–"
                Button {
                    weatherService.select(WeatherLocationSelection(token: token))
                } label: {
                    VStack(spacing: 1) {
                        Text(verbatim: cityLabel).font(.system(size: 9, weight: .medium)).opacity(0.75).lineLimit(1)
                        HStack(spacing: 2) {
                            Image(systemName: st?.glyphName ?? "cloud.fill").symbolRenderingMode(.multicolor).font(.system(size: 10))
                            Text(verbatim: deg).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var conditionsDetailView: some View {
        let detail = state.detail
        let feels = detail.map { "\(Int(tempUnit.convert($0.apparent).rounded()))°" } ?? "–"
        let wind = detail.map { WeatherUnits.wind($0.windSpeed, windUnit) } ?? "–"
        let uv = detail.map { String(format: "%.0f", $0.uvIndex) } ?? "–"
        let hum = detail.map { "\(Int($0.humidity.rounded()))%" } ?? "–"
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Feels \(feels)").font(.system(size: 9.5, weight: .medium)).monospacedDigit()
                Text(verbatim: "Hum \(hum)").font(.system(size: 9.5)).opacity(0.75).monospacedDigit()
            }
            Spacer(minLength: 2)
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: "UV \(uv)").font(.system(size: 9.5, weight: .medium)).monospacedDigit()
                Text(verbatim: wind).font(.system(size: 9.5)).opacity(0.75).monospacedDigit().lineLimit(1)
            }
        }
    }

    private var focusCompanionView: some View {
        let rem = focus.model.remaining
        let clock = String(format: "%02d:%02d", rem / 60, rem % 60)
        return HStack(spacing: 8) {
            Image(systemName: focus.model.isRunning ? "flame.fill" : "timer")
                .font(.system(size: 13)).foregroundStyle(focus.model.isRunning ? Color.orange : accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: clock).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(focus.model.isRunning ? "Focusing" : "Focus Paused").font(.system(size: 9)).opacity(0.70)
            }
            Spacer(minLength: 2)
            Button { focus.toggle() } label: {
                Image(systemName: focus.model.isRunning ? "pause.fill" : "play.fill").font(.system(size: 11))
            }.buttonStyle(.plain)
        }
        .onTapGesture(count: 2) { focus.reset() }
    }

    private var systemVitalsView: some View {
        let cpu = SystemMonitorFormat.percent(telemetry.state.cpuUsage)
        let ram = SystemMonitorFormat.percent(telemetry.state.memoryFraction)
        let bat = telemetry.state.batteryFraction.map { SystemMonitorFormat.percent($0) } ?? "AC"
        return HStack(spacing: 6) {
            vitalCell("CPU", value: cpu, color: .orange)
            vitalCell("RAM", value: ram, color: .mint)
            vitalCell("BAT", value: bat, color: .green)
        }
        .onAppear { telemetry.retain() }
        .onDisappear { telemetry.release() }
    }

    private func vitalCell(_ label: String, value: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(verbatim: label).font(.system(size: 8.5, weight: .semibold)).foregroundStyle(color)
            Text(verbatim: value).font(.system(size: 11.5, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private var nextCalendarView: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar").font(.system(size: 13)).foregroundStyle(accent)
            if let next = calendarFeed.upcoming.first {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: next.title).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
                    Text(verbatim: CalendarEventCompactFormatter.relativeLine(for: next.start, isAllDay: next.isAllDay))
                        .font(.system(size: 9.5)).opacity(0.75).monospacedDigit().lineLimit(1)
                }
            } else {
                Text("No Upcoming Events").font(.system(size: 10.5)).opacity(0.75).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func cityNameForToken(_ token: String) -> String {
        if case .city(let id) = WeatherLocationSelection(token: token),
           let city = weatherService.savedCities.city(id: id) {
            return city.name
        }
        return state.cityName
    }
}

/// The hourly line: a thin polyline across the width with an accent dot on one hour (the first by default).
struct HourLine: View {
    let fractions: [Double]
    let accent: Color
    var dot = 0

    var body: some View {
        Canvas { ctx, size in
            let n = fractions.count
            let pts = fractions.enumerated().map { i, f in
                CGPoint(x: 4 + CGFloat(i) * (size.width - 8) / CGFloat(max(n - 1, 1)), y: size.height - 4 - CGFloat(f) * (size.height - 8))
            }
            var path = Path()
            path.addLines(pts)
            ctx.stroke(path, with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            if pts.indices.contains(dot) { let p = pts[dot]; ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)), with: .color(accent)) }
        }
    }
}
