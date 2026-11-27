import ImageIO
import SwiftUI

extension SettingsTab {
    /// Pages whose settings the stage can show changing.
    var showsStage: Bool { switch self {
        case .appearance, .dockItems, .appIcons, .shelf, .barWidgets, .notch, .edgeBars, .controlCenter, .radialDial, .tiling, .windowManagement, .experimental, .shortcuts, .downloads: return true
        default: return false
        }
    }

    /// Pages whose stage shows the bar and the notch; the rest draw their own surface instead.
    var stageShowsBar: Bool {
        switch self {
        case .appearance, .dockItems, .appIcons, .shelf, .barWidgets, .notch, .edgeBars: return true
        default: return false
        }
    }
}

/// Slice DI-2: writes a page's measured content height to the file named by
/// `DOCK_SETTINGS_PAGE_HEIGHT`, so "the Dock Items page is ≤ 1074 pt" is read, not eyeballed.
/// Does nothing without the switch.
struct SettingsPageHeightProbe: View {
    let tab: SettingsTab

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { Self.record(tab: tab, height: geo.size.height) }
                .onChange(of: geo.size.height) { Self.record(tab: tab, height: $0) }
        }
    }

    private static func record(tab: SettingsTab, height: CGFloat) {
        guard let path = DebugSwitch.settingsPageHeight.value() else { return }
        let line = "\(tab.rawValue) \(Int(height.rounded()))\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}

/// When the window's colour wash follows: the clock, a fixed time of day, or nothing.
enum SettingsGlowSchedule: String, CaseIterable {
    static let defaultsKey = "com.katikati.settings.glow"
    case clock, dawn, day, dusk, night, off

    /// The hour the palette is read at for the fixed choices; nil follows the clock.
    var fixedHour: Double? {
        switch self {
        case .dawn: return 6
        case .day: return 12
        case .dusk: return 18
        case .night: return 0
        case .clock, .off: return nil
        }
    }

    var title: Text {
        switch self {
        case .clock: return Text("Follow the Clock")
        case .dawn: return Text("Dawn")
        case .day: return Text("Day")
        case .dusk: return Text("Dusk")
        case .night: return Text("Night")
        case .off: return Text("Off")
        }
    }
}

/// A soft radial wash in the hour's tint (`TimeOfDayPalette`): the stage's vignette and the window's
/// glow. Off for reduced motion and increased contrast, where a drifting colour is noise.
struct SettingsTimeGlow: View {
    var opacity = 0.22
    @AppStorage(SettingsGlowSchedule.defaultsKey) private var scheduleRaw = SettingsGlowSchedule.clock.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let schedule = SettingsGlowSchedule(rawValue: scheduleRaw) ?? .clock
        if reduceMotion || contrast == .increased || schedule == .off {
            Color.clear
        } else {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let c = Calendar.current.dateComponents([.hour, .minute], from: context.date)
                let tint = TimeOfDayPalette(hour: schedule.fixedHour ?? Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60).tint
                RadialGradient(colors: [Color(red: tint.red, green: tint.green, blue: tint.blue).opacity(opacity), .clear],
                               center: .top, startRadius: 0, endRadius: 520)
                    .animation(.easeInOut(duration: 1), value: tint)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// The live preview: a miniature of the user's desktop with the bar and notch drawn from the same
/// solver and silhouettes the app uses. Like `NotchPreview` it reads no feed, media or panel and
/// starts nothing, so it can never pass invented values off as live data or trigger a permission
/// prompt; it only redraws when a setting changes.
struct SettingsStage: View {
    @ObservedObject var store: AppSettingsStore
    /// The Notch page shows the skin's open panel, so its style picker has something to change.
    var expandsNotch = false
    var tab: SettingsTab = .appearance
    var onSelectQuery: ((String) -> Void)? = nil
    @State private var wallpaper: NSImage?
    @State private var isLoadingWallpaper = false

    private static let screenAspect = LayoutThumbnailModel.referenceScreen.width / LayoutThumbnailModel.referenceScreen.height

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.06))
            SettingsTimeGlow(opacity: 0.35)
            screen
                .aspectRatio(Self.screenAspect, contentMode: .fit)
                .padding(14)
        }
        .clipped()
        .onAppear(perform: loadWallpaper)
        .accessibilityElement(children: tab == .dockItems ? .contain : .ignore)
        .accessibilityLabel(Text("Live preview"))
    }

    private var screen: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / LayoutThumbnailModel.referenceScreen.width
            ZStack(alignment: .top) {
                backdrop
                if tab.stageShowsBar {
                    bar(in: proxy.size)
                    notch(scale: scale)
                }
                switch tab {
                case .shelf: StageShelf(store: store)
                case .edgeBars: StageEdgeBars(store: store)
                case .controlCenter: StageControlCenter(store: store)
                case .radialDial: StageRadialDial()
                case .tiling: StageTiling()
                case .experimental: StageMissionControl(store: store)
                case .shortcuts: StageShortcuts(store: store)
                case .downloads: StageDownloads()
                default: EmptyView()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: store.layoutThumbnailInputs.barHeight)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: store.barLayoutMode)
    }

    @ViewBuilder
    private var backdrop: some View {
        if let wallpaper {
            Image(nsImage: wallpaper).resizable().aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(colors: [Color(red: 0.36, green: 0.45, blue: 0.78), Color(red: 0.72, green: 0.52, blue: 0.80)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func bar(in size: CGSize) -> some View {
        let inputs = store.layoutThumbnailInputs
        let vertical = inputs.placement.isVertical
        let islands = LayoutThumbnailModel.islands(for: store.barLayoutMode, inputs: inputs)
        let capsule = LayoutThumbnailModel.capsule(for: store.barLayoutMode, inputs: inputs)
        let wings = store.dockWings
        let interactive = tab == .dockItems && onSelectQuery != nil
        return ZStack(alignment: .topLeading) {
            ForEach(Array(islands.enumerated()), id: \.offset) { _, island in
                let r = island.rect
                let frame = CGRect(x: r.minX * size.width, y: r.minY * size.height,
                                   width: max(3, r.width * size.width), height: max(3, r.height * size.height))
                let iconSize = max(5, (vertical ? frame.width : frame.height) * 0.42)
                let glyphs = Group {
                    ForEach(island.sections.prefix(5), id: \.self) { sec in
                        stageSectionGlyph(sec, iconSize: iconSize, interactive: interactive)
                    }
                }
                stagePlate(frame: frame) {
                    if vertical { VStack(spacing: 2) { glyphs } } else { HStack(spacing: 2) { glyphs } }
                }
            }
            if let capsule {
                let cf = CGRect(x: capsule.minX * size.width, y: capsule.minY * size.height,
                                width: max(3, capsule.width * size.width), height: max(3, capsule.height * size.height))
                stagePlate(frame: cf) { EmptyView() }
            }
            if wings.left.preset.isAssigned, let first = islands.first {
                stageWingPlate(
                    placement: .leftWing, preset: wings.left.preset, size: size,
                    refRect: first.rect, vertical: vertical, isLeading: true, interactive: interactive
                )
            }
            if wings.right.preset.isAssigned, let lastRect = capsule ?? islands.last?.rect {
                stageWingPlate(
                    placement: .rightWing, preset: wings.right.preset, size: size,
                    refRect: lastRect, vertical: vertical, isLeading: false, interactive: interactive
                )
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    @ViewBuilder
    private func stageSectionGlyph(_ section: BarSection, iconSize: CGFloat, interactive: Bool) -> some View {
        let icon = Image(systemName: DockLivePreviewStrip.symbol(for: section))
            .font(.system(size: iconSize))
            .foregroundStyle(section == .ai ? .cyan : .white.opacity(0.85))
        if interactive {
            Button {
                onSelectQuery?(Self.queryTitle(for: section))
            } label: {
                icon
            }
            .buttonStyle(.plain)
            .contextMenu {
                if section != .apps {
                    Button("Hide") { store.setWidgetVisible(false, for: section) }
                }
            }
        } else {
            icon
        }
    }

    @ViewBuilder
    private func stageWingPlate(
        placement: DockWingPlacement,
        preset: DockWidgetPresetType,
        size: CGSize,
        refRect: CGRect,
        vertical: Bool,
        isLeading: Bool,
        interactive: Bool
    ) -> some View {
        let frame = Self.wingStageFrame(size: size, refRect: refRect, vertical: vertical, isLeading: isLeading)
        let iconSize = max(5, min(frame.width, frame.height) * 0.48)
        let plate = stagePlate(frame: frame) {
            Image(systemName: preset.symbolName).font(.system(size: iconSize)).foregroundStyle(.white.opacity(0.85))
        }
        if interactive {
            plate
                .contentShape(Rectangle())
                .onTapGesture { onSelectQuery?(String(localized: "Dock II Wings")) }
                .contextMenu {
                    if vertical {
                        Button("Swap Top & Bottom Wings") { store.swapDockWings() }
                    } else {
                        Button("Swap Left & Right Wings") { store.swapDockWings() }
                    }
                    Button("Hide Wing") { store.setDockWing(.none, placement: placement) }
                }
        } else {
            plate
        }
    }

    private static func wingStageFrame(size: CGSize, refRect: CGRect, vertical: Bool, isLeading: Bool) -> CGRect {
        if vertical {
            let w = max(3, refRect.width * size.width)
            let h = max(12, size.height * 0.085)
            let y = isLeading
                ? max(2, refRect.minY * size.height - h - 3)
                : min(size.height - h - 2, refRect.maxY * size.height + 3)
            return CGRect(x: refRect.minX * size.width, y: y, width: w, height: h)
        }
        let w = max(14, size.width * 0.08)
        let h = max(3, refRect.height * size.height)
        let x = isLeading
            ? max(2, refRect.minX * size.width - w - 3)
            : min(size.width - w - 2, refRect.maxX * size.width + 3)
        return CGRect(x: x, y: refRect.minY * size.height, width: w, height: h)
    }

    private static func queryTitle(for section: BarSection) -> String {
        switch section {
        case .utilities: return String(localized: "Mid-Dock Utilities")
        case .widgets: return String(localized: "Right FAB Style")
        case .apps: return String(localized: "Running Indicator")
        default: return String(localized: "Dock Items")
        }
    }

    private func stagePlate<Content: View>(frame: CGRect, @ViewBuilder content: () -> Content) -> some View {
        let radius = min(frame.width, frame.height) * 0.32
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.black.opacity(0.35)))
            .overlay(content())
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
    }

    private func notch(scale: CGFloat) -> some View {
        let size = NotchGeometry.previewSize(for: store.notchSkin, expanded: expandsNotch)
        let w = size.width * scale
        let h = size.height * scale
        return Group {
            switch store.notchSkin {
            case .liquid:
                VStack(spacing: max(2, 4 * scale)) {
                    HStack(spacing: max(3, 5 * scale)) {
                        ZStack {
                            NotchContinuousMaskShape(
                                topCornerRadius: NotchDesignSpec.closedCornerRadii.topFlaring,
                                bottomCornerRadius: NotchDesignSpec.closedCornerRadii.bottomSquircle,
                                flaringTopEars: false
                            )
                            .fill(Color.black)
                            .shadow(color: Color(red: 0.56, green: 0.42, blue: 0.96).opacity(0.65), radius: max(3, 6 * scale))
                            HStack {
                                RoundedRectangle(cornerRadius: max(1.5, 3 * scale))
                                    .fill(Color.pink.opacity(0.85))
                                    .frame(width: max(5, 11 * scale), height: max(5, 11 * scale))
                                Spacer()
                                HStack(spacing: 1) {
                                    ForEach([0.45, 0.9, 0.6], id: \.self) { frac in
                                        Capsule().fill(Color.pink.opacity(0.9))
                                            .frame(width: max(1, 2 * scale), height: max(3, 10 * scale * frac))
                                    }
                                }
                            }
                            .padding(.horizontal, max(3, 6 * scale))
                        }
                        .frame(width: max(46, 260 * scale), height: max(8, 28 * scale))
                        Circle()
                            .fill(Color.black)
                            .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.75))
                            .overlay(Circle().fill(Color.orange).frame(width: max(3, 7 * scale), height: max(3, 7 * scale)))
                            .frame(width: max(8, 24 * scale), height: max(8, 24 * scale))
                    }
                    if expandsNotch {
                        RoundedRectangle(cornerRadius: max(5, 14 * scale), style: .continuous)
                            .fill(Color.black)
                            .overlay(
                                RoundedRectangle(cornerRadius: max(5, 14 * scale), style: .continuous)
                                    .strokeBorder(.white.opacity(0.14), lineWidth: 0.75)
                            )
                            .shadow(color: Color(red: 0.56, green: 0.42, blue: 0.96).opacity(0.45), radius: max(4, 8 * scale))
                            .frame(width: w, height: max(18, h * 0.75))
                    }
                }
            case .dynamicIsland, .superGlass:
                RoundedRectangle(cornerRadius: expandsNotch ? max(6, 16 * scale) : max(4, 10 * scale), style: .continuous)
                    .fill(Color.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: expandsNotch ? max(6, 16 * scale) : max(4, 10 * scale), style: .continuous)
                            .strokeBorder(.white.opacity(store.notchSkin == .superGlass ? 0.34 : 0.22), lineWidth: 1)
                    )
                    .frame(width: w, height: h)
            case .boring:
                ZStack {
                    NotchContinuousMaskShape(
                        topCornerRadius: NotchDesignSpec.closedCornerRadii.topFlaring,
                        bottomCornerRadius: NotchDesignSpec.closedCornerRadii.bottomSquircle,
                        flaringTopEars: false
                    )
                    .fill(Color.black)
                    if expandsNotch {
                        HStack(spacing: max(3, 6 * scale)) {
                            RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.1))
                            RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.08))
                        }
                        .padding(max(3, 6 * scale))
                    }
                }
                .frame(width: w, height: h)
            case .classic:
                ZStack {
                    NotchContinuousMaskShape(
                        topCornerRadius: NotchDesignSpec.closedCornerRadii.topFlaring,
                        bottomCornerRadius: NotchDesignSpec.closedCornerRadii.bottomSquircle,
                        flaringTopEars: false
                    )
                    .fill(Color.black)
                    if expandsNotch {
                        RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.1))
                            .padding(max(3, 6 * scale))
                    }
                }
                .frame(width: w, height: h)
            }
        }
        .opacity(store.notchIslandEnabled ? 1 : 0.3)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: store.notchSkin)
    }

    private func loadWallpaper() {
        guard wallpaper == nil, !isLoadingWallpaper, let screen = NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen), !url.hasDirectoryPath else { return }
        isLoadingWallpaper = true
        Task.detached(priority: .utility) {
            let cg = Self.loadPreviewWallpaper(url: url, maxPixelSize: 960)
            await MainActor.run {
                if let cg {
                    wallpaper = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                }
                isLoadingWallpaper = false
            }
        }
    }

    private nonisolated static func loadPreviewWallpaper(url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// The drag handle between the stage and the controls: drag to resize, double-click to reset.
struct SettingsStageHandle: View {
    let axis: Axis
    @Binding var fraction: Double
    let available: CGFloat
    let length: CGFloat

    @State private var dragStart: CGFloat?

    var body: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.45))
            .frame(width: axis == .vertical ? 4 : 36, height: axis == .vertical ? 36 : 4)
            .frame(width: axis == .vertical ? 12 : nil, height: axis == .vertical ? nil : 12)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { (axis == .vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStart ?? length
                        dragStart = start
                        let delta = axis == .vertical ? value.translation.width : value.translation.height
                        fraction = Double(SettingsStageSize.fraction(length: start + delta, available: available))
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .onTapGesture(count: 2) {
                fraction = Double(SettingsStageSize.defaultFraction)
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            }
            .accessibilityLabel(Text("Resize preview"))
            .accessibilityValue(Text(verbatim: "\(Int(fraction * 100))%"))
            .accessibilityAdjustableAction { direction in
                let step = 0.05
                fraction = min(Double(SettingsStageSize.maxFraction), max(0.15, fraction + (direction == .increment ? step : -step)))
            }
    }
}
