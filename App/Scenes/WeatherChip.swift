import SwiftUI

public struct WeatherChip: View {
    @EnvironmentObject var weatherService: WeatherService
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        let theme = DockThemeTokens.resolved(for: colorScheme)
        
        HStack(spacing: 6) {
            Image(systemName: weatherService.currentState.symbolName)
                .renderingMode(.template)
            Text(verbatim: "\(Int(round(weatherService.currentState.temperatureCelsius)))°")
                .font(.system(size: 12, weight: .medium, design: .rounded))
            
            if !weatherService.currentState.isLive {
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 10, height: 10)
                    .opacity(0.5)
            }
        }
        .foregroundStyle(theme.labelActive.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

public struct WeatherPopupView: View {
    @EnvironmentObject var weatherService: WeatherService

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(weatherService.currentState.cityName)
                .font(.headline)
            Text(weatherService.currentState.conditionText)
                .font(.subheadline)
            HStack {
                Text(verbatim: "H: \(Int(round(weatherService.currentState.highCelsius)))°")
                Text(verbatim: "L: \(Int(round(weatherService.currentState.lowCelsius)))°")
            }
            .font(.caption)
        }
        .padding()
    }
}
