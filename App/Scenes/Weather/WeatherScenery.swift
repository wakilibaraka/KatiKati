import SwiftUI

/// Phase 56 W12: the flat-vector landscape behind Glance. A saturated sky gradient, a sun or moon,
/// three layered ridges (colours from `WeatherGlanceSpec.palette`), and the shared particle layer
/// (rain, snow, stars, clouds) on top. Static unless `animate`.
struct WeatherScenery: View {
    let condition: WeatherCondition
    let isNight: Bool
    let animate: Bool

    private var palette: WeatherGlanceSpec.Palette { WeatherGlanceSpec.palette(condition: condition, isNight: isNight) }
    private func color(_ c: TileRGB) -> Color { Color(red: c.r, green: c.g, blue: c.b) }

    var body: some View {
        let p = palette
        ZStack {
            LinearGradient(colors: [color(p.skyTop), color(p.skyBottom)], startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                if [.clear, .partlyCloudy].contains(condition) {
                    let r = size.height * 0.07
                    let c = CGPoint(x: size.width * 0.78, y: size.height * 0.24)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(color(p.accent)))
                    if isNight {   // a bite out of the disc in the sky colour reads as a crescent
                        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.4, y: c.y - r * 1.15, width: 2 * r, height: 2 * r)), with: .color(color(p.skyTop)))
                    }
                }
                for (i, hill) in p.hills.enumerated() {
                    let base = size.height * (0.66 + 0.1 * Double(i)), amp = size.height * (0.09 - 0.02 * Double(i))
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: size.height))
                    for x in stride(from: 0.0, through: size.width, by: 8) {
                        let u = x / size.width * .pi * 2
                        path.addLine(to: CGPoint(x: x, y: base - amp * (sin(u * 1.3 + Double(i) * 1.7) + 0.5 * sin(u * 2.9 + Double(i)))))
                    }
                    path.addLine(to: CGPoint(x: size.width, y: size.height))
                    ctx.fill(path, with: .color(color(hill)))
                }
            }
            WeatherEffectsView(plan: .plan(condition: condition, isNight: isNight), animate: animate, cloudOpacity: 0.5)
        }
        .accessibilityHidden(true)
    }
}
