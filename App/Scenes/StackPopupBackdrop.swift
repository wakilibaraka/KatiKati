import AppKit
import SwiftUI

/// The plate of the folder / shelf / Trash popup: the native Dock's stack material — regular Liquid
/// Glass in its dark appearance, whatever the system appearance is — shaped by one path that
/// carries the arrow. Below macOS 26 (or with glass switched off) a dark frosted plate takes the
/// same outline.
///
/// The view is `arrowHeight` taller than the plate: the arrow hangs in that strip.
struct StackPopupBackdrop: View {
    let plateSize: CGSize
    /// Arrow centre along the active edge; `nil` = no arrow.
    let arrowCenterX: CGFloat?
    var arrowEdge: StackPopupArrowEdge = .bottom
    let usesLiquidGlass: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dockThemeStyle) private var dockThemeStyle
    @Environment(\.themeTuning) private var themeTuning
    private var theme: DockThemeTokens { .resolved(for: colorScheme, style: dockThemeStyle) }

    private var arrowW: CGFloat { (arrowCenterX != nil && (arrowEdge == .leading || arrowEdge == .trailing)) ? StackPopupMetrics.arrowHeight : 0 }
    private var arrowH: CGFloat { (arrowCenterX != nil && arrowEdge == .bottom) ? StackPopupMetrics.arrowHeight : 0 }

    /// The preset's plate tint, through the same `DockThemeStyle.plateOverlay` pass every other plate
    /// takes. Before this the pop only read `DockThemeTokens`, which carries text, separator and fill
    /// colours but no plate tint — so the pop's theme menu re-tinted the drawer chip and left the plate
    /// itself identical, which is what the live pass saw as "two presets, no difference".
    private var plateOverlay: AnyShapeStyle? {
        guard let top = dockThemeStyle.plateOverlay(
            baseTint: theme.styleTokens.baseTint,
            vibrancy: themeTuning.vibrancy,
            contrast: themeTuning.contrast,
            translucency: themeTuning.translucency) else { return nil }
        return DockGlassBackdrop.overlayPaint(
            top: top,
            bottom: dockThemeStyle.plateOverlayBottom(
                baseTintBottom: theme.styleTokens.baseTintBottom,
                vibrancy: themeTuning.vibrancy,
                contrast: themeTuning.contrast,
                translucency: themeTuning.translucency))
    }

    /// The tint itself, laid on the pop's own outline (plate + arrow) over whichever material drew it.
    @ViewBuilder
    private var plateFill: some View {
        if let paint = plateOverlay {
            StackPopupShape(plateSize: plateSize, arrowEdge: arrowEdge, arrowCenterX: arrowCenterX).fill(paint)
        }
    }

    var body: some View {
        Group {
            if #available(macOS 26.0, *), usesLiquidGlass {
                StackGlassPlate(plateSize: plateSize, arrowEdge: arrowEdge, arrowCenterX: arrowCenterX)
                    .overlay { plateFill }
            } else {
                let shape = StackPopupShape(plateSize: plateSize, arrowEdge: arrowEdge, arrowCenterX: arrowCenterX)
                StackFrostedPlate()
                    .clipShape(shape)
                    .overlay { plateFill }
                    .overlay(shape.stroke(theme.stackPopupHairline.color, lineWidth: 0.5))
                    .dockShadow(theme.stackPopupShadow)
            }
        }
        .frame(width: plateSize.width + arrowW, height: plateSize.height + arrowH)
        .allowsHitTesting(false)
    }
}

struct StackPopupShape: Shape {
    let plateSize: CGSize
    var arrowEdge: StackPopupArrowEdge = .bottom
    let arrowCenterX: CGFloat?

    func path(in rect: CGRect) -> Path {
        Path(StackPopupOutline.path(plateSize: plateSize, arrowEdge: arrowEdge, arrowCenter: arrowCenterX))
            .offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// The glass itself. A plain container owns the `NSGlassEffectView` so the no-`_setPath:` fallback
/// can keep the glass off the arrow strip instead of painting a plate 8pt too tall.
@available(macOS 26.0, *)
private struct StackGlassPlate: NSViewRepresentable {
    let plateSize: CGSize
    let arrowEdge: StackPopupArrowEdge
    let arrowCenterX: CGFloat?

    func makeNSView(context: Context) -> StackGlassContainer {
        let view = StackGlassContainer()
        view.apply(plateSize: plateSize, arrowEdge: arrowEdge, arrowCenterX: arrowCenterX)
        return view
    }

    // SwiftUI re-runs update, never re-creates the view: width and arrow follow the content here.
    func updateNSView(_ view: StackGlassContainer, context: Context) {
        view.apply(plateSize: plateSize, arrowEdge: arrowEdge, arrowCenterX: arrowCenterX)
    }
}

@available(macOS 26.0, *)
final class StackGlassContainer: NSView {
    private let glass = NSGlassEffectView()
    private var plateSize = CGSize.zero
    private var arrowEdge: StackPopupArrowEdge = .bottom
    private var arrowCenterX: CGFloat? = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        glass.contentView = NSView()
        glass.style = .regular
        // On the view, not the window: the app is pinned to `.aqua` and everything else in this
        // panel (menus included) stays light.
        glass.appearance = NSAppearance(named: .darkAqua)
        glass.cornerRadius = StackPopupMetrics.cornerRadius
        addSubview(glass)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func apply(plateSize: CGSize, arrowEdge: StackPopupArrowEdge, arrowCenterX: CGFloat?) {
        guard plateSize != self.plateSize || arrowEdge != self.arrowEdge || arrowCenterX != self.arrowCenterX else { return }
        self.plateSize = plateSize
        self.arrowEdge = arrowEdge
        self.arrowCenterX = arrowCenterX
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let arrow = StackPopupMetrics.arrowHeight
        let hasArrow = arrowCenterX != nil
        let arrowW = (hasArrow && (arrowEdge == .leading || arrowEdge == .trailing)) ? arrow : 0
        let arrowH = (hasArrow && arrowEdge == .bottom) ? arrow : 0
        let full = CGRect(x: 0, y: 0, width: plateSize.width + arrowW, height: plateSize.height + arrowH)
        // AppKit's y runs up: flip the outline, whose y runs down in top-left coords.
        var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: full.height)
        let outline = StackPopupOutline.path(plateSize: plateSize, arrowEdge: arrowEdge, arrowCenter: arrowCenterX)
        if let path = outline.copy(using: &flip), TEDockGlassSetPath(glass, path) {
            glass.frame = full
        } else {
            let gx = (hasArrow && arrowEdge == .leading) ? arrow : 0
            let gy = (hasArrow && arrowEdge == .bottom) ? arrow : 0
            glass.frame = CGRect(x: gx, y: gy, width: plateSize.width, height: plateSize.height)
        }
    }
}

private struct StackFrostedPlate: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
