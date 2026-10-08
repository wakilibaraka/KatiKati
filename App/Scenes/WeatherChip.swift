import SwiftUI

public struct WeatherChip: View {
    @EnvironmentObject var weatherService: WeatherService
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        let theme = DockThemeTokens.resolved(for: colorScheme)
        
        HStack(spacing: 8) {
            Image(systemName: weatherService.currentState.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 16))
                .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
            
            Text(verbatim: "\(Int(round(weatherService.currentState.temperatureCelsius)))°")
                .font(.system(size: 14, weight: .bold, design: .rounded))
            
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
