import SwiftUI

/// Desktop Weather: current conditions from the app's shared `WeatherService`.
struct DesktopWeatherBoxView: View {
    @ObservedObject var service: WeatherService

    private func temperature(_ celsius: Double) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius).formatted(
            .measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0)))
        )
    }

    var body: some View {
        let state = service.currentState
        Group {
            if state.hasData {
                VStack(spacing: 4) {
                    Spacer(minLength: 0)
                    Text(verbatim: state.cityName).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Image(systemName: state.glyphName).font(.system(size: 30)).symbolRenderingMode(.multicolor)
                        Text(verbatim: temperature(state.temperatureCelsius))
                            .font(.system(size: 44, weight: .semibold, design: .rounded))
                    }
                    Text(verbatim: state.conditionText).font(.system(size: 12))
                    Text(verbatim: "\(temperature(state.highCelsius)) / \(temperature(state.lowCelsius))")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "cloud.sun").font(.system(size: 26)).foregroundStyle(.secondary)
                    Text("No forecast yet").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
    }
}
