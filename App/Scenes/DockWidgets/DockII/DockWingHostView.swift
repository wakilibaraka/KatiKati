import AppKit
import SwiftUI

private struct DockBadgesByBundleIDKey: EnvironmentKey {
    static let defaultValue: [String: String] = [:]
}

extension EnvironmentValues {
    var dockBadgesByBundleID: [String: String] {
        get { self[DockBadgesByBundleIDKey.self] }
        set { self[DockBadgesByBundleIDKey.self] = newValue }
    }
}

/// Observable size box updated by `PanelCoordinator` after `PanelGeometry.wingPanelFrames` resolves
/// auto-degraded (`L -> M -> S`) sizes for each wing.
@MainActor
final class DockWingResolvedSizeModel: ObservableObject {
    @Published var size: WidgetSize
    @Published var displayUUID: String?

    init(size: WidgetSize = .medium, displayUUID: String? = nil) {
        self.size = size
        self.displayUUID = displayUUID
    }
}

/// Shared floating glass container for both Left and Right Dock II wing panels.
/// Mirrors `DockStripView`'s exact `DockPanelBackdrop`, `dockPanelRim`, `dockShadow`, and
/// `shadowPadding` so wings match the main dock's material and Liquid Glass refraction pixel-for-pixel.
struct DockWingHostView: View {
    let placement: DockWingPlacement
    let usesLiquidGlass: Bool
    @ObservedObject var sizeModel: DockWingResolvedSizeModel
    var displayUUID: String? = nil
    @EnvironmentObject var settingsStore: AppSettingsStore
    @EnvironmentObject var badgeStore: BadgeStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var onOpenSettings: () -> Void = {}

    private var theme: DockThemeTokens {
        .resolved(for: colorScheme, style: settingsStore.themeMaterial)
    }

    private var activeDisplayUUID: String? { displayUUID ?? sizeModel.displayUUID }
    private var metrics: PanelLayoutMetrics { settingsStore.layoutMetrics }
    private var dockScale: CGFloat { settingsStore.dockPanelHeight.scale }
    private var cornerRadius: CGFloat { DockShape.panelCornerRadius * dockScale }

    private var slot: DockWingSlotConfig {
        settingsStore.dockWings.resolved(displayUUID: activeDisplayUUID).slot(for: placement)
    }

    private var stripPlacement: StripPlacement {
        settingsStore.stripPlacement(forDisplay: activeDisplayUUID)
    }

    var body: some View {
        let preset = slot.preset
        let activeSize = sizeModel.size
        let targetWidth = DockWingDimensions.scaledWidth(for: preset, size: activeSize, scale: dockScale)

        Group {
            if preset.isAssigned {
                ZStack {
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

                    // Smoked inner glass wash matching `DockTileChrome` so white/neon widget ink keeps
                    // crisp contrast over bright windows (while still preserving Liquid Glass refraction).
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(white: 0.085).opacity(colorScheme == .dark ? 0.36 : 0.68),
                                    Color(white: 0.045).opacity(colorScheme == .dark ? 0.46 : 0.76)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .padding(1)
                        .allowsHitTesting(false)

                    wingContent(preset: preset, size: activeSize)
                        .nativeScaled(dockScale)
                        .frame(width: targetWidth, height: metrics.panelHeight)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
                .frame(width: targetWidth, height: metrics.panelHeight)
                .dockPanelRim(
                    cornerRadius: cornerRadius,
                    style: theme.panelRimStyle(highlighted: isHovered),
                    lineWidth: theme.panelRimLineWidth(highlighted: isHovered),
                    usesLiquidGlass: usesLiquidGlass,
                    visible: true
                )
                .rotation3DEffect(
                    .degrees(isHovered && !reduceMotion ? -1.5 : 0),
                    axis: (x: 1, y: 0, z: 0),
                    perspective: 0.85
                )
                .animation(
                    reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.72),
                    value: isHovered
                )
                .onHover { isHovered = $0 }
                .dockShadow(
                    theme.stripShadow,
                    visible: DockLiquidGlassConfiguration.stripShadowVisible(
                        usesLiquidGlass: usesLiquidGlass,
                        usesSystemVariant: DockGlassPresentation.usesSystemVariant
                    )
                )
                .padding(PanelCoordinator.shadowPadding)
                .environment(\.widgetSize, activeSize)
                .environment(\.dockPopoverEdge, stripPlacement.previewEdge)
                .environment(\.dockBadgesByBundleID, badgeStore.badgesByBundleID)
                .environment(\.dockThemeStyle, settingsStore.themeMaterial)
                .environment(\.themeTuning, ThemeTuning.resolved(
                    vibrancy: settingsStore.themeVibrancy,
                    contrast: settingsStore.themeContrast,
                    translucency: settingsStore.themeTranslucency
                ))
                .contextMenu {
                    wingContextMenu(currentPreset: preset, currentSize: activeSize)
                }
            }
        }
    }

    @ViewBuilder
    private func wingContent(preset: DockWidgetPresetType, size: WidgetSize) -> some View {
        switch preset {
        case .none:
            EmptyView()
        case .spotify:
            DockSpotifyWidgetView()
        case .controlCenter:
            DockControlCenterWidgetView()
        case .vpn:
            DockVpnWidgetView()
        case .friends:
            DockFriendsWidgetView(onOpenSettings: onOpenSettings)
        case .telemetry:
            DockTelemetryWidgetView()
        case .ai:
            DockAIWingWidgetView()
        }
    }

    @ViewBuilder
    private func wingContextMenu(currentPreset: DockWidgetPresetType, currentSize: WidgetSize) -> some View {
        Menu("Widget Preset") {
            ForEach(DockWidgetPresetType.allCases) { candidate in
                Button {
                    settingsStore.setDockWing(candidate, placement: placement)
                } label: {
                    if candidate == currentPreset {
                        Label(candidate.localizedTitle, systemImage: "checkmark")
                    } else {
                        Text(verbatim: candidate.localizedTitle)
                    }
                }
            }
        }
        Menu("Widget Size") {
            sizeMenuItem(Text("Small"), size: .small, current: currentSize)
            sizeMenuItem(Text("Medium"), size: .medium, current: currentSize)
            sizeMenuItem(Text("Large"), size: .large, current: currentSize)
        }
        Divider()
        Button("Wing Settings...") {
            onOpenSettings()
        }
        Button("Hide Wing") {
            settingsStore.setDockWing(.none, placement: placement)
        }
    }

    private func sizeMenuItem(_ label: Text, size: WidgetSize, current: WidgetSize) -> some View {
        Button {
            settingsStore.setDockWingSize(size, placement: placement)
        } label: {
            if size == current {
                Label { label } icon: { Image(systemName: "checkmark") }
            } else {
                label
            }
        }
    }
}

// MARK: - Universal Multi-Surface Card & Tear-Off Floating Stack (DWP-2)

/// Surface-aware modular Dock II widget card rendered inside Drawer (`PopGridPopupView`),
/// Shelf (`ShelfGridPopupView`), Background Apps (`DrawerView`), and Floating Stack.
struct DockUniversalWidgetCard: View {
    let model: UniversalWidgetModel
    let usesLiquidGlass: Bool
    var width: CGFloat = DockWidgetConfigStore.defaultStackWidth
    @ObservedObject var settingsStore: AppSettingsStore
    var onOpenSettings: () -> Void = {}

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let cardHeight = model.stackCardHeight
        let cornerRadius: CGFloat = 15

        Group {
            if model.isCollapsed {
                HStack(spacing: 8) {
                    Image(systemName: model.preset.symbolName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DockWidgetStyle.ink.opacity(0.85))
                    Text(verbatim: model.preset.localizedTitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(DockWidgetStyle.ink)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DockWidgetStyle.ink.opacity(0.55))
                }
                .padding(.horizontal, 12)
                .frame(width: width, height: cardHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    settingsStore.toggleSurfaceWidgetCollapsed(for: model.preset, on: model.surface)
                }
            } else {
                presetBody
                    .frame(width: width, height: cardHeight)
                    .environment(\.widgetSize, model.size)
            }
        }
        .background(
            ZStack {
                DockVisualEffectView(material: .hudWindow)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(white: 0.085).opacity(usesLiquidGlass ? 0.78 : 0.88))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(isHovered ? 0.24 : 0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .scaleEffect(isHovered && !reduceMotion ? 1.015 : 1.0)
        .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.76), value: isHovered)
        .onHover { isHovered = $0 }
        .contextMenu {
            Menu("Widget Size") {
                sizeButton(Text("Small"), .small)
                sizeButton(Text("Medium"), .medium)
                sizeButton(Text("Large"), .large)
            }
            Button(model.isCollapsed ? String(localized: "Expand") : String(localized: "Collapse")) {
                settingsStore.toggleSurfaceWidgetCollapsed(for: model.preset, on: model.surface)
            }
            if model.surface != .floatingStack {
                Button("Tear Off to Floating Stack") {
                    settingsStore.tearOffSurfaceWidget(model.preset, from: model.surface)
                }
            }
            Menu("Pin to Dock Wing") {
                Button("Left Wing") {
                    settingsStore.setDockWing(model.preset, size: model.size, placement: .leftWing)
                }
                Button("Right Wing") {
                    settingsStore.setDockWing(model.preset, size: model.size, placement: .rightWing)
                }
            }
            Divider()
            Button("Remove Widget") {
                settingsStore.unpinSurfaceWidget(model.preset, from: model.surface)
            }
        }
    }

    @ViewBuilder
    private var presetBody: some View {
        switch model.preset {
        case .none:
            EmptyView()
        case .spotify:
            DockSpotifyWidgetView()
        case .controlCenter:
            DockControlCenterWidgetView()
        case .vpn:
            DockVpnWidgetView()
        case .friends:
            DockFriendsWidgetView(onOpenSettings: onOpenSettings)
        case .telemetry:
            DockTelemetryWidgetView()
        case .ai:
            DockAIWingWidgetView()
        }
    }

    private func sizeButton(_ label: Text, _ size: WidgetSize) -> some View {
        Button {
            settingsStore.setSurfaceWidgetSize(size, for: model.preset, on: model.surface)
        } label: {
            if model.size == size {
                Label { label } icon: { Image(systemName: "checkmark") }
            } else {
                label
            }
        }
    }
}

/// Compact menu button added inside Drawer, Shelf, and Background Apps headers to pin Dock II presets.
struct DockSurfacePinMenuButton: View {
    let surface: WidgetSurfaceKind
    @ObservedObject var settingsStore: AppSettingsStore

    var body: some View {
        let pinned = Set(settingsStore.surfaceWidgets.attachments(for: surface).map(\.preset))
        Menu {
            ForEach(DockWidgetPresetType.allCases.filter(\.isAssigned)) { preset in
                let isPinned = pinned.contains(preset)
                Button {
                    if isPinned {
                        settingsStore.unpinSurfaceWidget(preset, from: surface)
                    } else {
                        settingsStore.pinSurfaceWidget(preset, size: .medium, to: surface)
                    }
                } label: {
                    if isPinned {
                        Label(preset.localizedTitle, systemImage: "checkmark")
                    } else {
                        Label(preset.localizedTitle, systemImage: preset.symbolName)
                    }
                }
            }
            if !pinned.isEmpty {
                Divider()
                Button("Clear Widgets") {
                    settingsStore.clearSurfaceWidgets(on: surface)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "rectangle.stack.badge.plus")
                    .font(.system(size: 11, weight: .semibold))
                if !pinned.isEmpty {
                    Text(verbatim: "\(pinned.count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                }
            }
            .foregroundStyle(Color.white.opacity(pinned.isEmpty ? 0.72 : 0.96))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(pinned.isEmpty ? 0.12 : 0.22))
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(Text("Pin Widgets"))
    }
}

/// Embedded widget deck rendered at the bottom of Drawer / Shelf / Background Apps plates.
struct DockSurfacePinnedDeck: View {
    let surface: WidgetSurfaceKind
    let usesLiquidGlass: Bool
    let width: CGFloat
    @ObservedObject var settingsStore: AppSettingsStore
    var onOpenSettings: () -> Void = {}

    var body: some View {
        let items = settingsStore.surfaceWidgets.attachments(for: surface)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                StackSectionRuleLabel(title: String(localized: "Widgets"))
                ForEach(items) { item in
                    DockUniversalWidgetCard(
                        model: item,
                        usesLiquidGlass: usesLiquidGlass,
                        width: width,
                        settingsStore: settingsStore,
                        onOpenSettings: onOpenSettings
                    )
                }
            }
            .frame(width: width, alignment: .leading)
        }
    }
}

/// Torn-off stacked-cards floating panel inspired by the vertical fanned cards concept.
struct DockFloatingWidgetStackView: View {
    let usesLiquidGlass: Bool
    @EnvironmentObject var settingsStore: AppSettingsStore
    @EnvironmentObject var badgeStore: BadgeStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var onOpenSettings: () -> Void = {}
    var onDragFinished: (CGPoint) -> Void = { _ in }

    private var theme: DockThemeTokens {
        .resolved(for: colorScheme, style: settingsStore.themeMaterial)
    }

    var body: some View {
        let items = settingsStore.surfaceWidgets.attachments(for: .floatingStack)
        if !items.isEmpty {
            VStack(alignment: .trailing, spacing: 8) {
                headerPill(count: items.count)

                VStack(spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        let tilt: Double = (reduceMotion || isHovered || items.count == 1)
                            ? 0
                            : (idx % 2 == 0 ? -1.4 : 1.4)
                        DockUniversalWidgetCard(
                            model: item,
                            usesLiquidGlass: usesLiquidGlass,
                            width: DockWidgetConfigStore.defaultStackWidth,
                            settingsStore: settingsStore,
                            onOpenSettings: onOpenSettings
                        )
                        .rotationEffect(.degrees(tilt))
                        .shadow(color: Color.black.opacity(0.10), radius: 4, x: 0, y: 2)
                        .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 7)
                    }
                }
                .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.8), value: isHovered)
            }
            .padding(PanelCoordinator.shadowPadding)
            .onHover { isHovered = $0 }
            .environment(\.dockPopoverEdge, .top)
            .environment(\.dockBadgesByBundleID, badgeStore.badgesByBundleID)
            .environment(\.dockThemeStyle, settingsStore.themeMaterial)
            .environment(\.themeTuning, ThemeTuning.resolved(
                vibrancy: settingsStore.themeVibrancy,
                contrast: settingsStore.themeContrast,
                translucency: settingsStore.themeTranslucency
            ))
        }
    }

    private func headerPill(count: Int) -> some View {
        HStack(spacing: 8) {
            DockFloatingDragHandle(onDragFinished: onDragFinished) {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text("Widgets")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(DockWidgetStyle.ink)
                .contentShape(Rectangle())
            }

            DockSurfacePinMenuButton(surface: .floatingStack, settingsStore: settingsStore)

            Button {
                settingsStore.clearSurfaceWidgets(on: .floatingStack)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(DockWidgetStyle.ink.opacity(0.8))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .help(Text("Close Floating Stack"))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(Color(white: 0.11).opacity(0.82))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 8, x: 0, y: 4)
    }
}

private struct DockFloatingDragHandle<Content: View>: NSViewRepresentable {
    let onDragFinished: (CGPoint) -> Void
    @ViewBuilder let content: Content

    func makeNSView(context: Context) -> DragHostView<Content> {
        DragHostView(rootView: content, onDragFinished: onDragFinished)
    }

    func updateNSView(_ nsView: DragHostView<Content>, context: Context) {
        nsView.onDragFinished = onDragFinished
        nsView.update(rootView: content)
    }

    final class DragHostView<BodyView: View>: NSView {
        var onDragFinished: (CGPoint) -> Void
        private let hosting: NSHostingView<BodyView>

        init(rootView: BodyView, onDragFinished: @escaping (CGPoint) -> Void) {
            self.onDragFinished = onDragFinished
            self.hosting = NSHostingView(rootView: rootView)
            super.init(frame: .zero)
            hosting.autoresizingMask = [.width, .height]
            addSubview(hosting)
        }

        required init?(coder: NSCoder) { fatalError() }

        func update(rootView: BodyView) {
            hosting.rootView = rootView
        }

        override var intrinsicContentSize: NSSize { hosting.intrinsicContentSize }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            window.performDrag(with: event)
            let plateOrigin = CGPoint(
                x: window.frame.minX + PanelCoordinator.shadowPadding,
                y: window.frame.minY + PanelCoordinator.shadowPadding
            )
            onDragFinished(plateOrigin)
        }
    }
}

/// Dock II Wing & Universal Stack card for AI: spend, active agent turn, approvals, and Loadout.
struct DockAIWingWidgetView: View {
    @Environment(\.widgetSize) private var size
    @Environment(\.dockPopoverEdge) private var edge
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var approvals = ClaudeApprovalService.shared
    @ObservedObject private var timeTravel = SurfaceTimeTravelCoordinator.shared
    @State private var showPopover = false

    var body: some View {
        let state = AIDockPresentation.resolve(usage: usage, approvals: approvals, timeTravel: timeTravel)
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(state.tint.opacity(0.18)).frame(width: 26, height: 26)
                Image(systemName: state.icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(state.tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: state.title).font(.system(size: 11.5, weight: .semibold, design: .rounded)).foregroundStyle(DockWidgetStyle.ink).lineLimit(1)
                if size != .small { Text(verbatim: state.detail).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 2)
            if size == .large, let req = state.pendingRequest {
                Button { approvals.decide(req, .allow) } label: {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(.green)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        .onTapGesture { showPopover.toggle() }
        .popover(isPresented: $showPopover, arrowEdge: edge) { AIDockPopoverView() }
        .onAppear { usage.startMonitoring() }
        .accessibilityElement(children: .combine).accessibilityLabel(Text("AI")).accessibilityAddTraits(.isButton)
    }
}
