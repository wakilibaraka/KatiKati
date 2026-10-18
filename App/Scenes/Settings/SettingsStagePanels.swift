import SwiftUI

/// What the stage draws on top of the wallpaper for the pages that have their own surface. Each view
/// reads settings only (no feed, no event tap, no panel), so it can't start anything.

/// Control Center: the panel on its side, at its width and anchor, with a block per enabled tile.
struct StageControlCenter: View {
    @ObservedObject var store: AppSettingsStore
    @AppStorage("com.katikati.controlcenter.side") private var sideRaw = EdgeSide.right.rawValue

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / LayoutThumbnailModel.referenceScreen.width
            let width = store.controlCenterSize.width * scale
            let tiles = store.controlCenterWidgets.count + store.controlCenterToggles.count
            // Height grows with content, capped to the screen like the real panel.
            let height = min(proxy.size.height * 0.86, (60 + CGFloat(tiles) * 34) * scale * 1.6)
            VStack {
                if store.controlCenterAnchor != .top { Spacer(minLength: 0) }
                panel(width: width, height: height, scale: scale)
                if store.controlCenterAnchor != .bottom { Spacer(minLength: 0) }
            }
            .padding(.vertical, 18 * scale + 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: sideRaw == EdgeSide.left.rawValue ? .leading : .trailing)
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: store.controlCenterSize)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: store.controlCenterAnchor)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: sideRaw)
    }

    private func panel(width: CGFloat, height: CGFloat, scale: CGFloat) -> some View {
        let count = max(1, store.controlCenterWidgets.count + store.controlCenterToggles.count)
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                VStack(spacing: 3) {
                    ForEach(0..<min(count, 12), id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 3, style: .continuous).fill(.white.opacity(0.35))
                    }
                }
                .padding(5)
            )
            .frame(width: max(24, width), height: max(30, height))
    }
}

/// Radial Dial: a ring of wedges in the chosen theme's colours.
struct StageRadialDial: View {
    @AppStorage("com.katikati.dial.enabled") private var enabled = true
    @AppStorage("com.katikati.dial.theme") private var themeRaw = RadialDialTheme.lilacGlass.rawValue

    private var theme: RadialDialTheme { RadialDialTheme(rawValue: themeRaw) ?? .lilacGlass }

    private var palette: (fill: Color, edge: Color) {
        switch theme {
        case .lilacGlass: return (Color(red: 0.72, green: 0.58, blue: 0.95).opacity(0.55), .white.opacity(0.7))
        case .darkObsidian: return (Color.black.opacity(0.78), .white.opacity(0.18))
        case .systemFrosted: return (Color.white.opacity(0.45), .white.opacity(0.6))
        case .neonCyber: return (Color.black.opacity(0.8), Color(red: 0.1, green: 0.95, blue: 0.95))
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let d = min(proxy.size.width, proxy.size.height) * 0.62
            ZStack {
                ForEach(0..<8, id: \.self) { i in
                    Wedge(index: i, count: 8)
                        .fill(palette.fill)
                        .overlay(Wedge(index: i, count: 8).stroke(palette.edge, lineWidth: 1))
                }
                Circle().fill(palette.fill).overlay(Circle().stroke(palette.edge, lineWidth: 1)).frame(width: d * 0.3)
            }
            .frame(width: d, height: d)
            .opacity(enabled ? 1 : 0.3)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .animation(.easeOut(duration: 0.2), value: themeRaw)
    }

    private struct Wedge: Shape {
        let index: Int
        let count: Int

        func path(in rect: CGRect) -> Path {
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let r = rect.width / 2
            let step = 360.0 / Double(count)
            let start = Angle(degrees: -90 + step * Double(index) + 1.5)
            let end = Angle(degrees: -90 + step * Double(index + 1) - 1.5)
            var p = Path()
            p.addArc(center: c, radius: r, startAngle: start, endAngle: end, clockwise: false)
            p.addArc(center: c, radius: r * 0.34, startAngle: end, endAngle: start, clockwise: true)
            p.closeSubpath()
            return p
        }
    }
}

/// Window Management: four sample windows laid out by the chosen preset, with the inner and outer gap.
struct StageTiling: View {
    @ObservedObject private var engine = TilingEngine.shared

    var body: some View {
        GeometryReader { proxy in
            let outer = engine.gaps.outer * 0.25
            let inner = engine.gaps.inner * 0.25
            let area = CGRect(origin: .zero, size: proxy.size).insetBy(dx: outer + 10, dy: outer + 22)
            ZStack(alignment: .topLeading) {
                ForEach(Array(Self.rects(preset: engine.preset, area: area, gap: inner).enumerated()), id: \.offset) { _, r in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.white.opacity(0.5), lineWidth: 1))
                        .frame(width: max(2, r.width), height: max(2, r.height))
                        .offset(x: r.minX, y: r.minY)
                }
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: engine.preset)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: engine.gaps)
    }

    /// Four windows: BSP halves then quarters, one master with a stack, or all stacked full-size.
    static func rects(preset: TilingLayoutPreset, area: CGRect, gap: CGFloat) -> [CGRect] {
        let h = gap / 2
        switch preset {
        case .monocle:
            return [area]
        case .mainStack:
            let left = CGRect(x: area.minX, y: area.minY, width: area.width / 2 - h, height: area.height)
            let rowH = (area.height - 2 * gap) / 3
            let right = (0..<3).map { i in
                CGRect(x: area.midX + h, y: area.minY + CGFloat(i) * (rowH + gap), width: area.width / 2 - h, height: rowH)
            }
            return [left] + right
        case .bsp:
            let halfW = area.width / 2 - h
            let halfH = area.height / 2 - h
            return [
                CGRect(x: area.minX, y: area.minY, width: halfW, height: area.height),
                CGRect(x: area.midX + h, y: area.minY, width: halfW, height: halfH),
                CGRect(x: area.midX + h, y: area.midY + h, width: halfW / 2 - h, height: halfH),
                CGRect(x: area.midX + h + halfW / 2 + h, y: area.midY + h, width: halfW / 2 - h, height: halfH),
            ]
        }
    }
}
