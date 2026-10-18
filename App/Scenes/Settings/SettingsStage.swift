import SwiftUI

extension SettingsTab {
    /// Pages whose settings the stage can show changing.
    var showsStage: Bool { switch self {
        case .appearance, .widgets, .notch, .edgeBars, .controlCenter, .radialDial, .windowManagement, .shortcuts, .downloads: return true
        default: return false
        }
    }

    /// Pages whose stage shows the bar and the notch; the rest draw their own surface instead.
    var stageShowsBar: Bool {
        switch self {
        case .appearance, .widgets, .notch, .edgeBars: return true
        default: return false
        }
    }
}

/// A soft radial wash in the hour's tint (`TimeOfDayPalette`): the stage's vignette and the window's
/// glow. Off for reduced motion and increased contrast, where a drifting colour is noise.
struct SettingsTimeGlow: View {
    var opacity = 0.22
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if reduceMotion || contrast == .increased {
            Color.clear
        } else {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let c = Calendar.current.dateComponents([.hour, .minute], from: context.date)
                let tint = TimeOfDayPalette(hour: Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60).tint
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
    @State private var wallpaper: NSImage?

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
        .accessibilityElement(children: .ignore)
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
                case .controlCenter: StageControlCenter(store: store)
                case .radialDial: StageRadialDial()
                case .windowManagement: StageTiling()
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
        let islands = LayoutThumbnailModel.islands(for: store.barLayoutMode, inputs: inputs)
        let capsule = LayoutThumbnailModel.capsule(for: store.barLayoutMode, inputs: inputs)
        let rects = islands.map(\.rect) + (capsule.map { [$0] } ?? [])
        return ZStack(alignment: .topLeading) {
            ForEach(Array(rects.enumerated()), id: \.offset) { _, r in
                let frame = CGRect(x: r.minX * size.width, y: r.minY * size.height,
                                   width: max(3, r.width * size.width), height: max(3, r.height * size.height))
                RoundedRectangle(cornerRadius: min(frame.width, frame.height) * 0.32, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: min(frame.width, frame.height) * 0.32, style: .continuous)
                        .fill(Color.black.opacity(0.35)))
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func notch(scale: CGFloat) -> some View {
        let size = NotchGeometry.previewSize(for: store.notchSkin, expanded: expandsNotch)
        return NotchContinuousMaskShape(
            topCornerRadius: NotchDesignSpec.closedCornerRadii.topFlaring,
            bottomCornerRadius: NotchDesignSpec.closedCornerRadii.bottomSquircle,
            flaringTopEars: false
        )
        .fill(Color.black)
        .frame(width: size.width * scale, height: size.height * scale)
        .opacity(store.notchIslandEnabled ? 1 : 0.3)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: store.notchSkin)
    }

    private func loadWallpaper() {
        guard wallpaper == nil, let screen = NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen), !url.hasDirectoryPath else { return }
        wallpaper = NSImage(contentsOf: url)
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
            .onTapGesture(count: 2) { fraction = Double(SettingsStageSize.defaultFraction) }
            .accessibilityLabel(Text("Resize preview"))
    }
}
