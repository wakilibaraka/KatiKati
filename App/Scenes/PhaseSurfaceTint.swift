import SwiftUI

/// Phase 10b-3 (optional): a soft tint over the dock surface that follows the sun phase, drawn from the same
/// `SkyPalette` as the wallpaper so glass and desktop share one palette. Mounted only while the setting is on,
/// so there is no timeline (and no wake-up) otherwise; re-evaluates every 5 minutes.
struct PhaseSurfaceTint: View {
    let cornerRadius: CGFloat
    @EnvironmentObject private var weatherService: WeatherService

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 300)) { context in
            let state = weatherService.currentState
            let times = state.sunTimes(on: context.date) ?? SunTimes(sunrise: nil, sunset: nil, polar: state.isNight ? .night : .day)
            let phase = SolarPhaseResolver.phase(at: context.date, times: times)
            let stops = SkyPalette.stops(phase: phase, sky: WallpaperSky(state.conditionFamily))
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: stops.top.r, green: stops.top.g, blue: stops.top.b).opacity(0.16),
                                              Color(red: stops.bottom.r, green: stops.bottom.g, blue: stops.bottom.b).opacity(0.22)],
                                     startPoint: .top, endPoint: .bottom))
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.6), value: phase)
        }
    }
}
