import AppKit
import SwiftUI

/// Everything a widget may need, handed down by the panel controller.
struct PinboardContext {
    let weather: WeatherService
    let toggles: QuickToggleEngine
    let toggleOrder: [QuickToggleID]
}

struct PinboardWidgetView: View {
    let widget: PinboardWidget
    let context: PinboardContext

    var body: some View {
        switch widget {
        case .clock: PinboardClockCard()
        case .calendar: PinboardCalendarCard()
        case .weather: PinboardWeatherCard(service: context.weather)
        case .nowPlaying: PinboardNowPlayingCard()
        case .calculator: PinboardCalculatorCard()
        case .countdown: PinboardCountdownCard()
        case .screenTime: PinboardScreenTimeCard()
        case .quickSettings: PinboardQuickSettingsCard(engine: context.toggles, order: context.toggleOrder)
        case .system: PinboardSystemCard()
        case .network: PinboardNetworkCard()
        case .battery: PinboardBatteryCard()
        case .topApps: PinboardTopAppsCard()
        case .batteries: PinboardBatteriesCard()
        }
    }
}

private struct PinboardClockCard: View {
    var body: some View {
        WidgetCard(widget: .clock, title: Text("Clock")) {
            TimelineView(.periodic(from: Date(), by: 1)) { ctx in
                VStack(alignment: .leading, spacing: 2) {
                    Text(ctx.date, style: .time).font(.system(size: 44, weight: .thin)).monospacedDigit().foregroundColor(.white)
                    Text(ctx.date, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.system(size: 13, weight: .medium)).foregroundColor(.white.opacity(0.75))
                }
            }
        }
    }
}

private struct PinboardCalendarCard: View {
    var body: some View {
        WidgetCard(widget: .calendar, title: Text("Calendar")) {
            Text(Date(), format: .dateTime.day()).font(.system(size: 54, weight: .semibold)).foregroundColor(.white)
            Text(Date(), format: .dateTime.weekday(.wide).month(.abbreviated))
                .font(.system(size: 13, weight: .medium)).foregroundColor(.white.opacity(0.8))
        }
    }
}

private struct PinboardWeatherCard: View {
    @ObservedObject var service: WeatherService
    var body: some View {
        let s = service.currentState
        WidgetCard(widget: .weather, title: Text("Weather")) {
            if s.cityName.isEmpty {
                Text("No Weather Yet").font(.system(size: 13)).foregroundColor(.white.opacity(0.8))
            } else {
                Text(verbatim: s.cityName).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                HStack(alignment: .firstTextBaseline) {
                    Text(Measurement(value: s.temperatureCelsius, unit: UnitTemperature.celsius),
                         format: .measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
                        .font(.system(size: 38, weight: .light))
                    Spacer(minLength: 0)
                    Image(systemName: s.symbolName).font(.system(size: 22)).symbolRenderingMode(.multicolor)
                }
                Text(verbatim: s.conditionText).font(.system(size: 12)).foregroundColor(.white.opacity(0.8)).lineLimit(1)
            }
        }
    }
}

private struct PinboardNowPlayingCard: View {
    @StateObject private var service = NowPlayingService()
    var body: some View {
        WidgetCard(widget: .nowPlaying, title: Text("Now Playing")) {
            if let title = service.state.title {
                Text(verbatim: title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                if let artist = service.state.artist {
                    Text(verbatim: artist).font(.system(size: 12)).foregroundColor(.white.opacity(0.8)).lineLimit(1)
                }
            } else {
                Text("Nothing Playing").font(.system(size: 13)).foregroundColor(.white.opacity(0.8))
            }
            Spacer(minLength: 0)
            Button { service.togglePlayPause() } label: {
                Image(systemName: service.state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold)).frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.25)))
            }.buttonStyle(.plain)
        }
    }
}

private struct PinboardCalculatorCard: View {
    @State private var expression = ""
    var body: some View {
        WidgetCard(widget: .calculator, title: Text("Calculator")) {
            TextField("Expression", text: $expression).textFieldStyle(.plain).font(.system(size: 22, weight: .light))
            Text(verbatim: CalculatorEngine.evaluate(expression).map(CalculatorEngine.format) ?? "")
                .font(.system(size: 34, weight: .light)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
        }
    }
}

private struct PinboardCountdownCard: View {
    @ObservedObject private var store = ProductivityServices.shared.countdowns
    var body: some View {
        WidgetCard(widget: .countdown, title: Text("Countdown")) {
            if let e = store.events.first {
                let days = e.daysRemaining(from: Date())
                Text(verbatim: "\(days)").font(.system(size: 50, weight: .semibold)).monospacedDigit()
                Text(verbatim: e.label).font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.85)).lineLimit(1)
            } else {
                Text("No events").font(.system(size: 13)).foregroundColor(.white.opacity(0.85))
            }
        }
    }
}

private struct PinboardScreenTimeCard: View {
    var body: some View {
        WidgetCard(widget: .screenTime, title: Text("Screen Time")) {
            ScreenTimeSummaryView(rows: 3)
        }
    }
}

private struct PinboardQuickSettingsCard: View {
    @ObservedObject var engine: QuickToggleEngine
    let order: [QuickToggleID]
    @State private var confirming: QuickToggleID?

    var body: some View {
        WidgetCard(widget: .quickSettings, title: Text("Quick Settings")) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 10) {
                ForEach(order, id: \.self) { id in cell(id) }
            }
        }
        .onAppear { engine.refresh() }
    }

    private func cell(_ id: QuickToggleID) -> some View {
        let on = engine.states[id] ?? false
        let gone = engine.unavailable.contains(id)
        let armed = confirming == id
        return Button {
            if id.needsConfirm && !armed { confirming = id; DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if confirming == id { confirming = nil } }; return }
            confirming = nil
            engine.perform(id)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: engine.flash == id ? "checkmark" : id.symbolName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(on || armed ? Color(red: 0.12, green: 0.14, blue: 0.22) : .white)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(armed ? Color.red.opacity(0.9) : (on ? Color.white : Color.white.opacity(0.16))))
                    .overlay(armed ? Image(systemName: "exclamationmark").font(.system(size: 9, weight: .heavy)).foregroundColor(.white).offset(x: 14, y: -14) : nil)
                id.title.font(.system(size: 9, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .buttonStyle(.plain)
        .opacity(gone ? 0.35 : 1)
        .disabled(gone)
    }
}
