import SwiftUI

/// Phase 56a: a quiet "how far through the year" tile: the percentage, a bar, and the days left.
struct YearProgressTile: View {
    let env: TileEnv
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let p = YearProgress(date: Date())
        let daysLeft = String(format: String(localized: "%d days left"), p.daysLeft)
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: Date().formatted(.dateTime.year())).font(.system(size: 12, weight: .bold)).foregroundColor(env.secondary)
            Text(verbatim: "\(p.percent)%").font(.system(size: 34, weight: .light)).monospacedDigit()
            ProgressView(value: p.fraction).tint(env.accent(.date))
            Text(daysLeft).font(.system(size: 12)).foregroundColor(env.secondary)
            Spacer(minLength: 0)
        }
        .foregroundColor(env.text)
        .padding(16)
        .frame(width: width, height: height, alignment: .topLeading)
        .tileSurface(env)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(p.percent)%, \(daysLeft)"))
    }
}
