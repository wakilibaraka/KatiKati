import SwiftUI

/// Desktop Weather: current conditions from the app's shared `WeatherService`.
struct DesktopWeatherBoxView: View {
    @ObservedObject var service: WeatherService
    @AppStorage(WeatherUnits.temperatureKey) private var tempUnit: TemperatureUnit = .celsius

    private func temperature(_ celsius: Double) -> String {
        WeatherUnits.degrees(celsius, tempUnit)
    }

    var body: some View {
        let state = service.currentState
        Group {
            if state.hasData {
                VStack(spacing: 4) {
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        if !service.savedCities.cities.isEmpty {
                            Button { service.step(by: -1) } label: {
                                Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                        }
                        Text(verbatim: state.cityName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if !service.savedCities.cities.isEmpty {
                            Button { service.step(by: 1) } label: {
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack(spacing: 8) {
                        Image(systemName: state.glyphName).font(.system(size: 30)).symbolRenderingMode(.multicolor)
                        Button { tempUnit = tempUnit == .celsius ? .fahrenheit : .celsius } label: {
                            Text(verbatim: temperature(state.temperatureCelsius))
                                .font(.system(size: 44, weight: .semibold, design: .rounded))
                        }
                        .buttonStyle(.plain)
                        .help(Text("Switch between °C and °F"))
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
