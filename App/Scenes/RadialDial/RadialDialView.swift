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
    @Published var pageIndex = 0
    @Published var hoveredSector: Int?
    @Published var isCenterHovered = false
    /// -1 / 0 / 1: left chevron, hub body, right chevron.
    @Published var hubZone = 0
}

/// Top-level interactive radial dial view (Phase 31b).
struct RadialDialView: View {
    let pages: [RadialDialPage]
    @ObservedObject var state: RadialDialState
    let theme: RadialDialTheme
    let onPointerUp: (CGPoint) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var currentPage: RadialDialPage {
        guard !pages.isEmpty else { return RadialDialPage(id: .main, title: "main", items: []) }
        return pages[min(max(state.pageIndex, 0), pages.count - 1)]
    }

    var body: some View {
        let outer = RadialDialMetrics.outerRadius
        let sectors = RadialDialGeometry.sectors(
            count: currentPage.items.count,
            innerRadius: RadialDialMetrics.innerRadius,
            outerRadius: outer
        )

        ZStack {
            backdrop

            ZStack {
                ForEach(Array(currentPage.items.enumerated()), id: \.element.id) { index, item in
                    if index < sectors.count {
                        RadialDialWedgeView(
                            sector: sectors[index],
                            item: item,
                            isHovered: state.hoveredSector == index,
                            appeared: appeared,
                            reduceMotion: reduceMotion,
                            theme: theme,
                            center: RadialDialMetrics.center
                        )
                    }
                }
            }
            // A page change swaps the whole ring: the old one shrinks away, the new one blooms in.
            .id(currentPage.id)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.86).combined(with: .opacity))

            RadialDialCenterHub(
                title: currentPage.title,
                pageCount: pages.count,
                pageIndex: state.pageIndex,
                centerItem: currentPage.centerItem,
                isHovered: state.isCenterHovered,
                zone: state.hubZone,
                theme: theme
            )
            .scaleEffect(appeared ? 1 : 0.4)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: appeared)
        }
        .frame(width: RadialDialMetrics.panelSize, height: RadialDialMetrics.panelSize)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.86)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.76)) {
                appeared = true
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onEnded { onPointerUp($0.location) })
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
