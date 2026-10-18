import SwiftUI

struct LayoutModeThumbnail: View {
    let mode: BarLayoutMode
    let inputs: LayoutThumbnailModel.Inputs
    var highlighted = false
    /// Reference-screen points, so a thin bar stays visible at small sizes.
    var minimumIslandHeight: CGFloat = 2
    /// Fraction of the screen's height shown, measured up from the bottom edge (1 = whole
    /// screen). The live preview crops to the bottom strip so the islands read at full width.
    var visibleBottomFraction: CGFloat = 1

    var body: some View {
        let islands = LayoutThumbnailModel.islands(for: mode, inputs: inputs)
        Canvas { context, size in
            let screen = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 5)
            context.fill(screen, with: .color(Color(red: 0.72, green: 0.77, blue: 0.82)))
            if visibleBottomFraction >= 1 || inputs.placement.isVertical {
                // Menu bar strip only when the whole screen is shown.
                context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: max(2, size.height * 0.035))),
                             with: .color(.white.opacity(0.55)))
            }
            // A side rail runs the screen's height: show the whole screen, not the bottom crop.
            let fraction = inputs.placement.isVertical ? 1 : min(max(visibleBottomFraction, 0.05), 1)
            let top = 1 - fraction
            for island in islands {
                var rect = CGRect(x: island.rect.minX * size.width,
                                  y: (island.rect.minY - top) / fraction * size.height,
                                  width: island.rect.width * size.width,
                                  height: island.rect.height / fraction * size.height)
                if inputs.placement.isVertical {
                    if rect.width < minimumIslandHeight {
                        if inputs.placement == .right { rect.origin.x -= minimumIslandHeight - rect.width }
                        rect.size.width = minimumIslandHeight
                    }
                } else if rect.height < minimumIslandHeight {
                    rect.origin.y -= minimumIslandHeight - rect.height
                    rect.size.height = minimumIslandHeight
                }
                let pill = Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) * 0.32)
                context.fill(pill, with: .color(highlighted ? Color(white: 0.12) : Color(white: 0.25)))
            }
            if let capsule = LayoutThumbnailModel.capsule(for: mode, inputs: inputs) {
                var rect = CGRect(x: capsule.minX * size.width,
                                  y: (capsule.minY - top) / fraction * size.height,
                                  width: capsule.width * size.width,
                                  height: capsule.height / fraction * size.height)
                if rect.height < minimumIslandHeight {
                    rect.origin.y -= minimumIslandHeight - rect.height
                    rect.size.height = minimumIslandHeight
                }
                if inputs.placement.isVertical {
                    rect.size.height = max(rect.height, rect.width)
                } else {
                    rect.size.width = max(rect.width, rect.height)
                }
                context.fill(Path(roundedRect: rect, cornerRadius: rect.height * 0.32),
                             with: .color(highlighted ? Color(white: 0.12) : Color(white: 0.25)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The five modes as cards — shared by the Settings Layout tab and the welcome guide.
struct LayoutModePicker: View {
    let selection: BarLayoutMode
    let inputs: LayoutThumbnailModel.Inputs
    var thumbnailSize = CGSize(width: 88, height: 55)
    let onSelect: (BarLayoutMode) -> Void
    @Environment(\.dockThemeStyle) private var themeStyle
    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredMode: BarLayoutMode?

    /// A rail runs the screen's **height**, so its card is the same card turned on its side (Phase 41d):
    /// in the landscape card the rail was a ~2 pt sliver at the left edge, and Split 4 and Split 5 — the
    /// two modes a rail could not show before Phase 41a — were indistinguishable.
    private var cardSize: CGSize {
        inputs.placement.isVertical ? CGSize(width: thumbnailSize.height, height: thumbnailSize.width)
                                    : thumbnailSize
    }

    /// The rail is a sliver on a whole-screen card (54 of the reference screen's 1440 pt); floor its
    /// thickness so a card still reads as a rail rather than a hairline.
    private var minimumIslandThickness: CGFloat { inputs.placement.isVertical ? 4 : 2 }

    var body: some View {
        let palette = SettingsIridescentPalette.resolve(style: themeStyle, colorScheme: colorScheme)
        HStack(alignment: .top, spacing: 8) {
            ForEach(BarLayoutMode.allCases) { mode in
                let isSelected = mode == selection
                let isHovered = hoveredMode == mode
                Button {
                    onSelect(mode)
                } label: {
                    VStack(spacing: 5) {
                        LayoutModeThumbnail(mode: mode, inputs: inputs, highlighted: isSelected,
                                            minimumIslandHeight: minimumIslandThickness)
                            .frame(width: cardSize.width, height: cardSize.height)
                        LayoutModeTitle(mode: mode)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            .lineLimit(1)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                isSelected
                                    ? AnyShapeStyle(palette.subtleSurfaceGradient)
                                    : AnyShapeStyle(Color.primary.opacity(isHovered ? 0.06 : 0.0))
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isSelected
                                    ? AnyShapeStyle(palette.pillGradient)
                                    : AnyShapeStyle(Color.primary.opacity(isHovered ? 0.16 : 0.0)),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
                    .shadow(color: isSelected ? palette.glowColor : .clear, radius: 6, x: 0, y: 2)
                    .scaleEffect(isHovered ? 1.02 : 1.0)
                    .animation(.spring(response: 0.24, dampingFraction: 0.75), value: isHovered)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in hoveredMode = inside ? mode : (hoveredMode == mode ? nil : hoveredMode) }
                .accessibilityIdentifier("layoutMode.\(mode.rawValue)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// Localized mode name. Literals, so the localization gate sees each key.
struct LayoutModeTitle: View {
    let mode: BarLayoutMode

    var body: some View {
        switch mode {
        case .windows: Text("Full Width")
        case .split3: Text("Split 3")
        case .split4: Text("Split 4")
        case .split5: Text("Split 5")
        case .centered: Text("Centered")
        }
    }
}

/// The built-in dock styles as cards (Phase 11f) — Settings › Layout and the welcome guide.
/// Each thumbnail draws the style's own mode, height and spacing through the solver.
struct DockStylePicker: View {
    let selection: String?
    let inputs: LayoutThumbnailModel.Inputs
    // Five cards must fit the pane's ~504 pt content width (live check 18h: 104 pt overflowed).
    var thumbnailSize = CGSize(width: 78, height: 34)
    let onSelect: (DockStyle) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(DockStyle.builtIns) { style in
                let isSelected = style.id == selection
                Button {
                    onSelect(style)
                } label: {
                    VStack(spacing: 5) {
                        // Cropped to the bottom strip like the Preview: on a whole-screen thumbnail the
                        // size and spacing differences between styles were too small to see.
                        LayoutModeThumbnail(mode: style.mode, inputs: styledInputs(style), highlighted: isSelected,
                                            minimumIslandHeight: 3, visibleBottomFraction: 0.16)
                            .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                        Text(style.localizedTitle)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            .lineLimit(1)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dockStyle.\(style.id)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private func styledInputs(_ style: DockStyle) -> LayoutThumbnailModel.Inputs {
        var copy = inputs
        copy.barHeight = style.size.barHeight
        copy.gap = style.spacing.gap
        copy.margin = style.spacing.margin
        copy.bottomGap = style.bottomGap
        copy.placement = style.placement
        if let id = style.widgetPresetID, let preset = WidgetPresets.builtIns.first(where: { $0.id == id }) {
            copy.widgetOrder = preset.layout.visibleOrder
        }
        return copy
    }
}

/// Plate tint + rim from the real preset tokens (both appearance columns for Auto). Shared by the
/// Appearance theme grid and the welcome guide's theme row (Phase 11f).
struct ThemeSwatch: View {
    let style: DockThemeStyle
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        if style == .auto {
            HStack(spacing: 0) {
                plate(DockThemeStyleTokens.resolve(style: .auto, appearance: .light))
                plate(DockThemeStyleTokens.resolve(style: .auto, appearance: .dark))
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.15)))
        } else {
            let tokens = DockThemeStyleTokens.resolve(style: style, appearance: colorScheme == .dark ? .dark : .light)
            plate(tokens)
                .clipShape(shape)
                .overlay(shape.strokeBorder(color(tokens.rim).opacity(max(0.35, tokens.rim.a)), lineWidth: 1.5))
        }
    }

    private func plate(_ tokens: DockThemeStyleTokens) -> some View {
        ZStack {
            // Neutral desktop under the translucent plate so alpha reads as it does on screen.
            Color(white: 0.62)
            // Phase 12: the gradient half of a preset is what tells the twelve swatches apart, so the
            // preview draws it — the top stop alone was part of why the sweep read them as one theme.
            if let bottom = tokens.baseTintBottom {
                LinearGradient(colors: [color(tokens.baseTint), color(bottom)], startPoint: .top, endPoint: .bottom)
            } else {
                color(tokens.baseTint)
            }
            LinearGradient(colors: [color(tokens.gradientSheen), .clear], startPoint: .top, endPoint: .center)
        }
    }

    private func color(_ rgba: DockRGBA) -> Color {
        Color(.sRGB, red: Double(rgba.r), green: Double(rgba.g), blue: Double(rgba.b), opacity: Double(rgba.a))
    }
}

/// One-line description of a mode under the picker.
struct LayoutModeDetail: View {
    let mode: BarLayoutMode

    var body: some View {
        switch mode {
        case .windows: Text("One full-width bar across the bottom of the screen.")
        case .split3: Text("Three islands: launcher and weather, apps and now playing, clock and widgets.")
        case .split4: Text("Four islands: launcher and weather, apps, now playing, clock and widgets.")
        case .split5: Text("Five islands: launcher, weather, apps and now playing, clock, widgets.")
        case .centered: Text("One compact bar floating in the middle.")
        }
    }
}

extension AppSettingsStore {
    /// The live values every thumbnail draws with.
    var layoutThumbnailInputs: LayoutThumbnailModel.Inputs {
        var inputs = LayoutThumbnailModel.Inputs()
        inputs.barHeight = dockPanelHeight.points
        inputs.gap = islandGap
        inputs.margin = islandMargin
        inputs.centeredWidth = centeredWidth
        inputs.bottomGap = bottomGap
        inputs.placement = stripPlacementMap.global
        let fitted = fittedWidgetLayout(screenWidth: LayoutThumbnailModel.referenceScreen.width)
        inputs.widgetWidths = fitted.solverWidths()
        inputs.widgetOrder = fitted.visibleOrder
        return inputs
    }
}
