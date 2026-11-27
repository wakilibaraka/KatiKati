import AppKit
import SwiftUI

/// Attaches the enclosing NSWindow / NSView to `IslandSurfaceDriver` so its `CADisplayLink`
/// runs strictly in phase with the active ProMotion display.
private struct IslandDisplayLinkAnchor: NSViewRepresentable {
    let driver: IslandSurfaceDriver

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        Task { @MainActor [weak view, weak driver] in
            if let view { driver?.attach(to: view) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        driver.attach(to: nsView)
    }
}

/// Interactive Dynamic Island surface rendering closed-form metaball pills, OLED Rec. 709 keyline rims,
/// touch-adapted >= 44pt targets, 1:1 vertical pull-down drag gestures, and a Bento suite switcher.
struct IslandSurfaceView<SuiteContent: View>: View {
    @ObservedObject var driver: IslandSurfaceDriver
    @ObservedObject var registry: IslandPresetRegistry
    var themeResolution: NotchTheme.Resolution? = nil
    var suiteTitle: String = String(localized: "Suite")
    var activityTabTitle: String = String(localized: "Activity")
    @ViewBuilder var suiteContent: () -> SuiteContent

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressingPill = false
    @State private var isPressingBubble = false
    @State private var lastDragTranslationY: Double = 0

    init(
        driver: IslandSurfaceDriver,
        registry: IslandPresetRegistry,
        themeResolution: NotchTheme.Resolution? = nil,
        @ViewBuilder suiteContent: @escaping () -> SuiteContent = { EmptyView() }
    ) {
        self.driver = driver
        self.registry = registry
        self.themeResolution = themeResolution
        self.suiteContent = suiteContent
    }

    private var effectiveReduceMotion: Bool {
        systemReduceMotion
    }

    private var resolvedKeylineAlpha: Double {
        let base = islandResolvedKeylineAlpha(
            setting: driver.keylineSetting,
            backdropLuma: nil,
            isDarkAppearance: colorScheme == .dark,
            isOLEDDisplay: driver.topology.isOLED,
            metrics: driver.metrics
        )
        return base * driver.keylineDimMultiplier
    }

    private var surfaceFillColor: Color {
        if driver.topology.cutout.isPhysicalCutout || driver.topology.isOLED {
            return .black
        }
        guard let plate = themeResolution?.plate else { return .black }
        return Color(red: plate.r, green: plate.g, blue: plate.b, opacity: plate.a)
    }

    private var isLowPowerMode: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private var usesMetalLiquidMorph: Bool {
        IslandSurfaceGlassPolicy.shouldUseMetalMorph(
            usesMetalPreset: driver.skin.usesMetalLiquidMorph,
            optInEnabled: driver.metalMorphOptIn,
            isLowPowerMode: isLowPowerMode,
            reduceMotion: effectiveReduceMotion
        )
    }

    private var usesLiquidGlass: Bool {
        guard driver.skin.usesLiquidGlassBackdrop else { return false }
        return IslandSurfaceGlassPolicy.shouldUseLiquidGlass(
            hasPhysicalCutout: driver.topology.cutout.isPhysicalCutout,
            isOLED: driver.topology.isOLED,
            presentation: driver.scene.presentation,
            glassEnabled: driver.glassEnabled,
            isLowPowerMode: isLowPowerMode
        )
    }

    private var hidesAtRest: Bool {
        driver.topology.hidesAtRest(
            activeCount: driver.snapshot.activities.count,
            nonNotchBehavior: driver.nonNotchIdleBehavior
        ) && driver.scene.presentation == .idle && abs(driver.dragPullOffset) < 0.5
    }

    private var activeMeasures: IslandContentMeasure {
        let primaryViews = driver.scene.primary.map { registry.views(for: $0) }
        let detachedViews = driver.scene.detached.map { registry.views(for: $0) }
        var combined = primaryViews?.measure ?? .empty
        if let p = primaryViews, let d = detachedViews {
            combined.attached = p.measure.attached
            combined.detached = d.measure.detached
            combined.split = IslandSplitMeasure(
                attached: p.measure.split?.attached ?? IslandSlotPair(leading: p.measure.leading, trailing: 0),
                detached: d.measure.split?.detached ?? IslandSlotPair(leading: d.measure.leading, trailing: d.measure.trailing)
            )
        }
        if driver.isShowingBentoSuite && driver.scene.presentation == .expanded {
            let pad = driver.metrics.expanded.padding
            let suiteTargetHeight = max(132.0, Double(driver.preferredExpandedSize.height) - pad.top - pad.bottom)
            combined.expandedHeight = max(combined.expandedHeight, suiteTargetHeight)
        }
        return combined
    }

    var body: some View {
        let frame = driver.frame
        let scene = driver.scene
        let expandedPose = frame.drawn
        let pullOffset = driver.dragPullOffset
        let isExpanded = scene.presentation == .expanded
        let isSplit = scene.presentation == .minimal && frame.bubble.width > 0
        let stageHeight = max(driver.metrics.expanded.maxHeight + driver.metrics.top + 32, 220)

        ZStack(alignment: .topLeading) {
            IslandDisplayLinkAnchor(driver: driver)
                .frame(width: 1, height: 1)
                .opacity(0.001)

            // 2-layer OLED / expanded depth shadow matching islandcn metrics.
            if frame.shadow > 0.01 {
                let s = driver.metrics.expanded.shadow
                Path(frame.pillPath)
                    .fill(Color.black.opacity(s.opacity * frame.shadow))
                    .blur(radius: s.blur * 0.5)
                    .offset(y: s.offsetY)
                Path(frame.pillPath)
                    .fill(Color.black.opacity(s.tailStrength * frame.shadow))
                    .blur(radius: s.tailBlur * 0.5)
                    .offset(y: s.tailOffsetY)
            }

            // Combined surface silhouette: opt-in Metal SDF morph, macOS 26+ Liquid Glass (expanded / non-notch only),
            // or pure #000000 black (always enforced on closed/compact/minimal hardware notches).
            surfaceBackdropLayer(frame: frame, isExpanded: isExpanded, stageHeight: stageHeight)
                .offset(y: pullOffset * 0.35)

            // Main Pill, Idle Wide Bar, or Expanded Content Layer
            if isExpanded, let primary = scene.primary {
                let views = registry.views(for: primary)
                expandedContentLayer(views: views, frame: frame)
                    .frame(width: max(0, expandedPose.width), height: max(0, expandedPose.height))
                    .position(x: expandedPose.x + expandedPose.width / 2, y: expandedPose.y + expandedPose.height / 2 + pullOffset * 0.25)
                    .clipShape(Path(frame.clipPath))
            } else if scene.presentation == .compact, let primary = scene.primary {
                let views = registry.views(for: primary)
                compactContentLayer(views: views, box: frame.pill)
                    .frame(width: max(0, frame.pill.width), height: max(0, frame.pill.height))
                    .position(x: frame.pill.x + frame.pill.width / 2, y: frame.pill.y + frame.pill.height / 2 + pullOffset * 0.35)
                    .clipShape(Path(frame.clipPath))
            } else if isSplit, let primary = scene.primary, let detached = scene.detached {
                let primaryViews = registry.views(for: primary)
                let detachedViews = registry.views(for: detached)
                splitAttachedLayer(views: primaryViews, box: frame.pill)
                    .frame(width: max(0, frame.pill.width), height: max(0, frame.pill.height))
                    .position(x: frame.pill.x + frame.pill.width / 2, y: frame.pill.y + frame.pill.height / 2 + pullOffset * 0.35)
                    .clipShape(Path(frame.clipPath))

                splitDetachedLayer(views: detachedViews, bubble: frame.bubble)
                    .frame(width: max(0, frame.bubble.width), height: max(0, frame.bubble.height))
                    .position(x: frame.bubble.x + frame.bubble.width / 2, y: frame.bubble.y + frame.bubble.height / 2 + pullOffset * 0.35)
                    .clipShape(Path(frame.bubbleClipPath))
                    .gesture(bubbleInteractionGesture)
            } else if scene.presentation == .idle, driver.isWideBar {
                NotchWideBarView(width: max(0, frame.pill.width), height: max(0, frame.pill.height))
                    .position(x: frame.pill.x + frame.pill.width / 2, y: frame.pill.y + frame.pill.height / 2 + pullOffset * 0.35)
                    .clipShape(Path(frame.clipPath))
            }

            // Interactive pill hit box (`>= 44x44 pt` in touch mode).
            if !isExpanded {
                let rawHit = frame.pill.rect
                let hit = IslandTouchHitPolicy.interactiveHitRect(for: rawHit, touchEnabled: driver.touchMode)
                Color.clear
                    .frame(width: max(1, hit.width), height: max(1, hit.height))
                    .contentShape(Rectangle())
                    .position(x: hit.midX, y: hit.midY)
                    .gesture(pillInteractionGesture)
            }
        }
        .frame(width: driver.stageWidth, height: stageHeight, alignment: .topLeading)
        .opacity(hidesAtRest ? 0.0 : 1.0)
        .allowsHitTesting(!hidesAtRest)
        .environment(\.islandTouchMode, driver.touchMode)
        .onAppear {
            driver.reduceMotion = effectiveReduceMotion
            driver.updateContentMeasure(activeMeasures)
        }
        .onChange(of: effectiveReduceMotion) { _, next in
            driver.reduceMotion = next
        }
        .onChange(of: registry.revision) { _, _ in
            driver.updateContentMeasure(activeMeasures)
        }
        .onChange(of: driver.isShowingBentoSuite) { _, _ in
            driver.updateContentMeasure(activeMeasures)
        }
        .onChange(of: driver.scene.contentKey) { _, _ in
            driver.updateContentMeasure(activeMeasures)
        }
    }

    // MARK: - Backdrop Surfaces

    @ViewBuilder
    private func surfaceBackdropLayer(frame: IslandFrameGeometry, isExpanded: Bool, stageHeight: Double) -> some View {
        if usesMetalLiquidMorph {
            let liquidState = LiquidShapeState.from(
                islandFrame: frame,
                stageWidth: driver.stageWidth,
                topology: driver.topology,
                isExpanded: isExpanded,
                auraLab: driver.artworkAuraLab
            )
            let hasCutout = driver.topology.cutout.isPhysicalCutout
            LiquidSurfaceRepresentable(
                target: liquidState,
                notchHalfWidth: hasCutout ? driver.metrics.idle.width / 2.0 : 0,
                notchHeight: hasCutout ? driver.metrics.idle.height : 0,
                reduceMotion: true
            )
            .frame(width: driver.stageWidth, height: stageHeight)
            .allowsHitTesting(false)
        } else {
            ZStack(alignment: .topLeading) {
                if usesLiquidGlass {
                    let glassTint = DockRGBA(r: 0.04, g: 0.05, b: 0.07, a: 0.62)
                    let glassOverlay = DockRGBA(r: 0, g: 0, b: 0, a: 0.36)
                    DockGlassBackdrop(
                        material: .hudWindow,
                        usesLiquidGlass: true,
                        cornerRadius: CGFloat(max(8, frame.drawn.radius)),
                        baseTint: glassTint,
                        plateOverlay: glassOverlay
                    )
                    .frame(width: driver.stageWidth, height: stageHeight)
                    .clipShape(Path(frame.pillPath))
                    .allowsHitTesting(false)

                    if !frame.bubblePath.isEmpty {
                        DockGlassBackdrop(
                            material: .hudWindow,
                            usesLiquidGlass: true,
                            cornerRadius: CGFloat(max(8, frame.bubble.height / 2.0)),
                            baseTint: glassTint,
                            plateOverlay: glassOverlay
                        )
                        .frame(width: driver.stageWidth, height: stageHeight)
                        .clipShape(Path(frame.bubblePath))
                        .allowsHitTesting(false)
                    }
                    if !frame.bridgePath.isEmpty {
                        Path(frame.bridgePath).fill(surfaceFillColor)
                    }
                } else {
                    Path(frame.pillPath).fill(surfaceFillColor)
                    if !frame.bubblePath.isEmpty {
                        Path(frame.bubblePath).fill(surfaceFillColor)
                    }
                    if !frame.bridgePath.isEmpty {
                        Path(frame.bridgePath).fill(surfaceFillColor)
                    }
                }

                // Rec. 709 luma-adaptive rim keyline.
                if resolvedKeylineAlpha > 0.005 {
                    let strokeColor = Color.white.opacity(resolvedKeylineAlpha)
                    Path(frame.pillPath).stroke(strokeColor, lineWidth: driver.metrics.keyline.width)
                    if !frame.bubblePath.isEmpty {
                        Path(frame.bubblePath).stroke(strokeColor, lineWidth: driver.metrics.keyline.width)
                    }
                    if !frame.bridgePath.isEmpty {
                        Path(frame.bridgePath).stroke(strokeColor, lineWidth: driver.metrics.keyline.width)
                    }
                }
            }
        }
    }

    // MARK: - Slot Layouts

    @ViewBuilder
    private func compactContentLayer(views: IslandActivityViews, box: IslandBoxPose) -> some View {
        let keepout = driver.topology.cutout.keepoutWidth > 0
            ? max(driver.metrics.compact.sensorWidth, driver.topology.cutout.keepoutWidth)
            : driver.metrics.compact.sensorWidth
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                views.compactLeading
            }
            .padding(.leading, 10)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
                .frame(width: min(keepout, max(0, box.width - 56)))

            HStack(spacing: 6) {
                views.compactTrailing
            }
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func splitAttachedLayer(views: IslandActivityViews, box: IslandBoxPose) -> some View {
        let sensor = driver.metrics.compact.sensorWidth
        let leadingRoom = max(20, box.width - sensor)
        HStack(spacing: 0) {
            views.compactLeading
                .frame(width: leadingRoom, alignment: .center)
            Spacer(minLength: sensor)
        }
    }

    @ViewBuilder
    private func splitDetachedLayer(views: IslandActivityViews, bubble: IslandBubblePose) -> some View {
        views.minimal
            .frame(width: bubble.width, height: bubble.height)
    }

    @ViewBuilder
    private func expandedContentLayer(views: IslandActivityViews, frame: IslandFrameGeometry) -> some View {
        let isAlert = driver.snapshot.expanded?.reason == .alert
        if driver.skin.usesLiquidGlassBackdrop && driver.isShowingBentoSuite && !isAlert {
            suiteContent()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .gesture(expandedPullUpGesture)
                .transition(.opacity)
        } else {
            let pad = driver.metrics.expanded.padding
            VStack(alignment: .leading, spacing: driver.metrics.expanded.rowGap) {
                HStack(alignment: .center, spacing: 10) {
                    views.expandedLeading
                    views.expandedCenter
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 6) {
                        views.expandedTrailing
                        expandedModeSwitchPill
                    }
                }
                if driver.isShowingBentoSuite && !isAlert {
                    suiteContent()
                        .transition(.opacity)
                } else if let bottom = views.expandedBottom {
                    bottom
                }
            }
            .padding(.top, pad.top)
            .padding(.leading, pad.side)
            .padding(.trailing, pad.trailing)
            .padding(.bottom, pad.bottom)
            .gesture(expandedPullUpGesture)
        }
    }

    private var expandedModeSwitchPill: some View {
        IslandPillButton(
            fill: driver.isShowingBentoSuite ? IslandTheme.Accent.lagoon.opacity(0.24) : IslandTheme.Ink.fill,
            foreground: driver.isShowingBentoSuite ? IslandTheme.Accent.lagoon : IslandTheme.Ink.secondary,
            minHeight: 24,
            horizontalPadding: 9,
            accessibilityLabel: driver.isShowingBentoSuite ? activityTabTitle : suiteTitle
        ) {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                driver.isShowingBentoSuite.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: driver.isShowingBentoSuite ? "sparkles" : "square.grid.2x2")
                    .font(.system(size: 10, weight: .semibold))
                Text(driver.isShowingBentoSuite ? "Activity" : "Suite")
                    .font(.system(size: 11, weight: .semibold))
            }
        }
    }

    // MARK: - Gestures (Swell + Long-Press + 1:1 Pull-Down Drag)

    private var pillInteractionGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isPressingPill {
                    isPressingPill = true
                    driver.store.press(.pill)
                }
                if value.translation.height > 6 {
                    let dy = value.translation.height
                    lastDragTranslationY = dy
                    driver.dragPullOffset = IslandTouchHitPolicy.rubberBandedOffset(dy, dimension: 48, coefficient: 0.55)
                }
            }
            .onEnded { value in
                let dy = value.translation.height
                let velY = value.predictedEndTranslation.height - dy
                let wasPull = dy > 10 || lastDragTranslationY > 10
                isPressingPill = false
                lastDragTranslationY = 0
                if wasPull {
                    driver.store.release(cancel: true)
                    driver.finishInteractivePull(translationY: dy, velocityY: velY)
                } else {
                    driver.dragPullOffset = 0
                    driver.store.release(cancel: false)
                    if driver.store.presentation == .compact || driver.store.presentation == .minimal {
                        driver.store.expand()
                    }
                }
            }
    }

    private var bubbleInteractionGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !isPressingBubble {
                    isPressingBubble = true
                    driver.store.press(.bubble)
                }
            }
            .onEnded { _ in
                isPressingBubble = false
                driver.store.release(cancel: false)
                if let detached = driver.scene.detached {
                    driver.store.expand(detached.id)
                }
            }
    }

    private var expandedPullUpGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                if value.translation.height < 0 {
                    driver.dragPullOffset = IslandTouchHitPolicy.rubberBandedOffset(value.translation.height, dimension: 48, coefficient: 0.55)
                }
            }
            .onEnded { value in
                let dy = value.translation.height
                let velY = value.predictedEndTranslation.height - dy
                driver.finishInteractivePull(translationY: dy, velocityY: velY)
            }
    }
}
