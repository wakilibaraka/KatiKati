import AppKit
import SwiftUI

/// Compact pill representation of a desktop widget in capsule or edge-docked mode.
struct DesktopCapsuleView: View {
    let item: DesktopWidgetItem
    var canvasTheme: DesktopCanvasThemeState = DesktopCanvasThemeState()
    let itemCount: Int?
    let usesLiquidGlass: Bool
    let onUpdateItem: (DesktopWidgetItem) -> Void
    let onExpandTriggered: () -> Void
    let onRemoveBox: () -> Void
    let onAcquireLock: (DesktopInteractionLock) -> Void
    let onReleaseLock: (DesktopInteractionLock) -> Void
    let onDragStarted: () -> Void
    let onDragChanged: (CGSize, Bool) -> Void
    let onDragEnded: (CGSize, Bool) -> Void

    @ObservedObject private var performance = DesktopPerformanceStore.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dockThemeStyle) private var dockThemeStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isHovered = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var dragStartMouse: CGPoint?

    private var theme: DockThemeTokens { .resolved(for: colorScheme, style: dockThemeStyle) }
    private var effectiveMaterial: DesktopBoxMaterialStyle { item.appearance.materialOverride ?? canvasTheme.materialStyle }
    private var effectiveAccentColor: Color {
        guard let hex = item.appearance.accentHex, let rgb = DesktopHexColor.parse(hex) else { return .accentColor }
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    private var kindSymbol: String {
        switch item.kind {
        case .folder: return "folder.fill"
        case .todo: return "checklist"
        case .quickCapture: return "square.and.pencil"
        case .glance: return "calendar"
        case .weather: return "cloud.sun.fill"
        case .music: return "opticaldisc.fill"
        case .search: return "magnifyingglass"
        case .wordOfTheDay: return "book.closed.fill"
        case .yearProgress: return "chart.pie.fill"
        case .keepAwake: return "cup.and.saucer.fill"
        case .habitStreak: return "flame.fill"
        case .storageGlance: return "internaldrive"
        case .pinnedNote: return "pin.fill"
        case .quickPasteClipboard: return "doc.on.clipboard"
        }
    }

    var body: some View {
        let pillRadius: CGFloat = 16
        ZStack {
            backdropLayer(cornerRadius: pillRadius)

            HStack(spacing: 6) {
                headerIconView

                Text(verbatim: item.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.labelActive.color)
                    .desktopTextTreatment(item.appearance.textTreatment)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let itemCount {
                    Text(verbatim: "\(itemCount)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.labelSubtitle.color)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(theme.chipPillFill.normal.color))
                }

                Spacer(minLength: 2)

                Button(action: onExpandTriggered) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.labelInactive.color)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Expand to Window"))
            }
            .padding(.horizontal, 8)
        }
        .frame(
            width: DesktopCapsuleLayout.standardCapsuleSize.width,
            height: DesktopCapsuleLayout.standardCapsuleSize.height
        )
        .clipShape(Capsule())
        .overlay { capsuleRimOverlay }
        .dockShadow(
            theme.popupShadow,
            visible: DockLiquidGlassConfiguration.stripShadowVisible(
                usesLiquidGlass: usesLiquidGlass,
                usesSystemVariant: DockGlassPresentation.usesSystemVariant
            )
        )
        .padding(PanelLayoutMetrics.shadowPadding)
        .onHover { hovered in handleHover(hovered) }
        .gesture(capsuleDragGesture)
        .contextMenu { contextMenuItems }
    }

    @ViewBuilder
    private var capsuleRimOverlay: some View {
        switch item.appearance.borderStyle {
        case .standard:
            Capsule()
                .strokeBorder(
                    colorScheme == .dark
                        ? Color.white.opacity(0.18)
                        : Color.black.opacity(0.12),
                    lineWidth: 0.75
                )
        case .glow:
            if performance.settings.allowsAnimation(.capsuleEffects) {
                Capsule()
                    .strokeBorder(effectiveAccentColor.opacity(0.7), lineWidth: 1.5)
                    .shadow(color: effectiveAccentColor.opacity(0.55), radius: 6)
            } else {
                Capsule().strokeBorder(effectiveAccentColor.opacity(0.7), lineWidth: 1.5)
            }
        case .hairline:
            Capsule()
                .strokeBorder(effectiveAccentColor.opacity(0.45), lineWidth: 0.5)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private var headerIconView: some View {
        switch item.appearance.iconBadge {
        case .systemDefault:
            Image(systemName: kindSymbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.labelActive.color)
        case .emoji(let value):
            Text(verbatim: value)
                .font(.system(size: 12))
        case .sfSymbol(let name):
            Image(systemName: name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(effectiveAccentColor)
        case .customImage(let path):
            if let nsImg = DesktopAssetStore.decodedImage(
                at: path,
                maxPixelDimension: DesktopAssetKind.widgetIcon.maxPixelDimension
            ) {
                Image(nsImage: nsImg)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 14, height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            } else {
                Image(systemName: kindSymbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.labelActive.color)
            }
        }
    }

    @ViewBuilder
    private func backdropLayer(cornerRadius: CGFloat) -> some View {
        if !performance.settings.allowsAnimation(.capsuleEffects) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill((colorScheme == .dark ? Color(white: 0.14) : Color(white: 0.96)).opacity(0.96))
        } else {
            backdropMaterial(cornerRadius: cornerRadius)
        }
    }

    @ViewBuilder
    private func backdropMaterial(cornerRadius: CGFloat) -> some View {
        switch effectiveMaterial {
        case .inheritDock:
            DockPanelBackdrop(
                theme: theme,
                cornerRadius: cornerRadius,
                usesLiquidGlass: usesLiquidGlass,
                matchesDockRefraction: true
            )
            .padding(1)
            if theme.drawsEffectiveThickness && !usesLiquidGlass {
                theme.panelThicknessLayer(cornerRadius: cornerRadius)
            }
        case .frostedGlass:
            DockVisualEffectView(material: .hudWindow)
        case .tintedGlass:
            DockPanelBackdrop(
                theme: theme,
                cornerRadius: cornerRadius,
                usesLiquidGlass: usesLiquidGlass,
                matchesDockRefraction: true
            )
            .padding(1)
            effectiveAccentColor.opacity(0.18).allowsHitTesting(false)
        case .solidCard:
            let fill = colorScheme == .dark ? Color(white: 0.14, opacity: 0.96) : Color(white: 0.96, opacity: 0.96)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(fill)
        case .clearMinimal:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill((colorScheme == .dark ? Color.black : Color.white).opacity(0.12))
        }
    }

    private func handleHover(_ hovered: Bool) {
        isHovered = hovered
        hoverTask?.cancel()
        if hovered {
            hoverTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000) // 0.15s delay
                guard !Task.isCancelled else { return }
                onExpandTriggered()
            }
        }
    }

    private var capsuleDragGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { _ in
                let mouse = NSEvent.mouseLocation
                if dragStartMouse == nil {
                    dragStartMouse = mouse
                    hoverTask?.cancel()
                    onAcquireLock(.drag)
                    onDragStarted()
                }
                let start = dragStartMouse ?? mouse
                let delta = CGSize(width: mouse.x - start.x, height: mouse.y - start.y)
                let ctrlHeld = NSEvent.modifierFlags.contains(.control)
                onDragChanged(delta, ctrlHeld)
            }
            .onEnded { _ in
                let mouse = NSEvent.mouseLocation
                let start = dragStartMouse ?? mouse
                dragStartMouse = nil
                let delta = CGSize(width: mouse.x - start.x, height: mouse.y - start.y)
                let ctrlHeld = NSEvent.modifierFlags.contains(.control)
                onDragEnded(delta, ctrlHeld)
                onReleaseLock(.drag)
            }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button(String(localized: "Expand to Window")) {
            var updated = item
            updated.capsuleMode = .expanded
            onUpdateItem(updated)
        }
        Divider()
        Menu(String(localized: "Dock to Screen Edge")) {
            Button(String(localized: "Floating Capsule")) {
                var updated = item
                updated.capsuleMode = .capsule
                onUpdateItem(updated)
            }
            Divider()
            Button(String(localized: "Left Edge")) {
                var updated = item
                updated.capsuleMode = .edgeDocked(edge: .left)
                onUpdateItem(updated)
            }
            Button(String(localized: "Right Edge")) {
                var updated = item
                updated.capsuleMode = .edgeDocked(edge: .right)
                onUpdateItem(updated)
            }
            Button(String(localized: "Top Edge")) {
                var updated = item
                updated.capsuleMode = .edgeDocked(edge: .top)
                onUpdateItem(updated)
            }
            Button(String(localized: "Bottom Edge")) {
                var updated = item
                updated.capsuleMode = .edgeDocked(edge: .bottom)
                onUpdateItem(updated)
            }
        }
        Divider()
        Button(String(localized: "Remove Box"), role: .destructive, action: onRemoveBox)
    }
}
