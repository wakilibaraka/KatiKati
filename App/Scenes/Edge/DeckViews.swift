import SwiftUI

/// Everything the deck draws is driven by this model (Phase 7A-D2); the controller owns panels, timers and
/// the state machine and just publishes into it.
@MainActor
final class DeckViewModel: ObservableObject {
    @Published var state: DeckState = .rest
    /// False → tabs are off-screen (rest / exiting); true → shingled in. Flipped two frames after the panel resizes.
    @Published var revealed = false
    /// The panel is fan-sized (stays true while the exit animation plays, until the panel shrinks to the pill).
    @Published var showsFan = false
    @Published var showAll = false
    @Published var tabs: [Note] = []
    @Published var buttons: [DeckButton] = []
    @Published var tileStyle: EdgeTileStyle = .glass
    @Published var iconSet: EdgeIconSet = .classic
    @Published var barStyle: EdgeBarStyle = .paper
    @Published var magnifyPeak: CGFloat = DeckMagnification.maxScale
    @Published var scale: Double = 1
    @Published var magnify = true
    /// Pointer's y in the panel's top-left space while it is over the fanned deck (drives button magnification).
    @Published var pointerY: CGFloat?
    @Published var tabFont: String = ""
    @Published var onRight = true
    @Published var showRunningDots = true
    @Published var collapseToButton = false
    /// Pill / tile accent colours when there are no note tabs.
    @Published var accentDashes: [NotePaletteEntry] = []

    /// Tab frames in the panel's top-left view space (published by the tabs themselves); the controller turns the
    /// mouse poll into hover-preview / hover-open from these, so no SwiftUI hover callbacks are needed.
    @Published var tabFrames: [String: CGRect] = [:]
    /// Round-button frames (same space) by index in `buttons`; drives the hover-name bubble.
    @Published var buttonFrames: [Int: CGRect] = [:]

    var onTab: (String, CGRect) -> Void = { _, _ in }
    var onReorder: (String, Int) -> Void = { _, _ in }
    var onContext: (DeckContextAction, String) -> Void = { _, _ in }
    var onDragging: (Bool) -> Void = { _ in }
    /// ⌥-drag of the resting pill: `true` while moving, `false` on release.
    var onPillDrag: (Bool) -> Void = { _ in }
    var onButton: (DeckButton, CGRect) -> Void = { _, _ in }

    var metrics: DeckMetrics { DeckMetrics(scale: CGFloat(scale)) }
    var deckFont: DeckFont { DeckFont(postScript: tabFont, scale: CGFloat(scale)) }

    var visibleTabs: [Note] { showAll ? tabs : Array(tabs.prefix(DeckGeometry.fanLimit)) }
    var hiddenCount: Int { showAll ? 0 : max(0, tabs.count - DeckGeometry.fanLimit) }

    /// One layout used by both the view and the controller's panel sizing.
    func layout(panelHeight: CGFloat) -> DeckLayout {
        let font = deckFont
        let measure = font.measure
        let longest = visibleTabs.map { measure.total(VerticalLabelLayout.runs(for: $0.displayTitle.uppercased())) }.max() ?? 0
        let totalBtnHeight: CGFloat?
        if buttons.contains(where: { $0.isRichCard }) {
            let h = buttons.map { $0.cardHeight(unit: metrics.buttonSize) }.reduce(0, +)
            let gaps = CGFloat(max(0, buttons.count - 1)) * 4
            totalBtnHeight = h + gaps
        } else {
            totalBtnHeight = nil
        }
        return DeckGeometry.layout(metrics, panelHeight: panelHeight, count: visibleTabs.count,
                                   hasMore: hiddenCount > 0, longestLabel: longest, buttons: buttons.count,
                                   buttonsHeight: totalBtnHeight)
    }

    /// Items that give the pill its dashes: note tabs + button accents so 1 note never collapses the pill.
    var pillItemCount: Int {
        let raw = max(1, tabs.count + buttons.count)
        return collapseToButton ? min(3, raw) : raw
    }
}

/// A live or pinned macOS app shown on the EdgeBar (ExtraDock preset).
struct EdgeAppItem: Hashable, Identifiable, Sendable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let isRunning: Bool
    let isActive: Bool
}

/// Root view of a deck panel: the pill at rest, the fan otherwise.
struct DeckRootView: View {
    @ObservedObject var model: DeckViewModel

    var body: some View {
        ZStack {
            if model.showsFan { DeckFanView(model: model) } else { DeckPillView(model: model) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Right-click menu actions on a tab.
enum DeckContextAction: Equatable {
    case togglePin
    case archive
    case delete
    case color(Int)
}

private struct TabFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Round buttons stacked under the tabs.
enum DeckButton: Hashable {
    case app(EdgeAppItem)
    case focus
    case clock
    case batteryWifi
    case habits
    case hydration
    case food
    case notesPreview
    case bluetoothWifi
    case remindersAndTasks
    case systemAndBattery
    case timeAndAlarms
    case captureAndScreenshot
    case newNote
    case settings
    case status(StatusKind)
    case widget(WidgetTile)
    case productivity(ProductivityItem)

    var symbol: String {
        switch self {
        case .app: return "app.fill"
        case .focus: return "bolt.fill"
        case .clock: return "clock.fill"
        case .batteryWifi: return "battery.100.bolt"
        case .habits: return "square.grid.3x3.fill"
        case .hydration: return "drop.fill"
        case .food: return "fork.knife"
        case .notesPreview: return "note.text"
        case .bluetoothWifi: return "antenna.radiowaves.left.and.right"
        case .remindersAndTasks: return "checklist"
        case .systemAndBattery: return "cpu"
        case .timeAndAlarms: return "alarm.fill"
        case .captureAndScreenshot: return "camera.viewfinder"
        case .newNote: return "plus"
        case .settings: return "gearshape"
        case .status(.wifi): return "wifi"
        case .status(.battery): return "battery.100"
        case .status(.volume): return "speaker.wave.2.fill"
        case .widget(.weather): return "cloud.sun.fill"
        case .widget(.nowPlaying): return "music.note"
        case .widget(.bluetooth): return "wave.3.right.circle.fill"
        case .widget(.systemMonitor): return "cpu"
        case .productivity(.reminders): return "checklist"
        case .productivity(.alarms): return "alarm.fill"
        case .productivity(.time): return "timer"
        case .productivity(.tasks): return "list.bullet.rectangle"
        case .productivity(.clipboard): return "doc.on.clipboard"
        case .productivity(.capture): return "text.viewfinder"
        case .productivity(.screenshot): return "camera.viewfinder"
        case .productivity(.windows): return "rectangle.split.2x1"
        case .productivity(.screenTime): return "hourglass"
        }
    }

    /// Palette index for the coloured style (stable per button).
    var accent: Int {
        switch self {
        case .app: return 4
        case .focus: return 2
        case .clock: return 5
        case .batteryWifi: return 4
        case .habits: return 6
        case .hydration: return 1
        case .food: return 3
        case .notesPreview: return 0
        case .bluetoothWifi: return 4
        case .remindersAndTasks: return 3
        case .systemAndBattery: return 5
        case .timeAndAlarms: return 6
        case .captureAndScreenshot: return 2
        case .newNote: return 0
        case .settings: return 7
        case .status(.wifi): return 4
        case .status(.battery): return 5
        case .status(.volume): return 3
        case .widget(.weather): return 1
        case .widget(.nowPlaying): return 2
        case .widget(.bluetooth): return 4
        case .widget(.systemMonitor): return 6
        case .productivity(.reminders): return 3
        case .productivity(.alarms): return 6
        case .productivity(.time): return 5
        case .productivity(.tasks): return 2
        case .productivity(.clipboard): return 1
        case .productivity(.capture): return 4
        case .productivity(.screenshot): return 2
        case .productivity(.windows): return 7
        case .productivity(.screenTime): return 0
        }
    }
}

// MARK: - Bezel Dock Shape (ExtraDock)

/// Vertical bezel-melded dock silhouette with concave top and bottom flaring ears flush against the screen edge.
struct EdgeBezelDockShape: Shape {
    var onRight: Bool = true
    var earRadius: CGFloat = 10
    var cornerRadius: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        let inset: CGFloat = min(2, rect.width * 0.15)
        let span = max(1, rect.width - inset)
        let r = min(cornerRadius, span * 0.55, rect.height * 0.25)
        let ear = min(earRadius, max(0, span - r), max(0, (rect.height - 2 * r) * 0.25))
        var p = Path()
        if onRight {
            let edgeX = rect.maxX
            let innerX = rect.minX + inset
            let topY = rect.minY + ear
            let botY = rect.maxY - ear
            p.move(to: CGPoint(x: edgeX, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: edgeX - ear, y: topY), control: CGPoint(x: edgeX, y: topY))
            p.addLine(to: CGPoint(x: innerX + r, y: topY))
            p.addQuadCurve(to: CGPoint(x: innerX, y: topY + r), control: CGPoint(x: innerX, y: topY))
            p.addLine(to: CGPoint(x: innerX, y: botY - r))
            p.addQuadCurve(to: CGPoint(x: innerX + r, y: botY), control: CGPoint(x: innerX, y: botY))
            p.addLine(to: CGPoint(x: edgeX - ear, y: botY))
            p.addQuadCurve(to: CGPoint(x: edgeX, y: rect.maxY), control: CGPoint(x: edgeX, y: botY))
            p.closeSubpath()
        } else {
            let edgeX = rect.minX
            let innerX = rect.maxX - inset
            let topY = rect.minY + ear
            let botY = rect.maxY - ear
            p.move(to: CGPoint(x: edgeX, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: edgeX + ear, y: topY), control: CGPoint(x: edgeX, y: topY))
            p.addLine(to: CGPoint(x: innerX - r, y: topY))
            p.addQuadCurve(to: CGPoint(x: innerX, y: topY + r), control: CGPoint(x: innerX, y: topY))
            p.addLine(to: CGPoint(x: innerX, y: botY - r))
            p.addQuadCurve(to: CGPoint(x: innerX - r, y: botY), control: CGPoint(x: innerX, y: botY))
            p.addLine(to: CGPoint(x: edgeX + ear, y: botY))
            p.addQuadCurve(to: CGPoint(x: edgeX, y: rect.maxY), control: CGPoint(x: edgeX, y: botY))
            p.closeSubpath()
        }
        return p
    }
}

// MARK: - Pill (at rest)

struct DeckPillView: View {
    @ObservedObject var model: DeckViewModel

    private var dashes: [Color] {
        let noteColors = model.tabs.map { NotePalette.entry(at: $0.color).dashColor }
        let buttonColors = model.accentDashes.map(\.dashColor)
        let colors = noteColors + buttonColors
        let m = model.collapseToButton ? 3 : DeckGeometry.maxDashes
        return Array(colors.prefix(m)) + (colors.count > m ? [Color.secondary.opacity(0.5)] : [])
    }

    @ViewBuilder private var pillBackground: some View {
        if model.barStyle == .bezelDock || model.collapseToButton {
            EdgeBezelDockShape(onRight: model.onRight, earRadius: 6, cornerRadius: 6)
                .fill(Color(red: 0.05, green: 0.05, blue: 0.06).opacity(0.95))
                .overlay(
                    EdgeBezelDockShape(onRight: model.onRight, earRadius: 6, cornerRadius: 6)
                        .stroke(Color.white.opacity(0.16), lineWidth: 0.5)
                )
        } else if model.barStyle == .fluid {
            // One droplet, no dashes cut out of it: the note colours ride on top as glowing dots.
            FluidRailBody(centers: [], radius: model.metrics.pillWidth / 2, vertical: true,
                          lightAtStart: !model.onRight)
        } else if model.barStyle == .liquidGlass {
            EdgeGlassSurface(shape: Capsule(style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.55))
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.ultraThinMaterial))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: .black.opacity(0.22), radius: 6, x: model.onRight ? -2 : 2, y: 1)
        }
    }

    var body: some View {
        let m = model.metrics
        VStack(spacing: m.dashGap) {
            ForEach(Array((dashes.isEmpty ? [Color.secondary.opacity(0.4)] : dashes).enumerated()), id: \.offset) { _, c in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(c).frame(width: m.dashWidth, height: m.dashHeight)
            }
        }
        .padding(.vertical, m.pillPad)
        .frame(width: m.pillWidth)
        .background(pillBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.onRight ? .trailing : .leading)
        .padding(model.onRight ? .trailing : .leading, 1)
        .contentShape(Rectangle())
        .accessibilityLabel(Text("Edge Bars"))
        .help(Text("Edge Bars"))
        // The panel only accepts mouse events at rest while ⌥ is held over it, so a plain click never lands here.
        .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { _ in model.onPillDrag(true) }
            .onEnded { _ in model.onPillDrag(false) })
    }
}

// MARK: - Fan

struct DeckFanView: View {
    @ObservedObject var model: DeckViewModel
    @State private var dragID: String?
    @State private var dragTarget = 0

    private var visibleTabs: [Note] { model.visibleTabs }
    private var hiddenCount: Int { model.hiddenCount }

    var body: some View {
        let m = model.metrics
        let font = model.deckFont
        GeometryReader { geo in
            let layout = model.layout(panelHeight: max(1, geo.size.height))
            ZStack(alignment: model.onRight ? .topTrailing : .topLeading) {
                stack(layout: layout, metrics: m, font: font)
                    .padding(.vertical, model.barStyle == .bezelDock ? 10 * CGFloat(model.scale) : 0)
                    .padding(model.onRight ? .leading : .trailing, model.barStyle == .bezelDock ? 6 * CGFloat(model.scale) : 0)
                    .background(alignment: model.onRight ? .trailing : .leading) {
                        if model.barStyle == .bezelDock {
                            EdgeBezelDockShape(onRight: model.onRight, earRadius: 10, cornerRadius: 13)
                                .fill(Color(red: 0.05, green: 0.05, blue: 0.06).opacity(0.96))
                                .overlay(
                                    EdgeBezelDockShape(onRight: model.onRight, earRadius: 10, cornerRadius: 13)
                                        .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
                                )
                                .shadow(color: .black.opacity(0.32), radius: 8, x: model.onRight ? -2 : 2, y: 2)
                                .opacity(model.revealed ? 1 : 0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: model.revealed)
                        }
                    }
                    .overlay(alignment: model.onRight ? .trailing : .leading) {
                        if model.barStyle != .bezelDock { spine(layout) }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.onRight ? .topTrailing : .topLeading)
            .padding(.top, max(0, (geo.size.height - (layout.stackHeight + (model.barStyle == .bezelDock ? 20 * CGFloat(model.scale) : 0))) / 2))
        }
    }

    private func stack(layout: DeckLayout, metrics m: DeckMetrics, font: DeckFont) -> some View {
        let total = visibleTabs.count + (hiddenCount > 0 ? 1 : 0) + model.buttons.count
        // Negative spacing makes the tabs shingle, but it would also overlap the buttons: undo it per button.
        let spacing = visibleTabs.isEmpty ? 0 : layout.spacing
        return VStack(spacing: spacing) {
            ForEach(Array(visibleTabs.enumerated()), id: \.element.id) { idx, note in
                DeckTab(note: note, isOpen: model.state.expandedID == note.id, height: layout.itemHeight, strip: layout.pitch,
                        onRight: model.onRight, metrics: m, deckFont: font, lifted: dragID == note.id, barStyle: model.barStyle,
                        action: { rect in model.onTab(note.id, rect) },
                        menu: { model.onContext($0, note.id) },
                        onDragChanged: { dy in
                            if dragID != note.id { dragID = note.id; dragTarget = idx; model.onDragging(true) }
                            let next = DeckGeometry.dragTarget(from: idx, dy: dy, pitch: layout.pitch, count: visibleTabs.count)
                            if next != dragTarget { dragTarget = next }
                        },
                        onDragEnded: { dy in
                            let to = DeckGeometry.dragTarget(from: idx, dy: dy, pitch: layout.pitch, count: visibleTabs.count)
                            dragID = nil
                            model.onDragging(false)
                            if to != idx { model.onReorder(note.id, to - idx) }
                        })
                    .offset(y: dragID == nil ? 0 : DeckGeometry.dragShift(
                        index: idx, from: visibleTabs.firstIndex { $0.id == dragID } ?? idx, to: dragTarget, pitch: layout.pitch))
                    .animation(dragID == note.id ? nil : .spring(response: 0.26, dampingFraction: 0.86), value: dragTarget)
                    .zIndex(dragID == note.id ? 900 : 0)
                    .staged(index: idx, total: total, revealed: model.revealed, onRight: model.onRight, travel: m.tabWidth + 24)
            }
            if hiddenCount > 0 {
                DeckMoreTab(count: hiddenCount, height: m.moreTabHeight, width: m.tabWidth, onRight: model.onRight) { model.showAll = true }
                    .padding(.top, m.tabGap - spacing)
                    .staged(index: visibleTabs.count, total: total, revealed: model.revealed, onRight: model.onRight, travel: m.tabWidth + 24)
            }
            ForEach(Array(model.buttons.enumerated()), id: \.element) { i, button in
                let isCard = button.isRichCard
                DeckRoundButton(button: button, style: model.tileStyle, iconSet: model.iconSet, barStyle: model.barStyle, peak: model.magnifyPeak,
                                size: m.buttonSize, onRight: model.onRight, showRunningDots: model.showRunningDots,
                                pointerY: model.magnify ? model.pointerY : nil) { rect in model.onButton(button, rect) }
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: ButtonFramesKey.self, value: [i: proxy.frame(in: .global)])
                    })
                    .padding(.top, (i == 0 && visibleTabs.isEmpty && hiddenCount == 0 ? 0 : (isCard ? 4 : m.buttonGap) - spacing))
                    .padding(model.onRight ? .trailing : .leading, isCard ? 0 : (m.tabWidth - m.buttonSize) / 2)
                    .staged(index: visibleTabs.count + (hiddenCount > 0 ? 1 : 0) + i, total: total, revealed: model.revealed,
                            onRight: model.onRight, travel: m.tabWidth + 24)
            }
        }
        .frame(width: model.buttons.contains { $0.isRichCard } ? max(52, m.tabWidth * 1.75) : m.tabWidth)
        .animation(.easeInOut(duration: 0.18), value: visibleTabs.map(\.id))
        .onPreferenceChange(TabFramesKey.self) { frames in
            if model.tabFrames != frames { model.tabFrames = frames }
        }
        .onPreferenceChange(ButtonFramesKey.self) { frames in
            if model.buttonFrames != frames { model.buttonFrames = frames }
        }
    }

    private func spine(_ layout: DeckLayout) -> some View {
        EdgeLine()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            .foregroundColor(Color.white.opacity(0.35))
            .frame(width: 1, height: layout.stackHeight + 26)
            .padding(model.onRight ? .trailing : .leading, 3)
            .allowsHitTesting(false)
    }
}

// MARK: - Tabs

/// A paper tab: its title turned on its side, leaning 3°, drawn past the screen edge so the lean opens no wedge.
struct DeckTab: View {
    let note: Note
    let isOpen: Bool
    let height: CGFloat
    /// The part of this tab the next one does not cover.
    let strip: CGFloat
    let onRight: Bool
    let metrics: DeckMetrics
    let deckFont: DeckFont
    var lifted = false
    var barStyle: EdgeBarStyle = .paper
    let action: (CGRect) -> Void
    var menu: (DeckContextAction) -> Void = { _ in }
    var onDragChanged: (CGFloat) -> Void = { _ in }
    var onDragEnded: (CGFloat) -> Void = { _ in }

    @State private var hovering = false
    @State private var dragging = false
    /// Local so only this tab redraws while it follows the pointer (not animated: a spring reads as lag).
    @State private var dy: CGFloat = 0

    var body: some View {
        let palette = NotePalette.entry(at: note.color)
        ZStack(alignment: .top) {
            if barStyle == .fluid {
                // A dark shard with the note's own colour as its edge stripe, so colour still says
                // which note this is without a paper tab in the middle of a black rail.
                ZStack(alignment: onRight ? .leading : .trailing) {
                    EdgeTabShape(onRight: onRight)
                        .fill(Color(red: 0.07, green: 0.07, blue: 0.08).opacity(isOpen || hovering ? 0.98 : 0.9))
                    Rectangle().fill(palette.dashColor).frame(width: 2.5).padding(.vertical, 5)
                }
                .shadow(color: .black.opacity(lifted ? 0.42 : 0.28), radius: lifted ? 16 : 8, x: onRight ? -3 : 3, y: 2)
            } else if barStyle == .liquidGlass {
                EdgeGlassSurface(shape: EdgeTabShape(onRight: onRight), tint: palette.paperColor)
                    .opacity(isOpen || hovering || lifted ? 1 : 0.92)
            } else {
                EdgeTabShape(onRight: onRight)
                    .fill(palette.paperColor)
                    .shadow(color: .black.opacity(lifted ? 0.42 : (isOpen || hovering ? 0.32 : 0.22)),
                            radius: lifted ? 16 : (isOpen || hovering ? 9 : 6), x: onRight ? -3 : 3, y: lifted ? 6 : 2)
            }
            VerticalTabLabel(title: note.displayTitle, strip: strip, onRight: onRight,
                             ink: barStyle == .fluid ? Color.white.opacity(0.9) : palette.inkColor,
                             metrics: metrics, deckFont: deckFont)
                .offset(x: onRight ? -metrics.bleed / 2 : metrics.bleed / 2)
        }
        .frame(width: metrics.tabWidth + metrics.bleed, height: height, alignment: .top)
        .rotationEffect(.degrees(DeckGeometry.lean(onRight: onRight)), anchor: onRight ? .trailing : .leading)
        .offset(x: onRight ? metrics.bleed : -metrics.bleed)
        .frame(width: metrics.tabWidth)
        .contentShape(Rectangle())
        .overlay(alignment: onRight ? .topTrailing : .topLeading) {
            if note.pinned {
                Circle().fill(palette.dashColor).frame(width: 5, height: 5)
                    .padding(.top, 7).padding(onRight ? .trailing : .leading, 9)
            }
        }
        .overlay(
            GeometryReader { proxy in
                Color.clear.contentShape(Rectangle()).gesture(press(frame: proxy.frame(in: .global)))
            }
        )
        .background(GeometryReader { proxy in
            Color.clear.preference(key: TabFramesKey.self, value: [note.id: proxy.frame(in: .global)])
        })
        .scaleEffect(lifted ? 1.04 : 1, anchor: onRight ? .trailing : .leading)
        .offset(y: dy)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isOpen)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: note.displayTitle))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { action(.zero) }
        .contextMenu { contextMenuItems }
    }

    /// One gesture, not a tap competing with a long-press: a press that never travels is a tap; anything past the
    /// slop is a reorder drag (and can no longer fire the tap). Global space so the tab's own offset can't feed back.
    private func press(frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { v in
                if !dragging, abs(v.translation.height) > DeckGeometry.dragSlop { dragging = true }
                guard dragging else { return }
                dy = v.translation.height
                onDragChanged(dy)
            }
            .onEnded { v in
                if dragging {
                    onDragEnded(v.translation.height)
                } else if abs(v.translation.height) <= DeckGeometry.dragSlop {
                    action(frame)
                }
                dragging = false
                dy = 0
            }
    }

    @ViewBuilder private var contextMenuItems: some View {
        Button { menu(.togglePin) } label: { note.pinned ? Text("Unpin") : Text("Pin") }
        Menu {
            ForEach(0..<NotePalette.all.count, id: \.self) { i in
                Button { menu(.color(i)) } label: { Self.colorName(i) }
            }
        } label: { Text("Color") }
        Button { menu(.archive) } label: { Text("Archive") }
        Divider()
        Button { menu(.delete) } label: { Text("Delete") }
    }

    static func colorName(_ index: Int) -> Text {
        switch NotePalette.entry(at: index).name {
        case "Lemon": return Text("Lemon")
        case "Peach": return Text("Peach")
        case "Rose": return Text("Rose")
        case "Lilac": return Text("Lilac")
        case "Sky": return Text("Sky")
        case "Mint": return Text("Mint")
        case "Sand": return Text("Sand")
        default: return Text("Slate")
        }
    }
}

struct DeckMoreTab: View {
    let count: Int
    let height: CGFloat
    let width: CGFloat
    let onRight: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                EdgeTabShape(onRight: onRight, radius: 9)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.18), radius: 5, x: onRight ? -2 : 2, y: 1)
                Text(verbatim: "+\(count)").font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(DeckPressStyle())
    }
}

// MARK: - Round buttons (glass or coloured)

struct DeckRoundButton: View {
    let button: DeckButton
    let style: EdgeTileStyle
    var iconSet: EdgeIconSet = .classic
    var barStyle: EdgeBarStyle = .paper
    var peak: CGFloat = DeckMagnification.maxScale
    let size: CGFloat
    var onRight = true
    var showRunningDots = true
    /// Pointer y in panel space (nil = no magnification).
    var pointerY: CGFloat?
    let action: (CGRect) -> Void

    @State private var hovering = false

    var body: some View {
        GeometryReader { proxy in
            Button {
                action(proxy.frame(in: .global))
            } label: {
                buttonContent
                    .scaleEffect(magnification(proxy.frame(in: .global).midY), anchor: onRight ? .trailing : .leading)
                    .animation(.easeOut(duration: 0.1), value: pointerY)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
        }
        .frame(width: button.isRichCard ? max(52, size * 1.85) : size,
               height: button.isRichCard ? button.cardHeight(unit: size) : size)
        .accessibilityLabel(button.labelText)
    }

    @ViewBuilder
    private var buttonContent: some View {
        if button.isRichCard {
            DeckRichCardView(button: button, width: max(52, size * 1.85), onRight: onRight, barStyle: barStyle)
                .scaleEffect(hovering ? 1.03 : 1)
        } else if case let .app(app) = button {
            Image(nsImage: AppIconResolver.icon(for: app.bundleID))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.9, height: size * 0.9)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                .frame(width: size, height: size)
                .overlay(alignment: onRight ? .trailing : .leading) {
                    if showRunningDots && app.isRunning {
                        let dot = max(4, size * 0.15)
                        Circle()
                            .fill(Color.green)
                            .frame(width: dot, height: dot)
                            .offset(x: onRight ? 2 : -2)
                    }
                }
                .scaleEffect(hovering ? 1.08 : 1)
                .contentShape(Rectangle())
        } else {
            Image(systemName: button.symbol)
                .font(.system(size: size * 0.43, weight: .semibold))
                .foregroundColor(barStyle == .fluid || barStyle == .bezelDock ? .white
                                 : (barStyle == .liquidGlass ? Color.primary.opacity(0.85)
                                    : (iconSet != .classic || style == .coloured ? .white : Color.primary.opacity(0.78))))
                .shadow(color: .black.opacity(iconSet == .realistic ? 0.35 : 0), radius: 1, y: 1)
                .frame(width: size, height: size)
                .background(background)
                .scaleEffect(hovering ? 1.08 : 1)
                .contentShape(Circle())
        }
    }

    private func magnification(_ centerY: CGFloat) -> CGFloat {
        guard let pointerY else { return 1 }
        return DeckMagnification.scale(distance: pointerY - centerY, maxScale: peak)
    }

    @ViewBuilder private var background: some View {
        let accent = NotePalette.entry(at: button.accent).dashColor
        if barStyle == .bezelDock {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.18 : 0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                )
        } else if barStyle == .fluid {
            // A bead on the rail: the ring is the button, the interior stays the bar's own body.
            Circle().strokeBorder(
                LinearGradient(colors: [accent.opacity(0.85), Color.white.opacity(0.18)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1.5
            )
            .background(Circle().fill(Color.white.opacity(hovering ? 0.10 : 0.04)))
        } else if barStyle == .liquidGlass {
            EdgeGlassSurface(shape: Circle(), tint: accent)
        } else {
            paperBackground(accent)
        }
    }

    @ViewBuilder private func paperBackground(_ accent: Color) -> some View {
        switch iconSet {
        case .modern:
            // Flat squircle tile with a soft two-stop gradient of the button's accent.
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(LinearGradient(colors: [accent.opacity(0.95), accent.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                .shadow(color: accent.opacity(0.35), radius: 4, y: 2)
        case .realistic:
            // Raised glass bead: body gradient, bright top gloss, inner rim, contact shadow.
            ZStack {
                Circle().fill(RadialGradient(colors: [accent.opacity(0.95), accent.opacity(0.55)], center: .topLeading,
                                             startRadius: 1, endRadius: size))
                Circle().fill(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0)], startPoint: .top, endPoint: .center))
                    .padding(size * 0.06).mask(Circle().padding(size * 0.02))
                Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.6), .black.opacity(0.25)], startPoint: .top, endPoint: .bottom),
                                      lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
        case .classic:
            classicBackground
        }
    }

    @ViewBuilder private var classicBackground: some View {
        switch style {
        case .glass:
            Circle().fill(.regularMaterial).shadow(color: .black.opacity(0.22), radius: 5, y: 1)
        case .coloured:
            Circle().fill(NotePalette.entry(at: button.accent).dashColor).shadow(color: .black.opacity(0.28), radius: 5, y: 1)
        }
    }

    private var label: Text { button.labelText }
}

// MARK: - Staging (the 42 ms shingle)

private struct DeckStaged: ViewModifier {
    let index: Int
    let total: Int
    let revealed: Bool
    let onRight: Bool
    let travel: CGFloat

    func body(content: Content) -> some View {
        let delay = revealed ? Double(index) * 0.042 : Double(max(0, total - 1 - index)) * 0.030
        content
            .offset(x: revealed ? 0 : (onRight ? travel : -travel))
            .opacity(revealed ? 1 : 0)
            .animation(.spring(response: 0.34, dampingFraction: 0.84).delay(delay), value: revealed)
    }
}

extension View {
    fileprivate func staged(index: Int, total: Int, revealed: Bool, onRight: Bool, travel: CGFloat) -> some View {
        modifier(DeckStaged(index: index, total: total, revealed: revealed, onRight: onRight, travel: travel))
    }
}

extension DeckButton {
    /// The button's name (hover bubble, tooltip, VoiceOver).
    var labelText: Text {
        switch self {
        case let .app(item): return Text(verbatim: item.name)
        case .focus: return Text("Focus")
        case .clock: return Text("Clock")
        case .batteryWifi: return Text("Battery & Wi-Fi")
        case .habits: return Text("Habits")
        case .hydration: return Text("Hydration")
        case .food: return Text("Nutrition")
        case .notesPreview: return Text("Notes")
        case .bluetoothWifi: return Text(verbatim: "Bluetooth & Wi-Fi")
        case .remindersAndTasks: return Text(verbatim: "Reminders & Tasks")
        case .systemAndBattery: return Text(verbatim: "System & Battery")
        case .timeAndAlarms: return Text(verbatim: "Time & Alarms")
        case .captureAndScreenshot: return Text(verbatim: "Capture & Screenshot")
        case .newNote: return Text("New Note")
        case .settings: return Text("KatiKati Settings")
        case .status(.wifi): return Text(verbatim: "Wi-Fi")
        case .status(.battery): return Text("Battery")
        case .status(.volume): return Text("Volume")
        case .widget(.weather): return Text("Weather")
        case .widget(.nowPlaying): return Text("Now Playing")
        case .widget(.bluetooth): return Text("Bluetooth")
        case .widget(.systemMonitor): return Text("System")
        case .productivity(.reminders): return Text("Reminders")
        case .productivity(.alarms): return Text("Alarms")
        case .productivity(.time): return Text("Time")
        case .productivity(.tasks): return Text("Tasks")
        case .productivity(.clipboard): return Text("Clipboard")
        case .productivity(.capture): return Text("Capture")
        case .productivity(.screenshot): return Text("Copy Screenshot")
        case .productivity(.windows): return Text("Windows")
        case .productivity(.screenTime): return Text("Screen Time")
        }
    }
}

/// 13b: the small name bubble shown beside the button under the pointer (hosted in the bar's flyout panel).
struct DeckLabelBubble: View {
    let button: DeckButton

    var body: some View {
        button.labelText
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .fixedSize()
    }
}

struct ButtonFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
