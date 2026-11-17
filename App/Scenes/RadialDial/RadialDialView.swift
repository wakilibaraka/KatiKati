import SwiftUI

/// Shared layout constants. The panel is larger than the ring so the drop shadow isn't clipped.
enum RadialDialMetrics {
    static let panelSize: CGFloat = 380
    static let outerRadius: CGFloat = 160
    static let innerRadius: CGFloat = 52
    static let hubSize: CGFloat = 100
    static var center: CGPoint { CGPoint(x: panelSize / 2, y: panelSize / 2) }
}

/// What the pointer (or keyboard) currently points at. Owned by the panel controller, which feeds it
/// from global mouse monitors, so hover works with no button held and while a hold-to-open button is down.
@MainActor
final class RadialDialState: ObservableObject {
    @Published var nav = RadialDialNavigationState(rootTitle: "Main", rootNodes: RadialDialPresets.defaultRootNodes())
    @Published var hoveredSector: Int?
    @Published var isCenterHovered = false
    /// -1 / 0 / 1: left chevron, hub body, right chevron.
    @Published var hubZone = 0
}

/// Top-level interactive radial dial view (SLICE RD-2: Path/Canvas slices, spring summon, breadcrumb sub-menus).
struct RadialDialView: View {
    @ObservedObject var state: RadialDialState
    let theme: RadialDialTheme
    let onPointerUp: (CGPoint) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var summonSpring: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.78)
    }

    var body: some View {
        let nodes = state.nav.currentNodes
        let sectors = RadialDialGeometry.sectors(
            count: nodes.count,
            innerRadius: RadialDialMetrics.innerRadius,
            outerRadius: RadialDialMetrics.outerRadius
        )

        ZStack {
            backdrop
            canvasOverlay(sectors: sectors)

            ZStack {
                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    if index < sectors.count {
                        RadialDialWedgeView(
                            sector: sectors[index],
                            node: node,
                            isHovered: state.hoveredSector == index,
                            appeared: appeared,
                            reduceMotion: reduceMotion,
                            theme: theme,
                            center: RadialDialMetrics.center
                        )
                    }
                }
            }
            .id(state.nav.breadcrumbs.joined(separator: "/"))
            .transition(reduceMotion ? .opacity : .scale(scale: 0.88).combined(with: .opacity))

            RadialDialCenterHub(
                title: state.nav.currentTitle,
                breadcrumbs: state.nav.breadcrumbs,
                canGoBack: state.nav.canGoBack,
                isHovered: state.isCenterHovered,
                theme: theme
            )
            .scaleEffect(appeared ? 1 : 0.4)
            .animation(summonSpring, value: appeared)
        }
        .overlay(alignment: .top) {
            if state.nav.canGoBack {
                Text(verbatim: state.nav.breadcrumbs.joined(separator: " › "))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.92))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                    .padding(.top, 6)
                    .transition(.opacity)
            }
        }
        .frame(width: RadialDialMetrics.panelSize, height: RadialDialMetrics.panelSize)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.86)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(summonSpring) {
                appeared = true
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onEnded { onPointerUp($0.location) })
    }

    private func canvasOverlay(sectors: [RadialDialGeometry.Sector]) -> some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let inner = RadialDialMetrics.innerRadius
            let outer = RadialDialMetrics.outerRadius

            for sector in sectors {
                let startCos = cos(sector.startAngle)
                let startSin = sin(sector.startAngle)
                var divider = Path()
                divider.move(to: CGPoint(x: center.x + inner * startCos, y: center.y + inner * startSin))
                divider.addLine(to: CGPoint(x: center.x + outer * startCos, y: center.y + outer * startSin))
                context.stroke(divider, with: .color(.white.opacity(0.12)), lineWidth: 1)

                if state.hoveredSector == sector.index {
                    var glowSector = Path()
                    glowSector.addArc(center: center, radius: outer, startAngle: Angle(radians: Double(sector.startAngle)), endAngle: Angle(radians: Double(sector.endAngle)), clockwise: false)
                    glowSector.addArc(center: center, radius: inner, startAngle: Angle(radians: Double(sector.endAngle)), endAngle: Angle(radians: Double(sector.startAngle)), clockwise: true)
                    glowSector.closeSubpath()
                    context.fill(glowSector, with: .radialGradient(
                        Gradient(colors: [outerBorderColor.opacity(0.45), .clear]),
                        center: sector.centerPoint(in: center, atFraction: 0.5),
                        startRadius: 4,
                        endRadius: 72
                    ))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var backdrop: some View {
        let size = RadialDialMetrics.outerRadius * 2
        return Circle()
            .fill(.ultraThinMaterial)
            .overlay(Circle().fill(backdropTint))
            .overlay(Circle().strokeBorder(outerBorderColor, lineWidth: 1.5))
            // Soft inner rim so the ring reads as a lens, not a flat disc.
            .overlay(Circle().inset(by: 3).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.38), radius: 18, y: 8)
            .shadow(color: outerBorderColor.opacity(0.35), radius: 24)
    }

    private var backdropTint: Color {
        switch theme {
        case .lilacGlass: return Color(red: 0.16, green: 0.14, blue: 0.24).opacity(0.62)
        case .darkObsidian: return Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.78)
        case .systemFrosted: return Color.black.opacity(0.42)
        case .neonCyber: return Color(red: 0.04, green: 0.05, blue: 0.10).opacity(0.8)
        }
    }

    private var outerBorderColor: Color {
        switch theme {
        case .lilacGlass: return Color(red: 0.65, green: 0.55, blue: 0.95).opacity(0.45)
        case .darkObsidian: return Color.white.opacity(0.18)
        case .systemFrosted: return Color.white.opacity(0.25)
        case .neonCyber: return Color(red: 0.0, green: 0.85, blue: 0.95).opacity(0.6)
        }
    }
}
