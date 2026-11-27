import AppKit
import SwiftUI

struct SideDeckAIMissionControlView: View {
    @ObservedObject private var usage = AgentUsageService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(.cyan)
                Text("AI Mission Control").font(.system(size: 16, weight: .semibold))
                Spacer()
                Circle()
                    .fill(usage.snapshot.activeTurn?.isActive == true ? .green : .secondary.opacity(0.35))
                    .frame(width: 8, height: 8)
            }
            Text(usage.snapshot.activeTurn?.model ?? usage.snapshot.lastMeasuredModel ?? "No AI activity today")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            NotchAIPageView()
                .frame(minHeight: 190, maxHeight: 230)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(12)
    }
}

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
    @Published var showArchived = false
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

    @Published var keyboardSelectionIndex: Int? = nil
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

    var filteredTabs: [Note] { tabs.filter { showArchived || !$0.archived } }
    var visibleTabs: [Note] {
        let filtered = filteredTabs
        return showAll ? filtered : Array(filtered.prefix(DeckGeometry.fanLimit))
    }
    var hiddenCount: Int { showAll ? 0 : max(0, filteredTabs.count - DeckGeometry.fanLimit) }

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
        let raw = max(1, filteredTabs.count + buttons.count)
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
    @AppStorage("com.katikati.theme.followDockTheme") private var followDockTheme = true
    @AppStorage("com.katikati.theme.material") private var dockThemeToken = DockThemeStyle.auto.token
    @Environment(\.colorScheme) private var colorScheme

    private var activeThemeStyle: DockThemeStyle {
        followDockTheme ? (DockThemeStyle(token: dockThemeToken) ?? .auto) : .auto
    }

    var body: some View {
        let tokens = DockThemeTokens.resolved(for: colorScheme, style: activeThemeStyle)
        ZStack {
            if model.showsFan { DeckFanView(model: model) } else { DeckPillView(model: model) }
        }
        .overlay {
            if followDockTheme, activeThemeStyle.tintsPlate, model.showsFan {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(tokens.styleTokens.rim.color.opacity(0.35), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
        }
        .environment(\.dockThemeStyle, activeThemeStyle)
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
    case counter
    case stickyNote
    case analogClock
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
        case .counter: return "plusminus.circle.fill"
        case .stickyNote: return "note.text"
        case .analogClock: return "clock"
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

    var edgeItem: EdgeItem? {
        switch self {
        case .app: return .apps
        case .focus: return .focus
        case .clock: return .clock
        case .batteryWifi: return .batteryWifi
        case .habits: return .habits
        case .hydration: return .hydration
        case .food: return .food
        case .notesPreview: return .notesPreview
        case .counter: return .counter
        case .stickyNote: return .stickyNote
        case .analogClock: return .analogClock
        case .newNote: return .newNote
        case .settings: return .settings
        case .bluetoothWifi, .widget(.bluetooth): return .bluetooth
        case .systemAndBattery, .widget(.systemMonitor): return .systemMonitor
        case .remindersAndTasks: return .reminders
        case .timeAndAlarms: return .time
        case .captureAndScreenshot: return .capture
        case .status: return .status
        case let .widget(tile):
            switch tile {
            case .weather: return .weather
            case .nowPlaying: return .nowPlaying
            case .bluetooth: return .bluetooth
            case .systemMonitor: return .systemMonitor
            }
        case let .productivity(item):
            switch item {
            case .reminders: return .reminders
            case .alarms: return .alarms
            case .time: return .time
            case .tasks: return .tasks
            case .clipboard: return .clipboard
            case .capture: return .capture
            case .screenshot: return .screenshot
            case .windows: return .windows
            case .screenTime: return .screenTime
            }
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
        case .counter: return 2
        case .stickyNote: return 0
        case .analogClock: return 5
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
        Group {
            if dashes.isEmpty && model.barStyle == .bezelDock {
                EdgeRevealLipView(side: model.onRight ? .right : .left, isHovered: false)
            } else {
                VStack(spacing: m.dashGap) {
                    ForEach(Array((dashes.isEmpty ? [Color.secondary.opacity(0.4)] : dashes).enumerated()), id: \.offset) { _, c in
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(c).frame(width: m.dashWidth, height: m.dashHeight)
                    }
                }
                .padding(.vertical, m.pillPad)
                .frame(width: m.pillWidth)
                .background(pillBackground)
            }
        }
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

private struct LocalButtonMidYsKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

struct DeckFanView: View {
    @ObservedObject var model: DeckViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragID: String?
    @State private var dragTarget = 0
    @State private var hoveredIndex: Int?
    @State private var localButtonMidYs: [Int: CGFloat] = [:]

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
            .overlay(alignment: model.onRight ? .topTrailing : .topLeading) {
                Button {
                    model.showArchived.toggle()
                    model.showAll = false
                } label: {
                    Image(systemName: model.showArchived ? "archivebox.fill" : "archivebox")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(5)
                        .background(.black.opacity(0.25), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.8))
                .help(Text("Archive"))
                .padding(model.onRight ? .trailing : .leading, 4)
            }
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
                let hoveredKey = hoveredIndex.map(String.init)
                let row = DeckRoundButton(
                    button: button,
                    style: model.tileStyle,
                    iconSet: model.iconSet,
                    barStyle: model.barStyle,
                    peak: model.magnifyPeak,
                    size: m.buttonSize,
                    onRight: model.onRight,
                    showRunningDots: model.showRunningDots,
                    pointerY: model.magnify ? model.pointerY : nil
                ) { rect in model.onButton(button, rect) }
                    .background(GeometryReader { proxy in
                        Color.clear
                            .preference(key: ButtonFramesKey.self, value: [i: proxy.frame(in: .global)])
                            .preference(key: LocalButtonMidYsKey.self, value: [i: proxy.frame(in: .named("edgeButtonStack")).midY])
                    })
                    .scaleEffect(EdgeSpotlightPolicy.scale(hoveredID: hoveredKey, itemID: String(i), reduceMotion: reduceMotion))
                    .opacity(EdgeSpotlightPolicy.opacity(hoveredID: hoveredKey, itemID: String(i)))
                    .onHover { isOver in
                        hoveredIndex = isOver ? i : (hoveredIndex == i ? nil : hoveredIndex)
                    }
                    .padding(.top, (i == 0 && visibleTabs.isEmpty && hiddenCount == 0 ? 0 : (isCard ? 4 : m.buttonGap) - spacing))
                    .padding(model.onRight ? .trailing : .leading, isCard ? 0 : (m.tabWidth - m.buttonSize) / 2)
                    .staged(index: visibleTabs.count + (hiddenCount > 0 ? 1 : 0) + i, total: total, revealed: model.revealed,
                            onRight: model.onRight, travel: m.tabWidth + 24)

                if button == .settings {
                    row.dropDestination(for: String.self) { items, _ in
                        handleRemoveDrop(items: items)
                    }
                } else if let raw = button.edgeItem?.rawValue {
                    row.draggable(raw)
                } else {
                    row
                }
            }
        }
        .coordinateSpace(name: "edgeButtonStack")
        .frame(width: model.buttons.contains { $0.isRichCard } ? max(52, m.tabWidth * 1.75) : m.tabWidth)
        .animation(.easeInOut(duration: 0.18), value: visibleTabs.map(\.id))
        .onPreferenceChange(TabFramesKey.self) { frames in
            if model.tabFrames != frames { model.tabFrames = frames }
        }
        .onPreferenceChange(ButtonFramesKey.self) { frames in
            if model.buttonFrames != frames { model.buttonFrames = frames }
        }
        .onPreferenceChange(LocalButtonMidYsKey.self) { mids in
            if localButtonMidYs != mids { localButtonMidYs = mids }
        }
        .dropDestination(for: String.self) { items, location in
            handleReorderDrop(items: items, pointerY: location.y)
        }
    }

    private func handleReorderDrop(items: [String], pointerY: CGFloat) -> Bool {
        guard let raw = items.first, let dropped = EdgeItem(rawValue: raw) else { return false }
        let orderedMids = localButtonMidYs.sorted { $0.key < $1.key }.map(\.value)
        let insertAt = EdgeInsertIndex.index(forY: pointerY, itemMidYs: orderedMids)
        let currentItems = model.buttons.compactMap(\.edgeItem)
        let nextOrder = EdgeCustomOrder.inserting(dropped, at: insertAt, in: currentItems)
        UserDefaults.standard.set(EdgeCustomOrder.encode(nextOrder.map(\.rawValue)), forKey: EdgeCustomOrder.defaultsKey)
        NotificationCenter.default.post(name: Notification.Name("com.katikati.edge.orderDidChange"), object: nil)
        return true
    }

    private func handleRemoveDrop(items: [String]) -> Bool {
        guard let raw = items.first, let dropped = EdgeItem(rawValue: raw), dropped != .settings else { return false }
        let currentItems = model.buttons.compactMap(\.edgeItem)
        let nextOrder = EdgeCustomOrder.removing(dropped, from: currentItems)
        UserDefaults.standard.set(EdgeCustomOrder.encode(nextOrder.map(\.rawValue)), forKey: EdgeCustomOrder.defaultsKey)
        NotificationCenter.default.post(name: Notification.Name("com.katikati.edge.orderDidChange"), object: nil)
        return true
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
        .nativeContextMenu { buildContextMenu() }
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

    /// The note tab's right-click, wearing the same header as every other surface: the note's name,
    /// its pin state, and the three actions a glance at the rail actually offers.
    private func buildContextMenu() -> NSMenu {
        let nsMenu = NSMenu()
        nsMenu.addItem(DockMenuChrome.header(
            icon: nil,
            symbol: "note.text",
            title: note.displayTitle,
            status: note.pinned ? String(localized: "Pin") : nil,
            tiles: [
                .init(symbol: note.pinned ? "pin.slash" : "pin",
                      caption: note.pinned ? String(localized: "Unpin") : String(localized: "Pin")) {
                    menu(.togglePin)
                },
                .init(symbol: "tray.and.arrow.down", caption: String(localized: "Archive")) {
                    menu(.archive)
                },
                .init(symbol: "trash", caption: String(localized: "Delete")) {
                    menu(.delete)
                },
            ],
            menu: nsMenu
        ))
        nsMenu.addItem(.separator())
        let pinRow = MenuChrome.action(note.pinned ? String(localized: "Unpin") : String(localized: "Pin"),
                                       symbol: note.pinned ? "pin.slash" : "pin", in: nsMenu) {
            menu(.togglePin)
        }
        pinRow.state = note.pinned ? .on : .off
        MenuChrome.submenu(String(localized: "Color"), symbol: "paintpalette", in: nsMenu) { sub in
            for index in 0..<NotePalette.all.count {
                let item = ClosureMenuItem(Self.colorTitle(index)) { menu(.color(index)) }
                item.state = index == note.color ? .on : .off
                sub.addItem(item)
            }
        }
        MenuChrome.action(String(localized: "Archive"), symbol: "tray.and.arrow.down", in: nsMenu) {
            menu(.archive)
        }
        nsMenu.addItem(.separator())
        MenuChrome.action(String(localized: "Delete"), symbol: "trash", in: nsMenu) { menu(.delete) }
        return nsMenu
    }

    static func colorTitle(_ index: Int) -> String {
        NotePalette.entry(at: index).name
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
        case .counter: return Text("Counter")
        case .stickyNote: return Text("Sticky Note")
        case .analogClock: return Text("Analog Clock")
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

// MARK: - Side Deck notification inbox (SD-2)

/// The notification inbox, moved out of the notch and into the Left Edge Bar's Side Deck. The bell tab
/// draws the persistent history Notification Center has shown (`NotificationMirrorService`) as a vertical
/// list you can filter, open, mark read and dismiss. The notch keeps only transient event pills and never
/// draws an inbox inside itself again.
/// OW-3: the persistent scratch note. Typing goes through `ScratchpadStore`, which debounces the atomic file
/// write; the badge is the pure count, and Copy All / Clear are the whole feature.
struct ScratchpadPane: View {
    @ObservedObject private var store = ScratchpadStore.shared
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(verbatim: "\(store.document.wordCount)w · \(store.document.characterCount)c")
                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(store.copyAll(), forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Group {
                        if copied {
                            Text("Copied")
                        } else {
                            Text("Copy All")
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .disabled(store.document.isEmpty)
                Button {
                    store.clear()
                } label: {
                    Text("Clear").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .disabled(store.document.isEmpty)
            }
            TextEditor(text: Binding(get: { store.document.text }, set: { store.update($0) }))
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
        }
        .padding(12)
    }
}

/// SD-3a: the one card surface every SideDeck page draws — 18 pt continuous radius on the deck's own glass
/// (`EdgeGlassSurface`: system glass on macOS 26, frosted below it, solid under Reduce Transparency, hairline
/// rim and one soft shadow). The notch's `.notchCard()` is deliberately not reused: its 0.10 white reads as the
/// notch's palette and leaves deck text sitting on a surface that belongs to another panel.
struct SideDeckCardSurface: ViewModifier {
    var radius: CGFloat = 18

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content.background(EdgeGlassSurface(shape: shape))
    }
}

extension View {
    func sideDeckCard(radius: CGFloat = 18) -> some View { modifier(SideDeckCardSurface(radius: radius)) }
}

struct SideDeckStorageView: View {
    @ObservedObject private var scanner = StorageScanService.shared
    @ObservedObject private var cleaner = CleanerService.shared
    /// SD-3b: the notch Storage page's "Scan App Leftovers" result, kept alive here now that the page is gone.
    @State private var leftoverCandidates: [CleanupCandidate] = []
    /// SD-3d: the developer-cache catalogue as measured on this machine, cheapest-to-reclaim totals included.
    @State private var devCaches: [DevCacheReading] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                capacity
                categoryBreakdown
                devCacheSection
                HStack(alignment: .top, spacing: 8) {
                    itemColumn(title: "Large Files", items: scanner.files)
                    itemColumn(title: String(localized: "Developer & Cache"), items: scanner.dev)
                }
                actions
            }
            .padding(12)
        }
        .onAppear {
            scanner.scan()
            measureDevCaches()
        }
        .onDisappear { scanner.cancel() }
    }

    private var capacity: some View {
        let disk = SystemMonitorSampler.disk()
        let used = Double(disk.total > disk.free ? disk.total - disk.free : 0)
        let fraction = disk.total == 0 ? 0 : used / Double(disk.total)
        let reclaimable = DevCacheCatalog.reclaimableBytes(devCaches)
        let reclaimableFraction = disk.total == 0 ? 0
            : min(fraction, Double(reclaimable) / Double(disk.total))
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Storage").font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                Text(verbatim: "\(SystemMonitorFormat.bytes(Double(disk.total - disk.free))) used")
                    .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule().fill(Color.accentColor)
                        .frame(width: max(4, geo.size.width * fraction))
                    // SD-3d: the slice of that bar this card can reclaim in one click, so the gauge answers
                    // "how much can I get back" and not just "how full am I".
                    if reclaimableFraction > 0 {
                        Capsule().fill(Color.orange)
                            .frame(width: max(2, geo.size.width * reclaimableFraction))
                    }
                }
            }
            .frame(height: 8)
            HStack(spacing: 4) {
                Image(systemName: "hammer").font(.system(size: 8)).foregroundStyle(.orange)
                Text(verbatim: ByteCountFormatter.string(fromByteCount: reclaimable, countStyle: .file))
                    .font(.system(size: 9)).foregroundStyle(.secondary).monospacedDigit()
                Text("Developer").font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    /// SD-3d: the ClearDisk-style catalogue. Each row is one known cache root with what it weighs and how
    /// risky it is to reclaim; the levels are the already-localized Low / Medium / High, and only Low and
    /// Medium are swept by the one-click reclaim, so an archive or a container image always needs its own
    /// confirmation.
    private var devCacheSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("Developer").font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 4)
                if !devCaches.isEmpty {
                    Button("Move to Trash") { reclaimDevCaches() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 9))
                }
            }
            if devCaches.isEmpty {
                Text("Nothing Large Found").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            ForEach(DevCacheCatalog.ordered(devCaches)) { reading in
                HStack(spacing: 5) {
                    Image(systemName: reading.target.symbol)
                        .font(.system(size: 9)).foregroundStyle(.secondary).frame(width: 12)
                    Text(verbatim: reading.target.title).lineLimit(1)
                    Text(verbatim: reading.target.risk.localizedTitle)
                        .font(.system(size: 8, weight: .semibold))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(riskTint(reading.target.risk).opacity(0.18)))
                        .foregroundStyle(riskTint(reading.target.risk))
                    Spacer(minLength: 4)
                    Text(verbatim: ByteCountFormatter.string(fromByteCount: reading.bytes, countStyle: .file))
                        .foregroundStyle(.secondary).monospacedDigit()
                }
                .font(.system(size: 9))
                .help(Text(verbatim: reading.paths.joined(separator: "\n")))
                .contextMenu {
                    Button(String(localized: "Reveal")) {
                        NSWorkspace.shared.activateFileViewerSelecting(reading.paths.map { URL(fileURLWithPath: $0) })
                    }
                    Button(String(localized: "Move to Trash"), role: .destructive) {
                        let homeRoot = [URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)]
                        for path in reading.paths {
                            let url = URL(fileURLWithPath: path)
                            guard AppRemovalPlanner.isWithinAllowedBoundary(url, allowedRoots: homeRoot) else { continue }
                            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
                        }
                        measureDevCaches()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    private func riskTint(_ risk: DevCacheTarget.Risk) -> Color {
        switch risk {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }

    /// Measured on appear and after a reclaim — never on a timer, so a closed deck costs nothing.
    private func measureDevCaches() {
        let home = NSHomeDirectory()
        Task.detached(priority: .utility) {
            let readings = DevCacheCatalog.snapshot(
                home: home,
                isDirectory: { path in
                    var isDirectory: ObjCBool = false
                    return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                        && isDirectory.boolValue
                },
                size: { StorageScanService.size(of: $0) },
                children: { path in
                    ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [])
                        .filter { !$0.hasPrefix(".") }
                        .map { path + "/" + $0 }
                }
            )
            await MainActor.run {
                devCaches = readings
                // The page that measured is the only writer; the dashboard reads this instead of scanning.
                DevCacheSnapshotStore.save(readings)
            }
        }
    }

    private func reclaimDevCaches() {
        let sweep = DevCacheCatalog.ordered(devCaches).filter { $0.target.risk.isReclaimableInOneClick }
        guard !sweep.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Move to Trash?")
        alert.informativeText = String(format: String(localized: "%d items, %@."), sweep.reduce(0) { $0 + $1.paths.count },
                                       ByteCountFormatter.string(fromByteCount: DevCacheCatalog.reclaimableBytes(devCaches),
                                                                 countStyle: .file))
        alert.addButton(withTitle: String(localized: "Move to Trash"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let homeRoot = [URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)]
        for path in sweep.flatMap(\.paths) {
            let url = URL(fileURLWithPath: path)
            guard AppRemovalPlanner.isWithinAllowedBoundary(url, allowedRoots: homeRoot) else { continue }
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        measureDevCaches()
    }

    private var categoryBreakdown: some View {
        HStack(spacing: 8) {
            category("Apps", "shippingbox", scanner.dev.reduce(0) { $0 + $1.bytes } / 4)
            category("Developer", "hammer", scanner.dev.reduce(0) { $0 + $1.bytes })
            category("Downloads", "arrow.down.circle", scanner.files.reduce(0) { $0 + $1.bytes })
            category("Large Files", "doc", scanner.files.reduce(0) { $0 + $1.bytes })
        }
    }

    private func category(_ title: String, _ symbol: String, _ bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(.secondary)
            Text(title).font(.system(size: 9, weight: .semibold)).lineLimit(1)
            Text(verbatim: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                .font(.system(size: 9)).foregroundStyle(.secondary).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    private func itemColumn(title: String, items: [StorageItem]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11, weight: .semibold))
            // The notch page's two empty states, carried over so a finished scan that found nothing says so
            // instead of leaving a blank column. Both strings were already catalogued.
            if items.isEmpty {
                if scanner.state == .scanning {
                    Text("Scanning…").font(.system(size: 9)).foregroundStyle(.secondary)
                } else {
                    Text("Nothing Large Found").font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            ForEach(items.prefix(5)) { item in
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
                } label: {
                    HStack {
                        Text(verbatim: item.name).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(verbatim: ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(.system(size: 9))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .contextMenu { rowMenu(for: item) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// SD-3b: the row menu the notch's Storage page carried — reveal, copy the path, or move the item to the
    /// Trash (never an unlink, so every mistake is recoverable from the Trash).
    @ViewBuilder
    private func rowMenu(for item: StorageItem) -> some View {
        Button(String(localized: "Reveal")) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
        }
        Button(String(localized: "Copy Path")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.path, forType: .string)
        }
        Button(String(localized: "Move to Trash"), role: .destructive) {
            let allowed = [URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)]
            let url = URL(fileURLWithPath: item.path)
            guard AppRemovalPlanner.isWithinAllowedBoundary(url, allowedRoots: allowed) else { return }
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                let alert = NSAlert()
                alert.messageText = String(localized: "Move to Trash is unavailable on this volume.")
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: String(localized: "OK"))
                alert.runModal()
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button("Review Caches") { reviewCachesTapped() }.buttonStyle(.borderless)
            Button {
                scanLeftovers()
            } label: {
                cleaner.isScanningLeftovers ? Text("Scanning…") : Text("Scan App Leftovers")
            }
            .buttonStyle(.borderless)
            .disabled(cleaner.isScanningLeftovers)
            Spacer(minLength: 0)
            if !scanner.hasFullDiskAccess {
                Button("Allow Full Disk Access") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderless)
                .help(Text("Allow Full Disk Access for the Whole Disk"))
            }
        }
        .font(.system(size: 10, weight: .semibold))
    }

    /// SD-3b: ported from the notch Storage page, which owned the only confirmation that told the owner how
    /// many cache folders it found, how much they weigh, and what actually happened afterwards.
    private func reviewCachesTapped() {
        cleaner.scan {
            let candidates = cleaner.candidates
            guard !candidates.isEmpty else {
                let empty = NSAlert()
                empty.messageText = String(localized: "Nothing to Clean")
                empty.informativeText = String(localized: "No cache folder older than a week and larger than 50 MB was found.")
                NSApp.activate(ignoringOtherApps: true)
                empty.runModal()
                return
            }
            let total = ByteCountFormatter.string(fromByteCount: CleanupPlan.totalBytes(candidates), countStyle: .file)
            let preview = candidates.prefix(8).map { candidate in
                "• \(candidate.name) — \(ByteCountFormatter.string(fromByteCount: candidate.bytes, countStyle: .file))"
            }.joined(separator: "\n")
            let alert = NSAlert()
            alert.messageText = String(localized: "Move Caches to the Trash?")
            alert.informativeText = String(format: String(localized: "%d items, %@. They are moved to the Trash, so you can put them back; apps rebuild them as needed.\n\n%@"),
                                           candidates.count, total, preview)
            alert.alertStyle = .warning
            alert.addButton(withTitle: String(localized: "Move to Trash"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let outcome = cleaner.clean(candidates)
            let done = NSAlert()
            done.messageText = String(localized: "Caches Moved to the Trash")
            let moved = String(format: String(localized: "%d items, %@."), outcome.moved,
                               ByteCountFormatter.string(fromByteCount: outcome.bytes, countStyle: .file))
            let failed = outcome.failed > 0
                ? " " + String(format: String(localized: "%d could not be moved."), outcome.failed)
                : ""
            done.informativeText = moved + failed
            NSApp.activate(ignoringOtherApps: true)
            done.runModal()
        }
    }

    /// SD-3b: the notch page's app-leftover scan, same picker, same Trash-first confirmation.
    private func scanLeftovers() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Scan App Leftovers")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let appURL = panel.url else { return }
        cleaner.scanLeftovers(forAppAt: appURL) {
            leftoverCandidates = cleaner.leftoverCandidates
            showLeftoverReview()
        }
    }

    private func showLeftoverReview() {
        guard !leftoverCandidates.isEmpty else {
            let alert = NSAlert()
            alert.messageText = String(localized: "No Apps Found")
            alert.informativeText = String(localized: "Nothing to Clean")
            alert.addButton(withTitle: String(localized: "OK"))
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        let preview = leftoverCandidates.prefix(8).map {
            "• \($0.name) — \(ByteCountFormatter.string(fromByteCount: $0.bytes, countStyle: .file))"
        }.joined(separator: "\n")
        let alert = NSAlert()
        alert.messageText = String(localized: "Move to Trash?")
        alert.informativeText = String(format: String(localized: "Scanned %d potential leftover locations in ~/Library.\n\n%@"),
                                       leftoverCandidates.count, preview)
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Move to Trash"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let outcome = cleaner.clean(leftoverCandidates)
        let done = NSAlert()
        done.messageText = String(localized: "Move to Trash")
        done.informativeText = "\(outcome.moved) moved, \(outcome.failed) failed."
        done.addButton(withTitle: String(localized: "OK"))
        done.runModal()
    }
}

struct SideDeckWeatherView: View {
    @ObservedObject private var service = WeatherService.shared

    /// SD-2: width-matched to the panel, so the forecast never sits in a narrow column in a wide deck.
    var body: some View {
        let state = service.currentState
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: state.cityName).font(.system(size: 13, weight: .semibold))
                        Text(verbatim: state.conditionText).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(verbatim: "\(Int(state.temperatureCelsius.rounded()))°")
                        .font(.system(size: 34, weight: .light)).monospacedDigit()
                    Image(systemName: state.glyphName).font(.system(size: 22))
                }
                if let detail = state.detail {
                    hourly(detail.hourly)
                    daily(detail.daily)
                } else {
                    Text("Weather data unavailable").foregroundStyle(.secondary)
                        .font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
        }
        .onAppear { Task { await service.refresh() } }
    }

    private func hourly(_ hours: [WeatherHourPoint]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hourly").font(.system(size: 11, weight: .semibold))
            HStack(spacing: 8) {
                ForEach(Array(hours.prefix(8).enumerated()), id: \.element.id) { index, hour in
                    VStack(spacing: 4) {
                        Text(index == 0 ? "Now" : hour.hourLabel)
                        Image(systemName: WeatherResponseParsing.mapWeatherCode(code: hour.code).symbol)
                        Text(verbatim: "\(Int(hour.temperature.rounded()))°").monospacedDigit()
                    }
                    .font(.system(size: 9)).foregroundStyle(index == 0 ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func daily(_ days: [WeatherDayPoint]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Forecast").font(.system(size: 11, weight: .semibold))
            ForEach(Array(days.prefix(7))) { day in
                HStack {
                    Text(verbatim: day.id == days.first?.id ? "Today" : DailyTile.weekday(day.date))
                    Spacer(minLength: 0)
                    Text(verbatim: "\(Int(day.low.rounded()))°")
                        .foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
                    Text(verbatim: "\(Int(day.high.rounded()))°").frame(width: 38, alignment: .trailing)
                }
                .font(.system(size: 10)).monospacedDigit()
            }
        }
    }
}

struct SideDeckQuickAccessView: View {
    let onLauncher: () -> Void
    let onCommandBar: () -> Void
    var onCloseDeck: () -> Void = {}

    private enum Mode: String {
        case commandBar
        case launcher
    }

    @AppStorage("com.katikati.sideDeck.quickAccessMode") private var modeRaw: String = Mode.commandBar.rawValue

    private var mode: Mode {
        Mode(rawValue: modeRaw) ?? .commandBar
    }

    private var modeBinding: Binding<Mode> {
        Binding(get: { mode }, set: { modeRaw = $0.rawValue })
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Picker("Mode", selection: modeBinding) {
                    Text("Command Bar").tag(Mode.commandBar)
                    Text("Launcher").tag(Mode.launcher)
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                Button {
                    if mode == .commandBar { onCommandBar() } else { onLauncher() }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help(mode == .commandBar ? Text("Open Command Bar") : Text("Open Launcher"))
                .accessibilityLabel(mode == .commandBar ? Text("Open Command Bar") : Text("Open Launcher"))
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            embeddedContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { prepareCurrentMode() }
        .onChange(of: modeRaw) { _, _ in prepareCurrentMode() }
        .onDisappear { teardownAllEmbedded() }
    }

    @ViewBuilder
    private var embeddedContent: some View {
        if let app = AppDelegate.shared {
            if mode == .commandBar {
                app.commandBarPanel.makeEmbeddedView { onCloseDeck() }
            } else {
                app.launcherPanel.makeEmbeddedView { onCloseDeck() }
            }
        } else {
            fallbackButtons
        }
    }

    private var fallbackButtons: some View {
        VStack(spacing: 12) {
            Text("Quick Access").font(.system(size: 13, weight: .semibold))
            HStack(spacing: 12) {
                quickButton(title: String(localized: "Launcher"), symbol: "square.grid.2x2", action: onLauncher)
                quickButton(title: String(localized: "Command Bar"), symbol: "command", action: onCommandBar)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func prepareCurrentMode() {
        guard let app = AppDelegate.shared else { return }
        if mode == .commandBar {
            app.launcherPanel.teardownEmbedded()
            app.commandBarPanel.prepareEmbedded()
        } else {
            app.commandBarPanel.teardownEmbedded()
            app.launcherPanel.prepareEmbedded()
        }
    }

    private func teardownAllEmbedded() {
        AppDelegate.shared?.commandBarPanel.teardownEmbedded()
        AppDelegate.shared?.launcherPanel.teardownEmbedded()
    }

    private func quickButton(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 22, weight: .medium))
                Text(verbatim: title).font(.system(size: 11, weight: .semibold))
            }
            // SD-2: the Command Bar and Launcher entries fill the panel rather than sitting in two tiles.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }
}

struct SideDeckNotificationsView: View {
    @ObservedObject var controller: WindowDrawerController
    @ObservedObject private var mirror = NotificationMirrorService.shared
    @AppStorage(NotificationHistoryStore.StorageKey.quietMode) private var quietMode = false
    @State private var hoveredID: String?

    init(controller: WindowDrawerController) {
        self.controller = controller
    }

    private var entries: [NotificationHistoryEntry] { controller.visibleNotifications }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            filterStrip
            if !quietMode, let live = mirror.live { liveCard(live) }
            content
        }
        .padding(12)
        .onAppear {
            mirror.startBanners()
            mirror.loadHistory()
        }
        .onDisappear { mirror.stopBanners() }
    }

    /// All / Unread plus the two bulk actions. The pills drive the same filter the deck's search bar feeds,
    /// so typing and the pill always agree on what the list shows.
    private var filterStrip: some View {
        HStack(spacing: 6) {
            filterPill(Text("All"), isOn: !controller.notificationsUnreadOnly) {
                controller.notificationsUnreadOnly = false
            }
            filterPill(Text("Unread"), isOn: controller.notificationsUnreadOnly) {
                controller.notificationsUnreadOnly = true
            }
            Spacer(minLength: 0)
            Button { mirror.markAllRead() } label: {
                Image(systemName: "checkmark.circle").font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(mirror.historyStore.unreadCount == 0)
            .help(Text("Mark All Read"))
            Button { mirror.clearHistoryStore() } label: {
                Text("Clear").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(mirror.historyStore.entries.isEmpty)
            .help(Text("Clear Inbox"))
        }
    }

    private func filterPill(_ title: Text, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOn ? Color.white : Color.secondary)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Capsule().fill(isOn ? Color.accentColor : Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    /// The banner Notification Center is drawing right now. It carries no app name: the accessibility tree
    /// does not name the notifying app, and this view does not guess one.
    private func liveCard(_ notification: MirroredNotification) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: notification.title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
            if let detail = notification.detail {
                Text(verbatim: detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    /// One door at a time: the grant that blocks the live banners comes before the one that blocks the
    /// history, and neither is ever asked for from code.
    @ViewBuilder
    private var content: some View {
        if !entries.isEmpty {
            rows
        } else if !controller.query.isEmpty || controller.notificationsUnreadOnly {
            message(Text("No matching notifications"))
        } else if !mirror.canReadBanners {
            door(Text("Accessibility Is Off"), pane: "Privacy_Accessibility")
        } else {
            switch mirror.historyState {
            case .noAccess:
                door(Text("Full Disk Access Is Off"), pane: "Privacy_AllFiles")
            case .unsupported:
                message(Text("Notification History Unavailable"))
            case .idle, .loading, .loaded:
                message(Text("No Notifications Yet"))
            }
        }
    }

    /// SD-7: grouped by app, newest group first, each group carrying its own unread count. Selection follows
    /// the entry's id, because a grouped list no longer has one flat row number per entry.
    private var rows: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(NotificationDigest.groups(entries)) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(verbatim: NotificationDigest.label(for: group.bundleID))
                                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                .foregroundStyle(.secondary)
                            if group.unreadCount > 0 {
                                Text(verbatim: "\(group.unreadCount)")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.22)))
                            }
                            Spacer(minLength: 0)
                        }
                        ForEach(group.entries) { entry in
                            card(entry, selected: controller.selectedNotification?.id == entry.id)
                        }
                    }
                }
            }
            .padding(.bottom, 4)
        }
    }

    private func card(_ entry: NotificationHistoryEntry, selected: Bool) -> some View {
        Button { controller.openNotification(entry) } label: {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(entry.isRead ? Color.clear : Color.accentColor)
                    .frame(width: 6, height: 6)
                    .padding(.top, 6)
                Image(nsImage: NotificationAppIcon.icon(for: entry.appBundleId))
                    .resizable().frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(verbatim: NotificationAppIcon.name(for: entry.appBundleId))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(verbatim: entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.tertiary).lineLimit(1)
                    }
                    Text(verbatim: entry.title)
                        .font(.system(size: 12, weight: entry.isRead ? .regular : .semibold))
                        .lineLimit(2)
                    if let body = entry.body {
                        Text(verbatim: body).font(.system(size: 11))
                            .foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                if hoveredID == entry.id || selected {
                    Button { controller.dismissNotification(entry) } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(Text("Dismiss"))
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hoveredID = entry.id } else if hoveredID == entry.id { hoveredID = nil }
        }
        .contextMenu {
            Button { controller.dismissNotification(entry) } label: { Text("Dismiss") }
        }
    }

    private func message(_ text: Text) -> some View {
        text.font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func door(_ text: Text, pane: String) -> some View {
        VStack(spacing: 5) {
            text.font(.system(size: 12, weight: .semibold))
            Button(String(localized: "Open System Settings")) { openPrivacy(pane) }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// `AgendaPane.openPrivacy`'s route, inlined: this view is part of the deck, not the settings window.
    private func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Side Deck rail (SD-1/SD-2)

/// One button of the Left Edge Bar's Side Deck rail, with an optional count badge: unread notifications
/// under the bell, staged items under the paperclip.
struct SideDeckRailButton: View {
    let symbol: String
    let title: Text
    let selected: Bool
    var badge = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16))
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.28) : Color.clear))
                .overlay(alignment: .topTrailing) {
                    if badge > 0 { SideDeckBadgeCount(count: badge).offset(x: 4, y: -3) }
                }
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// The little count capsule the rail and the bell tab share.
struct SideDeckBadgeCount: View {
    let count: Int

    var body: some View {
        Text(verbatim: count > 99 ? "99+" : "\(count)")
            .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(Capsule().fill(Color.accentColor))
            .fixedSize()
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

// MARK: - OW-5b: the FX / Gold / Crypto ticker

/// The ticker is **off until switched on here**, and the badge always says whether the numbers on screen are
/// live, read back from disk, or unreachable — a stale price with no badge is worse than no price.
struct TickerPane: View {
    @ObservedObject private var feed = TickerFeed.shared
    @AppStorage(TickerCachePolicy.enabledKey) private var enabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Toggle(isOn: $enabled) {
                    Text("Ticker").font(.system(size: 11, weight: .semibold))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                Spacer(minLength: 0)
                badge
            }
            if enabled {
                if let snapshot = feed.snapshot, !snapshot.quotes.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(snapshot.quotes) { quote in
                            HStack(spacing: 8) {
                                Text(verbatim: quote.id)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                Spacer(minLength: 0)
                                Text(verbatim: TickerFormat.value(quote))
                                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                                if let change = TickerFormat.change(quote.changeFraction) {
                                    Text(verbatim: change)
                                        .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                                        .foregroundStyle((quote.changeFraction ?? 0) >= 0 ? Color.green : Color.red)
                                }
                            }
                        }
                    }
                    Text(verbatim: snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    Text("No prices yet")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .onAppear {
            feed.retain()
            feed.refresh()
        }
        .onDisappear { feed.release() }
        .onChange(of: enabled) { _ in feed.refresh() }
    }

    private var badge: some View {
        let label: String = {
            switch feed.freshness {
            case .live: return String(localized: "Live")
            case .cached: return String(localized: "Cached")
            case .offline: return String(localized: "Offline")
            }
        }()
        let tint: Color = {
            switch feed.freshness {
            case .live: return .green
            case .cached: return .orange
            case .offline: return .secondary
            }
        }()
        return Text(verbatim: label)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.14)))
            .accessibilityLabel(label)
    }
}
