import SwiftUI

// Phase 6 Layout tab. Every geometry the user sees here comes from `IslandLayoutSolver`
// through `LayoutThumbnailModel`; every control writes an existing `AppSettingsStore`
// setter whose `@Published` value the panel coordinator already relayouts on, so changes
// apply without a relaunch.

/// One mode drawn from the solver: a muted screen with the islands sitting on its bottom edge.
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
            if visibleBottomFraction >= 1 {
                // Menu bar strip only when the whole screen is shown.
                context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: max(2, size.height * 0.035))),
                             with: .color(.white.opacity(0.55)))
            }
            let fraction = min(max(visibleBottomFraction, 0.05), 1)
            let top = 1 - fraction
            for island in islands {
                var rect = CGRect(x: island.rect.minX * size.width,
                                  y: (island.rect.minY - top) / fraction * size.height,
                                  width: island.rect.width * size.width,
                                  height: island.rect.height / fraction * size.height)
                if rect.height < minimumIslandHeight {
                    rect.origin.y -= minimumIslandHeight - rect.height
                    rect.size.height = minimumIslandHeight
                }
                let pill = Path(roundedRect: rect, cornerRadius: rect.height * 0.32)
                context.fill(pill, with: .color(highlighted ? Color(white: 0.12) : Color(white: 0.25)))
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

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(BarLayoutMode.allCases) { mode in
                let isSelected = mode == selection
                Button {
                    onSelect(mode)
                } label: {
                    VStack(spacing: 5) {
                        LayoutModeThumbnail(mode: mode, inputs: inputs, highlighted: isSelected)
                            .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                        LayoutModeTitle(mode: mode)
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
        for (key, value) in widgetWidths {
            if let section = BarSection(rawValue: key) { inputs.widgetWidths[section] = value }
        }
        return inputs
    }
}

/// Bottom-edge presets for the segmented control. `custom` = any slider value that is
/// neither preset; picking it keeps the current value (or nudges off a preset).
enum BottomEdgeChoice: Hashable {
    case floating, hugging, custom

    init(gap: CGFloat) {
        switch gap {
        case PanelLayoutMetrics.floatingBottomGap: self = .floating
        case PanelLayoutMetrics.huggingBottomGap: self = .hugging
        default: self = .custom
        }
    }
}

struct SettingsLayoutPane: View {
    @ObservedObject var store: AppSettingsStore

    private static let margin: CGFloat = 28
    private static let previewFraction: CGFloat = 0.22

    var body: some View {
        let inputs = store.layoutThumbnailInputs
        VStack(alignment: .leading, spacing: 18) {
            section {
                Text("Preview")
            } content: {
                // Bottom 22% of the reference screen, drawn at full pane width.
                LayoutModeThumbnail(mode: store.barLayoutMode, inputs: inputs, highlighted: true,
                                    minimumIslandHeight: 3, visibleBottomFraction: Self.previewFraction)
                    // Fixed height (≈ the cropped ratio at the pane's 504pt content width): the
                    // window's height probe proposes no height, so `aspectRatio` would collapse.
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
            }

            section {
                Text("Layout Mode")
            } content: {
                LayoutModePicker(selection: store.barLayoutMode, inputs: inputs) { store.setBarLayoutMode($0) }
                // Fixed two-line box: the window is measured once per tab switch, so the
                // pane height must not change with the selected mode.
                LayoutModeDetail(mode: store.barLayoutMode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
            }

            section {
                Text("Size")
            } content: {
                sliderRow(Text("Bar Height"),
                          value: store.dockPanelHeight.points,
                          range: DockPanelHeight.minimum...DockPanelHeight.maximum, step: 1) {
                    store.setDockPanelHeight(DockPanelHeight(clamping: $0))
                }
                sliderRow(Text("Gap Between Islands"), value: store.islandGap, range: 0.5...40, step: 0.5) {
                    store.setIslandGap($0)
                }
                sliderRow(Text("Side Margin"), value: store.islandMargin, range: 0...80, step: 1) {
                    store.setIslandMargin($0)
                }
                sliderRow(Text("Centered Width"), value: store.centeredWidth,
                          range: AppSettingsStore.minimumCenteredWidth...AppSettingsStore.maximumCenteredWidth, step: 10) {
                    store.setCenteredWidth($0)
                }
                .disabled(store.barLayoutMode != .centered)
            }

            section {
                Text("Widget Widths")
            } content: {
                ForEach([BarSection.weather, .media, .clock], id: \.self) { widget in
                    sliderRow(widgetLabel(widget),
                              value: store.widgetWidths[widget.rawValue] ?? widget.defaultWidgetWidth,
                              range: 60...400, step: 5) {
                        store.setWidgetWidth($0, for: widget)
                    }
                }
            }

            section {
                HStack {
                    Text("Bottom Edge")
                    Spacer(minLength: 12)
                    Picker("Bottom Edge", selection: Binding(
                        get: { BottomEdgeChoice(gap: store.bottomGap) },
                        set: { choice in
                            switch choice {
                            case .floating: store.setBottomGap(PanelLayoutMetrics.floatingBottomGap)
                            case .hugging: store.setBottomGap(PanelLayoutMetrics.huggingBottomGap)
                            case .custom:
                                if BottomEdgeChoice(gap: store.bottomGap) != .custom { store.setBottomGap(5) }
                            }
                        }
                    )) {
                        Text("Floating").tag(BottomEdgeChoice.floating)
                        Text("Hugging").tag(BottomEdgeChoice.hugging)
                        Text("Custom").tag(BottomEdgeChoice.custom)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            } content: {
                sliderRow(Text("Distance From Edge"), value: store.bottomGap,
                          range: PanelLayoutMetrics.bottomGapRange, step: 1) {
                    store.setBottomGap($0)
                }
                Text("Floating keeps the bar 8 pt above the screen edge. Hugging sits it almost on the edge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            section {
                Text("Edge Bars")
            } content: {
                Picker("Edge Bars", selection: Binding(
                    get: { store.edgeBarPreset },
                    set: { store.setEdgeBarPreset($0) }
                )) {
                    ForEach(EdgeBarPreset.allCases, id: \.self) { Self.presetTitle($0).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                HStack {
                    Text("Status Side")
                    Spacer(minLength: 12)
                    Picker("Status Side", selection: Binding(
                        get: { store.edgeStatusSide },
                        set: { store.setEdgeStatusSide($0) }
                    )) {
                        Text("Left").tag(EdgeSide.left)
                        Text("Right").tag(EdgeSide.right)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .disabled(store.edgeBarPreset == .off || store.edgeBarPreset == .notes)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Widgets").font(.subheadline.weight(.semibold))
                    ForEach(WidgetTile.allCases, id: \.self) { tile in
                        Toggle(isOn: Binding(
                            get: { store.widgetTiles.contains(tile) },
                            set: { store.setWidgetTile(tile, enabled: $0) }
                        )) {
                            switch tile {
                            case .weather: Text("Weather")
                            case .nowPlaying: Text("Now Playing")
                            case .bluetooth: Text("Bluetooth")
                            }
                        }
                    }
                }
                Toggle("Keep Edge Bars Open", isOn: Binding(
                    get: { store.deckKeepOpen },
                    set: { store.setDeckKeepOpen($0) }
                ))
                .disabled(store.edgeBarPreset == .off)
                Toggle("Sync Notes with iCloud Drive", isOn: Binding(
                    get: { store.notesSyncEnabled },
                    set: { store.setNotesSyncEnabled($0) }
                ))
                Text("Slim bars on the screen edges for notes and system status. Notes stay on the right.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Self.margin)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func presetTitle(_ preset: EdgeBarPreset) -> Text {
        switch preset {
        case .off: return Text("Off")
        case .notes: return Text("Notes")
        case .notesAndStatus: return Text("Notes & Status")
        case .status: return Text("Status")
        }
    }

    private func widgetLabel(_ widget: BarSection) -> Text {
        switch widget {
        case .weather: return Text("Weather")
        case .media: return Text("Now Playing")
        default: return Text("Clock")
        }
    }

    private func section<Header: View, Content: View>(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header().font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func sliderRow(_ label: Text, value: CGFloat, range: ClosedRange<CGFloat>, step: CGFloat,
                           set: @escaping (CGFloat) -> Void) -> some View {
        HStack(spacing: 10) {
            label.frame(width: 150, alignment: .leading)
            Slider(value: Binding(get: { value }, set: set), in: range, step: step)
            Text(verbatim: value.rounded() == value ? "\(Int(value)) pt" : String(format: "%.1f pt", value))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
    }
}
