import SwiftUI

/// A slow, Siri-style colour flow hugging the inside of the open notch. Clipped to the mask so it never
/// spills past the edge (sharp or curved), and static under Reduce Motion.
struct NotchSiriRim: View {
    let top: CGFloat
    let bottom: CGFloat
    let flares: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let colors: [Color] = [
        Color(red: 0.36, green: 0.55, blue: 1.0), Color(red: 0.70, green: 0.40, blue: 1.0),
        Color(red: 1.0, green: 0.42, blue: 0.62), Color(red: 1.0, green: 0.68, blue: 0.35),
        Color(red: 0.30, green: 0.85, blue: 0.85), Color(red: 0.36, green: 0.55, blue: 1.0),
    ]

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let shape = NotchContinuousMaskShape(topCornerRadius: top, bottomCornerRadius: bottom, flaringTopEars: flares)
            shape
                .stroke(AngularGradient(colors: Self.colors, center: .center, angle: .degrees(reduceMotion ? 0 : t * 40)),
                        lineWidth: 8)
                .blur(radius: 4)
                .opacity(0.8 + (reduceMotion ? 0 : 0.2 * sin(t * 1.6)))
                .clipShape(shape)
        }
        .allowsHitTesting(false)
    }
}
