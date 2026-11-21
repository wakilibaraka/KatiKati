import SwiftUI

/// Phase 10b-3 / DW-3 (optional): a soft tint over the dock surface that follows the desktop's own atmosphere.
/// It draws the same resolved environment the wallpaper engine paints (sun phase, weather, environment pin) so
/// glass and desktop share one palette — and when the user picked a dock accent, the accent's own stop list is
/// laid down instead, which is where solid / gradient / mesh / wallpaper-adaptive become visible on the bar.
/// Mounted only while `Tint Dock by Time of Day` is on, so there is no timeline (and no wake-up) otherwise.
struct PhaseSurfaceTint: View {
    let cornerRadius: CGFloat
    @EnvironmentObject private var weatherService: WeatherService
    @ObservedObject private var wallpaper = WallpaperEngine.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: Date(), by: reduceMotion ? 900 : 300)) { context in
            self.content(at: context.date)
        }
    }

    @ViewBuilder
    private func content(at date: Date) -> some View {
        let state = weatherService.currentState
        let times = state.sunTimes(on: date) ?? SunTimes(sunrise: nil, sunset: nil, polar: state.isNight ? .night : .day)
        let sample = SolarDaylightEvaluator.sample(at: date, times: times)
        let sky = WallpaperSky(state.conditionFamily)
        let terrain = WallpaperTerrain(rawValue: UserDefaults.standard.string(forKey: Self.terrainKey) ?? "") ?? .auto
        let scene = TerrainMimicCatalog.resolve(terrain, latitude: state.latitude, cityName: state.cityName)
        let environment = TerrainMimicCatalog.environment(scene: scene, phase: sample.phase.solarPhase, sky: sky)
        let accent = DockAccentSpec.decode(UserDefaults.standard.data(forKey: DockAccentSpec.defaultsKey))
        let stops = accent.resolved(wallpaperAccent: wallpaper.accentHexes)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        shape
            .fill(fill(for: accent.style, stops: stops, environment: environment))
            .allowsHitTesting(false)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: sample.phase)
    }

    /// The paint for one accent style. A solid is one flat wash, a gradient runs along the accent's own angle, and
    /// a mesh adds a soft second axis so three or four hues blend instead of banding.
    private func fill(for style: DockAccentStyle, stops: [DockAccentColor], environment: WallpaperEnvironment) -> AnyShapeStyle {
        let colors = stops.isEmpty ? legacyColors(environment) : stops.map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
        let angle = UserDefaults.standard.data(forKey: DockAccentSpec.defaultsKey)
            .flatMap { try? JSONDecoder().decode(DockAccentSpec.self, from: $0) }?.angleDegrees ?? 90
        switch style {
        case .solid:
            return AnyShapeStyle(colors[0].opacity(0.18))
        case .mesh where colors.count >= 3:
            return AnyShapeStyle(
                LinearGradient(colors: colors.map { $0.opacity(0.20) }, startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        case .linearGradient, .mesh, .wallpaperAdaptive:
            let points = Self.endpoints(for: angle)
            return AnyShapeStyle(LinearGradient(colors: colors.map { $0.opacity(0.20) },
                                                startPoint: points.start, endPoint: points.end))
        }
    }

    /// No accent stop at all (an empty sample): keep the pre-DW-3 phase wash so the bar never loses its tint.
    private func legacyColors(_ environment: WallpaperEnvironment) -> [Color] {
        [Color(red: environment.skyTop.r, green: environment.skyTop.g, blue: environment.skyTop.b).opacity(0.16),
         Color(red: environment.skyBottom.r, green: environment.skyBottom.g, blue: environment.skyBottom.b).opacity(0.22)]
    }

    /// 0° runs left→right, 90° top→bottom (the same convention the Settings stage preview shows).
    static func endpoints(for angleDegrees: Double) -> (start: UnitPoint, end: UnitPoint) {
        let radians = angleDegrees * .pi / 180
        let dx = cos(radians) / 2, dy = sin(radians) / 2
        return (UnitPoint(x: 0.5 - dx, y: 0.5 - dy), UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
    }

    private static let terrainKey = "com.katikati.wallpaper.terrain"
}
