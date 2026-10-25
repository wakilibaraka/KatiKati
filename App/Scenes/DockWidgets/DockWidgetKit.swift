import SwiftUI

/// Shared look of the Calendar / System / Devices dock widgets and the hover previews. The numbers are the Modern
/// weather chip's (graphite plate, 0.96 ink, 0.58 secondary, 9/5 padding, 11 pt captions) on `DockTileChrome`'s
/// 14 pt plate, so the new widgets read as the same dock as the weather chip beside them.
enum DockWidgetStyle {
    static let ink = Color(white: 0.96)
    static let secondaryOpacity = 0.58
    static let horizontalPadding: CGFloat = 9
    static let verticalPadding: CGFloat = 5
    static let captionSize: CGFloat = 11
    static let plate = LinearGradient(colors: [Color(white: 0.085), Color(white: 0.085)], startPoint: .top, endPoint: .bottom)
    /// Preview card: a touch lighter than the plate so it lifts off the wallpaper.
    static let cardFill = Color(white: 0.11)
    static let previewWidth: CGFloat = 300
    static let openDelay: Duration = .milliseconds(350)
    static let closeGrace: Duration = .milliseconds(220)

    static let good = Color(red: 0.30, green: 0.85, blue: 0.45)
    static let warn = Color(red: 1.0, green: 0.80, blue: 0.25)
    static let bad = Color(red: 1.0, green: 0.35, blue: 0.32)
}

private struct DockPopoverEdgeKey: EnvironmentKey {
    static let defaultValue: Edge = .top
}

extension EnvironmentValues {
    /// Which side of a dock widget its hover preview opens on: away from the screen edge the dock hugs.
    var dockPopoverEdge: Edge {
        get { self[DockPopoverEdgeKey.self] }
        set { self[DockPopoverEdgeKey.self] = newValue }
    }
}

extension StripPlacement {
    /// `.popover(arrowEdge:)` for a widget on this edge (the bottom bar's preview rises above it).
    var previewEdge: Edge {
        switch self {
        case .bottom: return .top
        case .left: return .trailing
        case .right: return .leading
        }
    }
}

/// A chip on the bar: the shared plate, padding and ink. Hover state is the chip's own.
private struct DockWidgetChipFrame: ViewModifier {
    @AppStorage(WidgetLook.storageKey) private var lookRaw = WidgetLook.default.rawValue
    @State private var isHovered = false

    private var look: WidgetLook { WidgetLook(rawValue: lookRaw) ?? .default }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, DockWidgetStyle.horizontalPadding)
            .padding(.vertical, DockWidgetStyle.verticalPadding)
            .foregroundStyle(DockWidgetStyle.ink)
            .dockTileChrome(isHovered: isHovered, cornerRadius: look.cornerRadius, fill: look == .tiles ? DockWidgetStyle.plate : nil)
            .onHover { isHovered = $0 }
            .contentShape(Rectangle())
    }
}

/// A 40 × 40 tile on a side rail.
private struct DockWidgetRailFrame: ViewModifier {
    @AppStorage(WidgetLook.storageKey) private var lookRaw = WidgetLook.default.rawValue
    @State private var isHovered = false

    private var look: WidgetLook { WidgetLook(rawValue: lookRaw) ?? .default }

    func body(content: Content) -> some View {
        content
            .foregroundStyle(DockWidgetStyle.ink)
            .frame(width: BarSection.railTileSize, height: BarSection.railTileSize)
            .dockTileChrome(isHovered: isHovered, cornerRadius: look.cornerRadius, fill: look == .tiles ? DockWidgetStyle.plate : nil)
            .onHover { isHovered = $0 }
            .contentShape(Rectangle())
    }
}

/// Opens `preview` in a popover after a short hover and closes it once the pointer has left both the widget and
/// the card (a grace period lets it cross the gap). A click on the widget closes it, so its own action wins.
private struct DockHoverPreview<Preview: View>: ViewModifier {
    @Environment(\.dockPopoverEdge) private var edge
    let preview: () -> Preview
    @State private var shown = false
    @State private var overWidget = false
    @State private var overCard = false
    @State private var pending: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { overWidget = $0; settle() }
            .simultaneousGesture(TapGesture().onEnded { pending?.cancel(); shown = false })
            .popover(isPresented: $shown, arrowEdge: edge) {
                preview().onHover { overCard = $0; settle() }
            }
    }

    private func settle() {
        pending?.cancel()
        let wanted = overWidget || overCard
        guard wanted != shown else { return }
        pending = Task { @MainActor in
            try? await Task.sleep(for: wanted ? DockWidgetStyle.openDelay : DockWidgetStyle.closeGrace)
            guard !Task.isCancelled else { return }
            shown = wanted
        }
    }
}

extension View {
    func dockWidgetChip() -> some View { modifier(DockWidgetChipFrame()) }
    func dockWidgetRailTile() -> some View { modifier(DockWidgetRailFrame()) }
    func dockHoverPreview<Preview: View>(@ViewBuilder _ preview: @escaping () -> Preview) -> some View {
        modifier(DockHoverPreview(preview: preview))
    }

    /// The 11 pt caption at the shared 0.58 opacity.
    func dockCaption() -> some View {
        font(.system(size: DockWidgetStyle.captionSize, weight: .regular)).monospacedDigit().lineLimit(1)
            .opacity(DockWidgetStyle.secondaryOpacity)
    }
}

/// Preview card chrome: width, padding, graphite fill and hairline. The popover supplies the shadow and arrow.
struct DockPreviewCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .frame(width: DockWidgetStyle.previewWidth, alignment: .leading)
            .foregroundStyle(DockWidgetStyle.ink)
            .background(DockWidgetStyle.cardFill)
            .environment(\.colorScheme, .dark)
    }
}

/// A progress ring with a centred label.
struct DockRing<Label: View>: View {
    let fraction: Double
    var tint: Color = DockWidgetStyle.ink
    var lineWidth: CGFloat = 3.5
    @ViewBuilder let label: Label

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.14), lineWidth: lineWidth)
            Circle().trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            label
        }
    }
}

/// 30-sample history line with a soft fill, values already normalised to 0…1.
struct DockSparkline: View {
    let values: [Double]
    var tint: Color = DockWidgetStyle.ink

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            let step = size.width / CGFloat(values.count - 1)
            let points = values.enumerated().map { i, v in
                CGPoint(x: CGFloat(i) * step, y: size.height - 1.5 - CGFloat(min(max(v, 0), 1)) * (size.height - 3))
            }
            var line = Path()
            line.addLines(points)
            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .linearGradient(Gradient(colors: [tint.opacity(0.28), tint.opacity(0)]),
                                                 startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}
