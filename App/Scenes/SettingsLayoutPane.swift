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
            color(tokens.baseTint)
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
    @State private var newPresetName = ""
    /// Fine-tune starts collapsed: styles + Size/Spacing cover the common choices (Phase 11f).
    @State private var showsFineTune = false
    /// Control Center edge; the panel reads it at each open (Phase 16n). The literal duplicates
    /// `ControlCenterPanelController.sideKey` — that file is app-target-only, and this pane also
    /// compiles into the test target.
    @AppStorage("com.katikati.controlcenter.side") private var controlCenterSideRaw = EdgeSide.right.rawValue

    /// Width styles are fitted to: the screen the dock is on (main until it reports).
    private var dockScreenWidth: CGFloat { NSScreen.main?.frame.width ?? LayoutThumbnailModel.referenceScreen.width }

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
                HStack {
                    Text("Dock Style")
                    Spacer(minLength: 8)
                    if store.currentDockStyle == nil {
                        Text("Custom").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } content: {
                DockStylePicker(selection: store.currentDockStyle?.id, inputs: inputs) {
                    store.applyDockStyle($0, screenWidth: dockScreenWidth)
                }
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
                segmentedRow(Text("Position"), selection: Binding(
                    get: { store.stripPlacementMap.global },
                    set: { store.setStripPlacement($0) }
                )) {
                    Text("Bottom").tag(StripPlacement.bottom)
                    Text("Left").tag(StripPlacement.left)
                    Text("Right").tag(StripPlacement.right)
                }
                segmentedRow(Text("Bar Height"), selection: Binding(
                    get: { DockSizeClass.nearest(to: store.dockPanelHeight.points) },
                    set: { store.setDockPanelHeight(DockPanelHeight(clamping: $0.barHeight)) }
                )) {
                    Text("Small").tag(DockSizeClass.small)
                    Text("Medium").tag(DockSizeClass.medium)
                    Text("Large").tag(DockSizeClass.large)
                }
                segmentedRow(Text("Spacing"), selection: Binding(
                    get: { DockSpacing.matching(gap: store.islandGap, margin: store.islandMargin) },
                    set: { if let spacing = $0 { store.setDockSpacing(spacing) } }
                )) {
                    Text("Compact").tag(DockSpacing?.some(.compact))
                    Text("Comfortable").tag(DockSpacing?.some(.comfortable))
                    Text("Airy").tag(DockSpacing?.some(.airy))
                }
            }

            section {
                Text("Widgets")
            } content: {
                List {
                    ForEach(store.widgetLayout.order, id: \.self) { widget in
                        widgetRow(widget)
                    }
                    .onMove { store.setWidgetLayout(store.widgetLayout.moving(from: $0, to: $1)) }
                }
                .listStyle(.plain)
                .frame(height: CGFloat(store.widgetLayout.order.count) * 38 + 24)
                presetControls
                contextPresetControls
            }

            section {
                DisclosureGroup(isExpanded: $showsFineTune) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Exact values for power users. Bar height is capped at what still fits this screen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        sliderRow(Text("Bar Height"),
                                  value: store.dockPanelHeight.points,
                                  range: DockPanelHeight.minimum...fittingMaximumBarHeight, step: 1) {
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
                        sliderRow(Text("Distance From Edge"), value: store.bottomGap,
                                  range: PanelLayoutMetrics.bottomGapRange, step: 1) {
                            store.setBottomGap($0)
                        }
                        Text("Floating keeps the bar 8 pt above the screen edge. Hugging sits it almost on the edge.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if NSScreen.screens.count > 1 {
                            Text("Displays").font(.subheadline.weight(.semibold)).padding(.top, 4)
                            ForEach(NSScreen.screens, id: \.self) { screen in
                                if let uuid = DisplayIdentity.uuidString(for: screen) {
                                    displayPlacementRow(name: screen.localizedName, uuid: uuid)
                                }
                            }
                        }
                        Text("Widget Widths").font(.subheadline.weight(.semibold)).padding(.top, 4)
                        ForEach([BarSection.weather, .media, .clock], id: \.self) { widget in
                            sliderRow(widgetLabel(widget),
                                      value: store.widgetWidths[widget.rawValue] ?? widget.defaultWidgetWidth,
                                      range: 60...400, step: 5) {
                                store.setWidgetWidth($0, for: widget)
                            }
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Fine-tune").font(.headline)
                }
            } content: {
                EmptyView()
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
                .pickerStyle(.menu)
                .fixedSize()
                // Phase 18g/18h: what an edge bar does when the dock rail takes its side.
                segmentedRow(Text("Edge Bar on the Dock's Side"), selection: Binding(
                    get: { store.edgeConflictPolicy },
                    set: { store.setEdgeConflictPolicy($0) }
                )) {
                    Text("Move Across").tag(EdgeConflictPolicy.moveAcross)
                    Text("Hide").tag(EdgeConflictPolicy.hide)
                }
                .disabled(store.stripPlacementMap.global == .bottom)
                HStack {
                    Text("Main Side")
                    Spacer(minLength: 12)
                    Picker("Main Side", selection: Binding(
                        get: { store.edgePrimarySide },
                        set: { store.setEdgePrimarySide($0) }
                    )) {
                        Text("Left").tag(EdgeSide.left)
                        Text("Right").tag(EdgeSide.right)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .disabled(store.edgeBarPreset == .off || store.edgeBarPreset == .custom)
                }
                if store.edgeBarPreset == .custom {
                    customRows
                } else if store.edgeBarPreset != .off {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Widgets").font(.subheadline.weight(.semibold))
                        ForEach(WidgetTile.allCases, id: \.self) { tile in
                            Toggle(isOn: Binding(
                                get: { store.widgetTiles.contains(tile) },
                                set: { store.setWidgetTile(tile, enabled: $0) }
                            )) {
                                Self.itemTitle(EdgeItem.allCases.first { $0.widget == tile } ?? .weather)
                            }
                        }
                    }
                }
                Toggle("Keep Edge Bars Open", isOn: Binding(
                    get: { store.deckKeepOpen },
                    set: { store.setDeckKeepOpen($0) }
                ))
                .disabled(store.edgeBarPreset == .off)
                if store.edgeBarPreset != .off {
                    deckControls
                }
                Toggle("Sync Notes with iCloud Drive", isOn: Binding(
                    get: { store.notesSyncEnabled },
                    set: { store.setNotesSyncEnabled($0) }
                ))
                Text("Slim bars on the screen edges for notes, productivity and system status. Pick a layout, flip it to either side, or choose Custom to place each item yourself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            section {
                Text("Window Chips")
            } content: {
                HStack {
                    Text("Multiple Windows")
                    Spacer(minLength: 12)
                    Picker("Multiple Windows", selection: Binding(
                        get: { store.chipGroupingPlan.defaultPolicy },
                        set: { store.setChipGroupingDefault($0) }
                    )) {
                        Text("One chip per window").tag(WindowChipGroupPolicy.separate)
                        Text("Group by app").tag(WindowChipGroupPolicy.grouped)
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
                ForEach(store.chipGroupingPlan.overrides.keys.sorted(), id: \.self) { bundleID in
                    HStack {
                        Text(verbatim: Self.appName(forBundleID: bundleID))
                        Spacer(minLength: 12)
                        Picker("Multiple Windows", selection: Binding(
                            get: { store.chipGroupingPlan.overrides[bundleID] ?? store.chipGroupingPlan.defaultPolicy },
                            set: { store.setChipGrouping($0, forBundleID: bundleID) }
                        )) {
                            Text("One chip per window").tag(WindowChipGroupPolicy.separate)
                            Text("Group by app").tag(WindowChipGroupPolicy.grouped)
                        }
                        .labelsHidden().pickerStyle(.menu).fixedSize()
                        Button("Remove") { store.setChipGrouping(nil, forBundleID: bundleID) }
                    }
                }
                Menu {
                    ForEach(Self.runningAppChoices(excluding: Set(store.chipGroupingPlan.overrides.keys)), id: \.bundleID) { app in
                        Button(app.name) {
                            let other: WindowChipGroupPolicy = store.chipGroupingPlan.defaultPolicy == .grouped ? .separate : .grouped
                            store.setChipGrouping(other, forBundleID: app.bundleID)
                        }
                    }
                } label: {
                    Text("Add App…")
                }
                .fixedSize()
                Text("A grouped app shows one chip with a window count; clicking it cycles the app's windows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Show All Running Apps", isOn: Binding(
                    get: { store.showAllRunningApps },
                    set: { store.setShowAllRunningApps($0) }
                ))
                Text("Gives every running app a chip, even when it has no open window — like the system Dock.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Hover Preview", isOn: Binding(
                    get: { store.chipPreviewEnabled },
                    set: { store.setChipPreviewEnabled($0) }
                ))
                if store.chipPreviewEnabled {
                    HStack {
                        Text("Preview Delay")
                        Spacer(minLength: 12)
                        Picker("Preview Delay", selection: Binding(
                            get: { store.chipPreviewDelayMs },
                            set: { store.setChipPreviewDelayMs($0) }
                        )) {
                            Text("Fast").tag(150)
                            Text("Normal").tag(350)
                            Text("Slow").tag(600)
                        }
                        .labelsHidden().pickerStyle(.segmented).fixedSize()
                    }
                    HStack {
                        Text("Preview Size")
                        Spacer(minLength: 12)
                        Picker("Preview Size", selection: Binding(
                            get: { store.chipPreviewThumbWidth },
                            set: { store.setChipPreviewThumbWidth($0) }
                        )) {
                            Text("Small").tag(140)
                            Text("Medium").tag(180)
                            Text("Large").tag(240)
                        }
                        .labelsHidden().pickerStyle(.segmented).fixedSize()
                    }
                    if !CGPreflightScreenCaptureAccess() {
                        Text("Window previews need Screen Recording permission. Without it, previews show titles only.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Allow Screen Recording") { _ = CGRequestScreenCaptureAccess() }
                    }
                }
                Toggle("Classic Right-Click Menu", isOn: Binding(
                    get: { store.chipClassicMenu },
                    set: { store.setChipClassicMenu($0) }
                ))
                Text("Right-click a window chip for a floating jump list above the dock. Turn this on to use the system menu instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            section {
                Text("Launcher")
            } content: {
                HStack {
                    Text("Scroll Direction")
                    Spacer(minLength: 12)
                    Picker("Scroll Direction", selection: Binding(
                        get: { store.launcherScrollDirection },
                        set: { store.setLauncherScrollDirection($0) }
                    )) {
                        Text("Sideways").tag(LauncherScrollDirection.horizontal)
                        Text("Down").tag(LauncherScrollDirection.vertical)
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize()
                }
                HStack {
                    Text("Hidden Apps")
                    Spacer(minLength: 12)
                    Text(verbatim: "\(launcherHiddenCount)").foregroundStyle(.secondary)
                    Button("Show All Hidden Apps") { updateLauncherState { $0.hidden = [] } }
                        .disabled(launcherHiddenCount == 0)
                }
                Button("Reset App Order") { updateLauncherState { $0.order = [] } }
                DisclosureGroup("Hide Rarely Used Apps") {
                    HStack {
                        Button("Hide All Suggested") { updateLauncherState { $0.hidden = LauncherHidePresets.hidingAll($0.hidden) } }
                        Button("Restore Suggested") { updateLauncherState { $0.hidden = LauncherHidePresets.restoringAll($0.hidden) } }
                    }
                    ForEach(LauncherHidePresets.entries, id: \.bundleID) { entry in
                        Toggle(isOn: Binding(
                            get: { launcherHiddenIDs.contains(entry.bundleID) },
                            set: { _ in updateLauncherState { $0.hidden = LauncherOrdering.toggleHidden($0.hidden, entry.bundleID) } }
                        )) { Text(verbatim: entry.name) }
                    }
                }
                HStack {
                    Text("Search Position")
                    Spacer(minLength: 12)
                    Picker("Search Position", selection: Binding(
                        get: { store.launcherSearchPosition },
                        set: { store.setLauncherSearchPosition($0) }
                    )) {
                        Text("Top").tag(LauncherSearchPosition.top)
                        Text("Bottom").tag(LauncherSearchPosition.bottom)
                        Text("Left").tag(LauncherSearchPosition.left)
                        Text("Right").tag(LauncherSearchPosition.right)
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
                HStack {
                    Text("Theme")
                    Spacer(minLength: 12)
                    Picker("Theme", selection: Binding(get: { store.launcherTheme }, set: { store.setLauncherTheme($0) })) {
                        Text("System").tag(LauncherTheme.system)
                        Text("Light").tag(LauncherTheme.light)
                        Text("Dark").tag(LauncherTheme.dark)
                        Text("Glass").tag(LauncherTheme.glass)
                        Text("Desktop Picture").tag(LauncherTheme.desktop)
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
                HStack {
                    Text("Tint")
                    Spacer(minLength: 12)
                    Picker("Tint", selection: Binding(get: { store.launcherTint }, set: { store.setLauncherTint($0) })) {
                        Text("None").tag(LauncherTint.none)
                        Text("Blue").tag(LauncherTint.blue)
                        Text("Purple").tag(LauncherTint.purple)
                        Text("Pink").tag(LauncherTint.pink)
                        Text("Orange").tag(LauncherTint.orange)
                        Text("Green").tag(LauncherTint.green)
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
                HStack {
                    Text("Launcher Icon")
                    Spacer(minLength: 12)
                    ForEach(LauncherIconStyle.allCases, id: \.self) { style in
                        Button { store.setLauncherIcon(style) } label: {
                            VStack(spacing: 4) {
                                LauncherIconView(style: style, size: 38)
                                iconName(style).font(.caption)
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, lineWidth: store.launcherIcon == style ? 2 : 0))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            section {
                Text("Control Center")
            } content: {
                HStack {
                    Text("Side")
                    Spacer(minLength: 12)
                    Picker("Side", selection: Binding(
                        get: { EdgeSide(rawValue: controlCenterSideRaw) ?? .right },
                        set: { controlCenterSideRaw = $0.rawValue }
                    )) {
                        Text("Left").tag(EdgeSide.left)
                        Text("Right").tag(EdgeSide.right)
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize()
                }
                HStack {
                    Text("Size")
                    Spacer(minLength: 12)
                    Picker("Size", selection: Binding(
                        get: { store.controlCenterSize },
                        set: { store.setControlCenterSize($0) }
                    )) {
                        Text("Small").tag(ControlCenterSize.small)
                        Text("Medium").tag(ControlCenterSize.medium)
                        Text("Large").tag(ControlCenterSize.large)
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize()
                }
                HStack {
                    Text("Anchor")
                    Spacer(minLength: 12)
                    Picker("Anchor", selection: Binding(
                        get: { store.controlCenterAnchor },
                        set: { store.setControlCenterAnchor($0) }
                    )) {
                        Text("Top").tag(ControlCenterAnchor.top)
                        Text("Center").tag(ControlCenterAnchor.center)
                        Text("Bottom").tag(ControlCenterAnchor.bottom)
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize()
                }
                HStack {
                    Text("Animation")
                    Spacer(minLength: 12)
                    Picker("Animation", selection: Binding(
                        get: { store.controlCenterAnimation },
                        set: { store.setControlCenterAnimation($0) }
                    )) {
                        Text("Instant").tag(ControlCenterAnimation.instant)
                        Text("Fade").tag(ControlCenterAnimation.fade)
                        Text("Slide").tag(ControlCenterAnimation.slide)
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize()
                }
                Text("Widgets").font(.subheadline).padding(.top, 6)
                ForEach(TileKind.controlCenterDefault, id: \.self) { kind in
                    Toggle(isOn: Binding(get: { store.controlCenterWidgets.contains(kind) }, set: { store.setControlCenterWidget(kind, enabled: $0) })) {
                        controlCenterWidgetTitle(kind)
                    }
                }
                Text("Quick Settings").font(.subheadline).padding(.top, 6)
                ForEach(QuickToggleID.defaultOrder, id: \.self) { id in
                    Toggle(isOn: Binding(get: { store.controlCenterToggles.contains(id) }, set: { store.setControlCenterToggle(id, enabled: $0) })) {
                        id.title
                    }
                }
            }

            section {
                Text("Shortcuts")
            } content: {
                let duplicated = ShortcutConflicts.duplicated(store.shortcutBindings)
                ForEach(ShortcutAction.allCases, id: \.self) { action in
                    HStack {
                        shortcutActionTitle(action)
                        if duplicated.contains(action) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                                .help(Text("Another action uses the same shortcut"))
                        }
                        Spacer(minLength: 12)
                        Picker(selection: Binding(get: { store.shortcutBindings[action] ?? .off }, set: { store.setShortcut(action, $0) })) {
                            Text("Off").tag(ShortcutTrigger.off)
                            Divider()
                            ForEach(ShortcutChord.allCases, id: \.self) { Text(verbatim: $0.glyphs).tag(ShortcutTrigger.chord($0)) }
                            Divider()
                            ForEach(ShortcutTapKey.allCases, id: \.self) { key in
                                (Text("Double-tap") + Text(verbatim: " \(key.glyph) (\(key.isRight ? "R" : "L"))")).tag(ShortcutTrigger.doubleTap(key))
                            }
                            if case let .key(custom) = store.shortcutBindings[action] ?? .off {
                                Divider()
                                Text(verbatim: custom.glyphs).tag(ShortcutTrigger.key(custom))
                            }
                            if store.hyperkeyEnabled {
                                Divider()
                                ForEach(ShortcutKeyNames.hyperChoices, id: \.self) { code in
                                    Text(verbatim: "Hyper+" + (ShortcutKeyNames.name(for: code) ?? "?")).tag(ShortcutTrigger.hyper(code))
                                }
                            }
                        } label: { EmptyView() }
                        .pickerStyle(.menu).fixedSize()
                        ShortcutRecorderButton { store.setShortcut(action, .key($0)) }
                    }
                }
                Text("Pick a shortcut from the list, or press Record and type a key combination with ⌃, ⌥, ⇧ or ⌘.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Toggle("Use Caps Lock as Hyper Key", isOn: Binding(
                    get: { store.hyperkeyEnabled },
                    set: { on in
                        if on, !HyperkeyService.hasPermission { HyperkeyService.requestPermission() }
                        store.setHyperkeyEnabled(on)
                    }
                ))
                Text("Hyper turns Caps Lock into ⌃⌥⇧⌘. It listens to keyboard events only, needs the Input Monitoring permission, and Caps Lock is restored when you turn it off or quit.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if store.hyperkeyEnabled, !HyperkeyService.hasPermission {
                    Button("Open Input Monitoring Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") { NSWorkspace.shared.open(url) }
                    }
                }
                Toggle("Open Launcher with Pinch", isOn: Binding(get: { store.launcherPinch }, set: { store.setLauncherPinch($0) }))
                Text("Pinch four or more fingers together on the trackpad. Turn off Launchpad under System Settings > Trackpad > More Gestures, or macOS opens its own app list too.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Open Trackpad Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.trackpad") { NSWorkspace.shared.open(url) }
                }
                Text("Double-tap shortcuts need the Accessibility permission. ⌃Space may also switch input sources.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Self.margin)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            let hidden = LauncherStore(url: LauncherStore.defaultURL).load().hidden
            launcherHiddenCount = hidden.count
            launcherHiddenIDs = Set(hidden)
        }
    }

    private func controlCenterWidgetTitle(_ kind: TileKind) -> Text {
        switch kind {
        case .network: return Text("Network")
        case .battery: return Text("Battery")
        case .batteries: return Text("Batteries")
        default: return Text(verbatim: "\(kind)")
        }
    }

    private func shortcutActionTitle(_ action: ShortcutAction) -> Text {
        switch action {
        case .launcher: return Text("Launcher")
        case .pinboard: return Text("Control Center")
        case .quickSettings: return Text("Quick Settings")
        case .keepAwake: return Text("Keep Awake")
        case .drawer: return Text("Drawer")
        case .notchTools: return Text("Notch Tools")
        case .weather: return Text("Weather")
        case .clock: return Text("Clock")
        case .commandBar: return Text("Command Bar")
        }
    }

    private func edgePrefBinding<V>(_ key: WritableKeyPath<EdgeBarPrefs, V>) -> Binding<V> {
        Binding(get: { store.edgePrefs[keyPath: key] },
                set: { var p = store.edgePrefs; p[keyPath: key] = $0; store.setEdgePrefs(p) })
    }

    private func edgePrefRow<C: View>(_ title: LocalizedStringKey, @ViewBuilder _ control: () -> C) -> some View {
        HStack { Text(title); Spacer(minLength: 12); control() }
    }

    /// Look and behaviour of the deck itself (7A-D6).
    private var deckControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach([EdgeSide.left, EdgeSide.right], id: \.self) { side in
                HStack(spacing: 10) {
                    (side == .left ? Text("Left Bar Size") : Text("Right Bar Size")).frame(width: 150, alignment: .leading)
                    Slider(value: Binding(get: { store.deckScale(for: side) }, set: { store.setDeckScale($0, for: side) }),
                           in: DeckSettingsRules.scaleRange, step: 0.05)
                    Text(verbatim: "\(Int((store.deckScale(for: side) * 100).rounded()))%")
                        .monospacedDigit().foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
                }
            }
            Toggle("Magnify Buttons Under the Pointer", isOn: Binding(get: { store.deckMagnify }, set: { store.setDeckMagnify($0) }))
            edgePrefRow("Magnify Amount") {
                Picker("Magnify Amount", selection: edgePrefBinding(\.magnifyAmount)) {
                    Text("Subtle").tag(EdgeMagnifyAmount.subtle)
                    Text("Standard").tag(EdgeMagnifyAmount.standard)
                    Text("Bold").tag(EdgeMagnifyAmount.bold)
                }.labelsHidden().pickerStyle(.segmented).fixedSize()
            }
            HStack(spacing: 10) {
                Text("Open Delay").frame(width: 150, alignment: .leading)
                Slider(value: edgePrefBinding(\.openDelay), in: EdgeBarPrefs.openDelayRange, step: 0.05)
                Text(verbatim: String(format: "%.2f s", store.edgePrefs.openDelay))
                    .monospacedDigit().foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
            }
            HStack(spacing: 10) {
                Text("Edge Sensitivity").frame(width: 150, alignment: .leading)
                Slider(value: edgePrefBinding(\.sensitivity), in: 0...1, step: 0.05)
                Text(verbatim: "\(Int((store.edgePrefs.sensitivity * 100).rounded()))%")
                    .monospacedDigit().foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
            }
            ForEach([EdgeSide.left, EdgeSide.right], id: \.self) { side in
                HStack(spacing: 10) {
                    (side == .left ? Text("Left Bar Height") : Text("Right Bar Height")).frame(width: 150, alignment: .leading)
                    Slider(value: Binding(get: { 1 - store.deckYRatio(for: side) }, set: { store.setDeckYRatio(1 - $0, for: side) }), in: 0...1)
                    Text(verbatim: "\(Int(((1 - store.deckYRatio(for: side)) * 100).rounded()))%")
                        .monospacedDigit().foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
                }
            }
            edgePrefRow("Button Icons") {
                Picker("Button Icons", selection: edgePrefBinding(\.iconSet)) {
                    Text("Classic").tag(EdgeIconSet.classic)
                    Text("Modern").tag(EdgeIconSet.modern)
                    Text("Realistic").tag(EdgeIconSet.realistic)
                }.labelsHidden().pickerStyle(.segmented).fixedSize()
            }
            Toggle("Open Only on Click", isOn: edgePrefBinding(\.openOnClick))
            Toggle("Show Button Names on Hover", isOn: edgePrefBinding(\.hoverLabels))
            edgePrefRow("Flyout Style") {
                Picker("Flyout Style", selection: edgePrefBinding(\.flyoutStyle)) {
                    Text("Modern").tag(EdgeFlyoutStyle.modern)
                    Text("Glass").tag(EdgeFlyoutStyle.glass)
                }.labelsHidden().pickerStyle(.segmented).fixedSize()
            }
            HStack {
                Text("Button Style")
                Spacer(minLength: 12)
                Picker("Button Style", selection: Binding(get: { store.edgeTileStyle }, set: { store.setEdgeTileStyle($0) })) {
                    Text("Glass").tag(EdgeTileStyle.glass)
                    Text("Coloured").tag(EdgeTileStyle.coloured)
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
            }
            HStack {
                Text("Note Tab Font")
                Spacer(minLength: 12)
                Picker("Note Tab Font", selection: Binding(get: { store.deckTabFont }, set: { store.setDeckTabFont($0) })) {
                    ForEach(DeckFont.faces, id: \.postScript) { face in
                        if face.postScript.isEmpty { Text("System").tag(face.postScript) } else { Text(verbatim: face.name).tag(face.postScript) }
                    }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            Toggle("Preview Notes on Hover", isOn: Binding(get: { store.deckTabPreview }, set: { store.setDeckTabPreview($0) }))
            Toggle("Open Notes on Hover", isOn: Binding(get: { store.deckOpenOnHover }, set: { store.setDeckOpenOnHover($0) }))
            Button("Reset Bar Positions") {
                store.setDeckYRatio(0.5, for: .left)
                store.setDeckYRatio(0.5, for: .right)
            }
        }
    }

    private static func presetTitle(_ preset: EdgeBarPreset) -> Text {
        switch preset {
        case .off: return Text("Off")
        case .notes: return Text("Notes")
        case .notesAndStatus: return Text("Notes & Status")
        case .status: return Text("Status")
        case .productivityAndRest: return Text("Productivity + Rest")
        case .custom: return Text("Custom")
        }
    }

    /// Custom layout: one row per shown item, Left / Right / Hidden.
    private func iconName(_ style: LauncherIconStyle) -> Text {
        switch style {
        case .glass: return Text("Glass")
        case .orbit: return Text("Orbit")
        case .tiles: return Text("Tiles")
        case .petal: return Text("Petal")
        case .themed: return Text("Themed")
        }
    }

    @State private var launcherHiddenCount = 0
    @State private var launcherHiddenIDs: Set<String> = []

    /// Edits the launcher's saved arrangement (hidden apps, custom order); the launcher re-reads it each time it opens.
    private func updateLauncherState(_ edit: (inout LauncherState) -> Void) {
        let launcherStore = LauncherStore(url: LauncherStore.defaultURL)
        var state = launcherStore.load()
        edit(&state)
        try? launcherStore.save(state)
        launcherHiddenCount = state.hidden.count
        launcherHiddenIDs = Set(state.hidden)
    }

    private var customRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(EdgeItem.allCases.filter { $0.isBuilt() }, id: \.self) { item in
                HStack {
                    Self.itemTitle(item)
                    Spacer(minLength: 12)
                    Picker(selection: Binding(
                        get: { store.edgePlacement(of: item) },
                        set: { store.setEdgePlacement($0, of: item) }
                    )) {
                        Text("Left").tag(EdgePlacement.left)
                        Text("Right").tag(EdgePlacement.right)
                        Text("Hidden").tag(EdgePlacement.hidden)
                    } label: { Self.itemTitle(item) }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
        }
    }

    private static func itemTitle(_ item: EdgeItem) -> Text {
        switch item {
        case .notes: return Text("Notes")
        case .newNote: return Text("New Note")
        case .settings: return Text("Settings")
        case .status: return Text("Status")
        case .weather: return Text("Weather")
        case .nowPlaying: return Text("Now Playing")
        case .bluetooth: return Text("Bluetooth")
        case .systemMonitor: return Text("System")
        case .reminders: return Text("Reminders")
        case .alarms: return Text("Alarms")
        case .time: return Text("Time")
        case .tasks: return Text("Tasks")
        case .clipboard: return Text("Clipboard")
        case .capture: return Text("Capture")
        case .windows: return Text("Windows")
        case .screenshot: return Text("Copy Screenshot")
        case .screenTime: return Text("Screen Time")
        }
    }

    private static func appName(forBundleID bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private static func runningAppChoices(excluding: Set<String>) -> [(bundleID: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (bundleID: String, name: String)? in
                guard let bid = app.bundleIdentifier, !excluding.contains(bid) else { return nil }
                return (bid, app.localizedName ?? bid)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func widgetLabel(_ widget: BarSection) -> Text {
        switch widget {
        case .weather: return Text("Weather")
        case .media: return Text("Now Playing")
        case .launcher: return Text("Launcher")
        case .apps: return Text("Apps")
        case .widgets: return Text("Widgets")
        case .clock: return Text("Clock")
        }
    }

    /// 10a-7: pick a preset per time window; fixed windows (Work Hours Mon–Fri 09:00–17:00, Evening 18:00–23:00).
    private var contextPresetControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { store.contextPresetsEnabled }, set: store.setContextPresetsEnabled)) {
                Text("Context Presets")
            }
            if store.contextPresetsEnabled {
                contextPicker(Text("Work Hours"), selection: store.contextWorkPresetID, set: store.setContextWorkPreset)
                contextPicker(Text("Evening"), selection: store.contextEveningPresetID, set: store.setContextEveningPreset)
                Text(verbatim: "Mon–Fri 09:00–17:00 · 18:00–23:00")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func contextPicker(_ label: Text, selection: String, set: @escaping (String) -> Void) -> some View {
        HStack {
            label
            Spacer(minLength: 8)
            Picker("Presets", selection: Binding(get: { selection }, set: set)) {
                Text("None").tag("")
                ForEach(WidgetPresets.builtIns + store.userWidgetPresets) { Text($0.localizedTitle).tag($0.id) }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private var presetControls: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(WidgetPresets.builtIns) { preset in
                    Button(preset.localizedTitle) { store.applyWidgetPreset(preset) }
                }
                if !store.userWidgetPresets.isEmpty {
                    Divider()
                    ForEach(store.userWidgetPresets) { preset in
                        Button(preset.name) { store.applyWidgetPreset(preset) }
                    }
                    Divider()
                    Menu("Delete") {
                        ForEach(store.userWidgetPresets) { preset in
                            Button(preset.name) { store.deleteWidgetPreset(id: preset.id) }
                        }
                    }
                }
            } label: {
                Text("Presets")
            }
            .fixedSize()
            TextField("Name", text: $newPresetName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 160)
            Button("Save Current Layout") {
                store.saveCurrentWidgetLayout(as: newPresetName)
                newPresetName = ""
            }
            .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    /// One reorderable row: name, S/M/L (sizable widgets only), show/hide (never for Apps).
    private func widgetRow(_ widget: BarSection) -> some View {
        let instance = store.widgetLayout.instance(for: widget)
        return HStack(spacing: 10) {
            widgetLabel(widget)
                .foregroundStyle(instance.isVisible ? .primary : .secondary)
            Spacer(minLength: 8)
            if widget.supportsWidgetSizes {
                Picker("Size", selection: Binding(
                    get: { instance.size },
                    set: { store.setWidgetSize($0, for: widget) }
                )) {
                    Text("Small").tag(WidgetSize.small)
                    Text("Medium").tag(WidgetSize.medium)
                    Text("Large").tag(WidgetSize.large)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                .disabled(!instance.isVisible)
            }
            if widget != .apps {
                Button {
                    store.setWidgetLayout(store.widgetLayout.updating(widget) { $0.isVisible.toggle() })
                } label: {
                    Image(systemName: instance.isVisible ? "eye" : "eye.slash")
                }
                .buttonStyle(.borderless)
                .help(instance.isVisible ? Text("Hide") : Text("Show"))
            }
        }
        .frame(height: 30)
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

    /// Fine-tune's Bar Height cap on the dock's screen (never below the current value, so the
    /// slider can always show where the bar is).
    private var fittingMaximumBarHeight: CGFloat {
        let cap = DockStyleFit.maximumBarHeight(
            mode: store.barLayoutMode, gap: store.islandGap, margin: store.islandMargin, bottomGap: store.bottomGap,
            screenWidth: dockScreenWidth, widgetOrder: store.widgetLayout.visibleOrder,
            range: DockPanelHeight.minimum...DockPanelHeight.maximum)
        return max(cap, store.dockPanelHeight.points, DockPanelHeight.minimum + 1)
    }

    /// One display's placement override; "Same as All Displays" clears it (Phase 18h, decision 5).
    private func displayPlacementRow(name: String, uuid: String) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: name).lineLimit(1).frame(width: 150, alignment: .leading)
            Picker(selection: Binding<StripPlacement?>(
                get: { store.stripPlacementMap.perDisplay[uuid] },
                set: { store.setStripPlacement($0 ?? store.stripPlacementMap.global, forDisplay: uuid) }
            )) {
                Text("Same as All Displays").tag(StripPlacement?.none)
                Text("Bottom").tag(StripPlacement?.some(.bottom))
                Text("Left").tag(StripPlacement?.some(.left))
                Text("Right").tag(StripPlacement?.some(.right))
            } label: { Text(verbatim: name) }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    private func segmentedRow<Value: Hashable, Options: View>(
        _ label: Text, selection: Binding<Value>, @ViewBuilder options: () -> Options
    ) -> some View {
        HStack(spacing: 10) {
            label.frame(width: 150, alignment: .leading)
            Picker(selection: selection, content: options) { label }
                .labelsHidden()
                .pickerStyle(.segmented)
        }
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

extension QuickToggleID {
    /// Literal `Text` per case so the localization checker sees every key.
    var title: Text {
        switch self {
        case .darkMode: return Text("Dark Mode")
        case .keepAwake: return Text("Keep Awake")
        case .hideDesktopIcons: return Text("Hide Desktop")
        case .showHiddenFiles: return Text("Hidden Files")
        case .dockAutoHide: return Text("Dock Auto-hide")
        case .pathBar: return Text("Path Bar")
        case .muteMic: return Text("Mute Mic")
        case .emptyTrash: return Text("Empty Trash")
        case .ejectDisks: return Text("Eject Disks")
        case .wifi: return Text("Wi-Fi")
        case .bluetooth: return Text("Bluetooth")
        case .nightShift: return Text("Night Shift")
        case .trueTone: return Text("True Tone")
        case .vpn: return Text("VPN")
        case .screenSaver: return Text("Screen Saver")
        case .lockScreen: return Text("Lock Screen")
        case .relaunchFinder: return Text("Relaunch Finder")
        case .screenMirroring: return Text("Screen Mirroring")
        }
    }
}

/// Records one key combination (at least one of ⌃ ⌥ ⇧ ⌘). A local key monitor lives only while recording.
private struct ShortcutRecorderButton: View {
    let onRecord: (ShortcutKey) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button { recording ? stop() : start() } label: {
            if recording { Text("Press keys…") } else { Text("Record") }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }   // Esc cancels
            let f = event.modifierFlags
            var mods: UInt8 = 0
            if f.contains(.control) { mods |= ShortcutKey.control }
            if f.contains(.option) { mods |= ShortcutKey.option }
            if f.contains(.shift) { mods |= ShortcutKey.shift }
            if f.contains(.command) { mods |= ShortcutKey.command }
            let key = ShortcutKey(keyCode: event.keyCode, modifiers: mods)
            if key.isValid { onRecord(key); stop() }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
