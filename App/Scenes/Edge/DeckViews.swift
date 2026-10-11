import SwiftUI

/// Everything the deck draws is driven by this model (Phase 7A-D2); the controller owns panels, timers and
/// the state machine and just publishes into it.
@MainActor
final class DeckViewModel: ObservableObject {
    @Published var state: DeckState = .rest
    /// False → tabs are off-screen (rest / exiting); true → shingled in. Flipped two frames after the panel resizes.
    @Published var revealed = false
    @Published var showAll = false
    @Published var tabs: [Note] = []
    @Published var buttons: [DeckButton] = []
    @Published var tileStyle: EdgeTileStyle = .glass
    @Published var scale: Double = 1
    @Published var tabFont: String = ""
    @Published var onRight = true
    /// Pill / tile accent colours when there are no note tabs (left deck).
    @Published var accentDashes: [NotePaletteEntry] = []

    var onTab: (String) -> Void = { _ in }
    var onButton: (DeckButton, CGRect) -> Void = { _, _ in }

    var metrics: DeckMetrics { DeckMetrics(scale: CGFloat(scale)) }
    var deckFont: DeckFont { DeckFont(postScript: tabFont, scale: CGFloat(scale)) }
}

/// Round buttons stacked under the tabs.
enum DeckButton: Hashable {
    case newNote
    case settings
    case status(StatusKind)
    case widget(WidgetTile)

    var symbol: String {
        switch self {
        case .newNote: return "plus"
        case .settings: return "gearshape"
        case .status(.wifi): return "wifi"
        case .status(.battery): return "battery.100"
        case .status(.volume): return "speaker.wave.2.fill"
        case .widget(.weather): return "cloud.sun.fill"
        case .widget(.nowPlaying): return "music.note"
        case .widget(.bluetooth): return "wave.3.right.circle.fill"
        }
    }

    /// Palette index for the coloured style (stable per button).
    var accent: Int {
        switch self {
        case .newNote: return 0
        case .settings: return 7
        case .status(.wifi): return 4
        case .status(.battery): return 5
        case .status(.volume): return 3
        case .widget(.weather): return 1
        case .widget(.nowPlaying): return 2
        case .widget(.bluetooth): return 4
        }
    }
}

// MARK: - Pill (at rest)

struct DeckPillView: View {
    @ObservedObject var model: DeckViewModel

    private var dashes: [Color] {
        let colors = model.tabs.isEmpty
            ? model.accentDashes.map(\.dashColor)
            : model.tabs.map { NotePalette.entry(at: $0.color).dashColor }
        let m = DeckGeometry.maxDashes
        return Array(colors.prefix(m)) + (colors.count > m ? [Color.secondary.opacity(0.5)] : [])
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
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.55))
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.ultraThinMaterial))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: .black.opacity(0.22), radius: 6, x: model.onRight ? -2 : 2, y: 1)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.onRight ? .trailing : .leading)
        .padding(model.onRight ? .trailing : .leading, 1)
    }
}

// MARK: - Fan

struct DeckFanView: View {
    @ObservedObject var model: DeckViewModel

    private var visibleTabs: [Note] { model.showAll ? model.tabs : Array(model.tabs.prefix(DeckGeometry.fanLimit)) }
    private var hiddenCount: Int { model.showAll ? 0 : max(0, model.tabs.count - DeckGeometry.fanLimit) }

    var body: some View {
        let m = model.metrics
        let font = model.deckFont
        let longest = visibleTabs.map { font.measure.total(VerticalLabelLayout.runs(for: $0.displayTitle.uppercased())) }.max() ?? 0
        GeometryReader { geo in
            let layout = DeckGeometry.layout(m, panelHeight: max(1, geo.size.height), count: visibleTabs.count,
                                             hasMore: hiddenCount > 0, longestLabel: longest, buttons: model.buttons.count)
            ZStack(alignment: model.onRight ? .topTrailing : .topLeading) {
                stack(layout: layout, metrics: m, font: font)
                    .overlay(alignment: model.onRight ? .trailing : .leading) { spine(layout) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.onRight ? .topTrailing : .topLeading)
            .padding(.top, max(0, (geo.size.height - layout.stackHeight) / 2))
        }
    }

    private func stack(layout: DeckLayout, metrics m: DeckMetrics, font: DeckFont) -> some View {
        let total = visibleTabs.count + (hiddenCount > 0 ? 1 : 0) + model.buttons.count
        return VStack(spacing: layout.spacing) {
            ForEach(Array(visibleTabs.enumerated()), id: \.element.id) { idx, note in
                DeckTab(note: note, isOpen: model.state.expandedID == note.id, height: layout.itemHeight, strip: layout.pitch,
                        onRight: model.onRight, metrics: m, deckFont: font) { model.onTab(note.id) }
                    .staged(index: idx, total: total, revealed: model.revealed, onRight: model.onRight, travel: m.tabWidth + 24)
            }
            if hiddenCount > 0 {
                DeckMoreTab(count: hiddenCount, height: m.moreTabHeight, width: m.tabWidth, onRight: model.onRight) { model.showAll = true }
                    .padding(.top, m.tabGap - layout.spacing)
                    .staged(index: visibleTabs.count, total: total, revealed: model.revealed, onRight: model.onRight, travel: m.tabWidth + 24)
            }
            ForEach(Array(model.buttons.enumerated()), id: \.element) { i, button in
                DeckRoundButton(button: button, style: model.tileStyle, size: m.buttonSize) { rect in model.onButton(button, rect) }
                    .padding(.top, (i == 0 && visibleTabs.isEmpty && hiddenCount == 0 ? 0 : m.buttonGap) - (i == 0 ? layout.spacing : 0))
                    .padding(model.onRight ? .trailing : .leading, (m.tabWidth - m.buttonSize) / 2)
                    .staged(index: visibleTabs.count + (hiddenCount > 0 ? 1 : 0) + i, total: total, revealed: model.revealed,
                            onRight: model.onRight, travel: m.tabWidth + 24)
            }
        }
        .frame(width: m.tabWidth)
        .animation(.easeInOut(duration: 0.18), value: visibleTabs.map(\.id))
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
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        let palette = NotePalette.entry(at: note.color)
        ZStack(alignment: .top) {
            EdgeTabShape(onRight: onRight)
                .fill(palette.paperColor)
                .shadow(color: .black.opacity(isOpen || hovering ? 0.32 : 0.22), radius: isOpen || hovering ? 9 : 6,
                        x: onRight ? -3 : 3, y: 2)
            VerticalTabLabel(title: note.displayTitle, strip: strip, onRight: onRight, ink: palette.inkColor,
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
        .onTapGesture(perform: action)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isOpen)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: note.displayTitle))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, action)
        .help(Text(verbatim: note.displayTitle))
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
    let size: CGFloat
    let action: (CGRect) -> Void

    @State private var hovering = false

    var body: some View {
        GeometryReader { proxy in
            Button {
                action(proxy.frame(in: .global))
            } label: {
                Image(systemName: button.symbol)
                    .font(.system(size: size * 0.43, weight: .semibold))
                    .foregroundColor(style == .coloured ? .white : Color.primary.opacity(0.78))
                    .frame(width: size, height: size)
                    .background(background)
                    .scaleEffect(hovering ? 1.08 : 1)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(label)
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .glass:
            Circle().fill(.regularMaterial).shadow(color: .black.opacity(0.22), radius: 5, y: 1)
        case .coloured:
            Circle().fill(NotePalette.entry(at: button.accent).dashColor).shadow(color: .black.opacity(0.28), radius: 5, y: 1)
        }
    }

    private var label: Text {
        switch button {
        case .newNote: return Text("New Note")
        case .settings: return Text("Settings")
        case .status(.wifi): return Text(verbatim: "Wi-Fi")
        case .status(.battery): return Text("Battery")
        case .status(.volume): return Text("Volume")
        case .widget(.weather): return Text("Weather")
        case .widget(.nowPlaying): return Text("Now Playing")
        case .widget(.bluetooth): return Text("Bluetooth")
        }
    }
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
