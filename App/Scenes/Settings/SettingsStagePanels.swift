import SwiftUI

/// What the stage draws on top of the wallpaper for the pages that have their own surface. Each view
/// reads settings only (no feed, no event tap, no panel), so it can't start anything.

/// Control Center: the panel on its side, at its width and anchor, with a block per enabled tile.
struct StageControlCenter: View {
    @ObservedObject var store: AppSettingsStore
    @AppStorage("com.katikati.controlcenter.side") private var sideRaw = EdgeSide.right.rawValue

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / LayoutThumbnailModel.referenceScreen.width
            let width = store.controlCenterSize.width * scale
            let tiles = store.controlCenterWidgets.count + store.controlCenterToggles.count
            // Height grows with content, capped to the screen like the real panel.
            let height = min(proxy.size.height * 0.86, (60 + CGFloat(tiles) * 34) * scale * 1.6)
            VStack {
                if store.controlCenterAnchor != .top { Spacer(minLength: 0) }
                panel(width: width, height: height, scale: scale)
                if store.controlCenterAnchor != .bottom { Spacer(minLength: 0) }
            }
            .padding(.vertical, 18 * scale + 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: sideRaw == EdgeSide.left.rawValue ? .leading : .trailing)
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: store.controlCenterSize)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: store.controlCenterAnchor)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: sideRaw)
    }

    private func panel(width: CGFloat, height: CGFloat, scale: CGFloat) -> some View {
        let count = max(1, store.controlCenterWidgets.count + store.controlCenterToggles.count)
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                VStack(spacing: 3) {
                    ForEach(0..<min(count, 12), id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 3, style: .continuous).fill(.white.opacity(0.35))
                    }
                }
                .padding(5)
            )
            .frame(width: max(24, width), height: max(30, height))
    }
}

/// Radial Dial: a ring of wedges in the chosen theme's colours.
struct StageRadialDial: View {
    @AppStorage("com.katikati.dial.enabled") private var enabled = true
    @AppStorage("com.katikati.dial.theme") private var themeRaw = RadialDialTheme.lilacGlass.rawValue
    @AppStorage(RadialDialConfigStore.storageKey) private var slicesData = Data()

    private var theme: RadialDialTheme { RadialDialTheme(rawValue: themeRaw) ?? .lilacGlass }
    private var sliceCount: Int {
        _ = slicesData
        return max(2, min(10, RadialDialConfigStore.loadNodes().count))
    }

    private var palette: (fill: Color, edge: Color) {
        switch theme {
        case .lilacGlass: return (Color(red: 0.72, green: 0.58, blue: 0.95).opacity(0.55), .white.opacity(0.7))
        case .darkObsidian: return (Color.black.opacity(0.78), .white.opacity(0.18))
        case .systemFrosted: return (Color.white.opacity(0.45), .white.opacity(0.6))
        case .neonCyber: return (Color.black.opacity(0.8), Color(red: 0.1, green: 0.95, blue: 0.95))
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let d = min(proxy.size.width, proxy.size.height) * 0.62
            let count = sliceCount
            ZStack {
                ForEach(0..<count, id: \.self) { i in
                    Wedge(index: i, count: count)
                        .fill(palette.fill)
                        .overlay(Wedge(index: i, count: count).stroke(palette.edge, lineWidth: 1))
                }
                Circle().fill(palette.fill).overlay(Circle().stroke(palette.edge, lineWidth: 1)).frame(width: d * 0.3)
            }
            .frame(width: d, height: d)
            .opacity(enabled ? 1 : 0.3)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .animation(.easeOut(duration: 0.2), value: themeRaw)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: slicesData)
    }

    private struct Wedge: Shape {
        let index: Int
        let count: Int

        func path(in rect: CGRect) -> Path {
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let r = rect.width / 2
            let step = 360.0 / Double(count)
            let start = Angle(degrees: -90 + step * Double(index) + 1.5)
            let end = Angle(degrees: -90 + step * Double(index + 1) - 1.5)
            var p = Path()
            p.addArc(center: c, radius: r, startAngle: start, endAngle: end, clockwise: false)
            p.addArc(center: c, radius: r * 0.34, startAngle: end, endAngle: start, clockwise: true)
            p.closeSubpath()
            return p
        }
    }
}

/// Window Management: four sample windows laid out by the chosen preset, with the inner and outer gap.
struct StageTiling: View {
    @ObservedObject private var engine = TilingEngine.shared

    var body: some View {
        GeometryReader { proxy in
            let outer = engine.gaps.outer * 0.25
            let inner = engine.gaps.inner * 0.25
            let area = CGRect(origin: .zero, size: proxy.size).insetBy(dx: outer + 10, dy: outer + 22)
            ZStack(alignment: .topLeading) {
                ForEach(Array(Self.rects(preset: engine.preset, area: area, gap: inner).enumerated()), id: \.offset) { _, r in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.white.opacity(0.5), lineWidth: 1))
                        .frame(width: max(2, r.width), height: max(2, r.height))
                        .offset(x: r.minX, y: r.minY)
                }
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: engine.preset)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: engine.gaps)
    }

    /// Four sample windows from the engine's own solver; the maths lives in Core so the gesture
    /// preview, which the unit-test target also compiles, can draw the same picture.
    static func rects(preset: TilingLayoutPreset, area: CGRect, gap: CGFloat) -> [CGRect] {
        TilingPreview.rects(preset: preset, area: area, gap: gap)
    }
}

/// Shortcuts: keycaps for the feature shortcuts the user has bound. Reads the store only; no key monitor.
/// Which action the stage describes. Hovering a row, or picking a chip, sets it; nothing polls.
final class ShortcutStageFocus: ObservableObject {
    static let shared = ShortcutStageFocus()
    @Published var action: ShortcutAction?
}

/// Shortcuts: a mini keyboard that lights the focused binding, and what that binding will do.
/// Reads the store and the focus model only — no key monitor, no timers, no idle work.
struct StageShortcuts: View {
    @ObservedObject var store: AppSettingsStore
    @ObservedObject private var focus = ShortcutStageFocus.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let letters: [[String]] = [
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
        ["Z", "X", "C", "V", "B", "N", "M"]
    ]
    private static let modifierCaps = ["⌃", "⌥", "⇧", "⌘", "✦", "fn"]
    private static let arrows = ["←", "↓", "↑", "→"]

    private var action: ShortcutAction {
        focus.action ?? Self.boundFeatureActions(in: store).first ?? .launcher
    }
    private var trigger: ShortcutTrigger { store.shortcutBindings[action] ?? action.defaultTrigger }
    private var keyboard: MiniKeyboardState { MiniKeyboardState.from(trigger) }
    private var conflict: ShortcutConflict {
        ShortcutConflictDetector.conflict(for: action, trigger: trigger, among: store.shortcutBindings)
    }

    /// Bound actions in the Core band: short enough to read as chips, and the ones people bind first.
    private static func boundFeatureActions(in store: AppSettingsStore) -> [ShortcutAction] {
        ShortcutAction.allCases.filter { $0.category == .core && (store.shortcutBindings[$0] ?? .off) != .off }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            keyboardMap
            inspector
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: keyboard)
    }

    private var keyboardMap: some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                keycap("esc", lit: false)
                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"], id: \.self) { keycap($0, lit: false) }
            }
            ForEach(Self.letters, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(row, id: \.self) { keycap($0, lit: isMain($0)) }
                }
            }
            HStack(spacing: 3) {
                ForEach(Self.modifierCaps, id: \.self) { keycap($0, lit: keyboard.litModifiers.contains($0)) }
                keycap("Space", lit: keyboard.mainKey == "Space", wide: true)
                ForEach(Self.arrows, id: \.self) { keycap($0, lit: isMain($0)) }
            }
        }
    }

    private func isMain(_ label: String) -> Bool {
        keyboard.mainKey.map { $0.caseInsensitiveCompare(label) == .orderedSame } ?? false
    }

    private func keycap(_ label: String, lit: Bool, wide: Bool = false) -> some View {
        Text(verbatim: label)
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(lit ? .white : Color.primary.opacity(0.72))
            .frame(width: wide ? 70 : 21, height: 19)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(lit ? Color.accentColor.opacity(0.78) : Color.white.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.white.opacity(lit ? 0.55 : 0.16), lineWidth: 1)
            )
            .overlay(
                // Double-tap and Hold keep a static ring: it reads as "timing" without animating.
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.white.opacity(keyboard.pulses && lit ? 0.5 : 0), lineWidth: 2)
            )
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(verbatim: SettingsLayoutPane.shortcutActionName(action))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(verbatim: trigger.displayGlyphs ?? String(localized: "Off"))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.ultraThinMaterial))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white.opacity(0.5), lineWidth: 1))
                .fixedSize()
            statusLine
            chips
        }
        .frame(width: 196, alignment: .leading)
    }

    @ViewBuilder private var statusLine: some View {
        switch conflict {
        case .clear:
            Label { Text("Clear") } icon: { Image(systemName: "checkmark.circle") }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        case .internalDuplicate(let other):
            Label { Text("Another action uses the same shortcut") } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                .font(.system(size: 9))
                .foregroundStyle(.orange)
                .help(Text(verbatim: SettingsLayoutPane.shortcutActionName(other)))
        case .systemClash(let reason):
            Label { Text("Used by macOS") } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                .font(.system(size: 9))
                .foregroundStyle(.orange)
                .help(Text(verbatim: reason))
        }
    }

    private var chips: some View {
        HStack(spacing: 4) {
            ForEach(Array(Self.boundFeatureActions(in: store).prefix(4)), id: \.self) { candidate in
                Button { ShortcutStageFocus.shared.action = candidate } label: {
                    Text(verbatim: SettingsLayoutPane.shortcutActionName(candidate))
                        .font(.system(size: 8, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(action == candidate ? 0.24 : 0.08)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Downloads: a queue silhouette (no invented file names) over a 24-hour strip with the quiet-hours window.
struct StageDownloads: View {
    @AppStorage(TorrentSettings.quietStartHourKey) private var quietStart = 0
    @AppStorage(TorrentSettings.quietEndHourKey) private var quietEnd = 0

    var body: some View {
        VStack(spacing: 8) {
            ForEach([0.8, 0.45, 0.15], id: \.self) { progress in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(height: 16)
                    .overlay(alignment: .leading) {
                        GeometryReader { p in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(.white.opacity(0.55))
                                .frame(width: p.size.width * progress)
                        }
                    }
            }
            quietStrip
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Lit cells are the hours when sharing is capped; equal hours means no window.
    private var quietStrip: some View {
        HStack(spacing: 1) {
            ForEach(0..<24, id: \.self) { hour in
                Rectangle().fill(isQuiet(hour) ? Color.indigo.opacity(0.85) : .white.opacity(0.3)).frame(height: 6)
            }
        }
        .clipShape(Capsule())
        .animation(.easeOut(duration: 0.2), value: quietStart)
        .animation(.easeOut(duration: 0.2), value: quietEnd)
    }

    private func isQuiet(_ hour: Int) -> Bool {
        if quietStart == quietEnd { return false }
        return quietStart < quietEnd ? (quietStart..<quietEnd).contains(hour) : (hour >= quietStart || hour < quietEnd)
    }
}

/// Edge Bars: miniature Right EdgeBar showing enabled items, style (Paper / Liquid Glass / Fluid / Bezel Dock),
/// size scale, and vertical edge position in real time.
struct StageEdgeBars: View {
    @ObservedObject var store: AppSettingsStore

    private var activeItems: [EdgeBarContent] {
        guard store.edgeBarPreset != .off else { return [] }
        var items = store.edgeContent[.right] ?? []
        if store.edgePrefs.showAppsInBar, !items.contains(.apps) {
            items.insert(.apps, at: 0)
        }
        return items
    }

    var body: some View {
        GeometryReader { proxy in
            let items = activeItems
            if !items.isEmpty {
                let scale = proxy.size.width / LayoutThumbnailModel.referenceScreen.width
                let deckScale = CGFloat(store.deckScale(for: .right))
                let unit = max(5, 11 * scale * deckScale)
                let spacing = max(1.5, 2.5 * scale * deckScale)
                let style = store.edgePrefs.barStyle
                let topInset = 18 * scale + 6
                let bottomInset = 26 * scale + 6
                let yRatio = CGFloat(store.deckYRatio(for: .right))

                GeometryReader { inner in
                    let barBoxHeight = estimatedHeight(items: items, unit: unit, spacing: spacing, style: style)
                    let travel = max(0, inner.size.height - barBoxHeight)
                    // yRatio 1 = top, yRatio 0 = bottom (matching DeckGeometry).
                    let yOffset = travel * (1 - yRatio)
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        previewStack(items: items, unit: unit, spacing: spacing, style: style)
                    }
                    .padding(.top, yOffset)
                }
                .padding(.top, topInset)
                .padding(.bottom, bottomInset)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: store.edgeBarPreset)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: store.edgePrefs)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: store.widgetTiles)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: store.productivityItems)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: store.edgeTileStyle)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: store.deckScale(for: .right))
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: store.deckYRatio(for: .right))
    }

    private func previewStack(items: [EdgeBarContent], unit: CGFloat, spacing: CGFloat, style: EdgeBarStyle) -> some View {
        VStack(alignment: .trailing, spacing: spacing) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, content in
                itemView(content, unit: unit, style: style)
            }
        }
        .padding(.vertical, style == .bezelDock ? max(4, unit * 0.55) : max(2, unit * 0.25))
        .padding(.leading, max(3, unit * 0.32))
        .padding(.trailing, max(3, unit * 0.28))
        .background {
            if style == .bezelDock {
                EdgeBezelDockShape(onRight: true, earRadius: max(4, unit * 0.45), cornerRadius: max(5, unit * 0.5))
                    .fill(Color(red: 0.05, green: 0.05, blue: 0.06).opacity(0.95))
                    .overlay(
                        EdgeBezelDockShape(onRight: true, earRadius: max(4, unit * 0.45), cornerRadius: max(5, unit * 0.5))
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                    )
            } else if style == .fluid {
                RoundedRectangle(cornerRadius: unit * 0.6, style: .continuous)
                    .fill(Color(red: 0.07, green: 0.07, blue: 0.09).opacity(0.92))
                    .overlay(RoundedRectangle(cornerRadius: unit * 0.6, style: .continuous).strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
            } else if style == .liquidGlass {
                RoundedRectangle(cornerRadius: unit * 0.6, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: unit * 0.6, style: .continuous).strokeBorder(.white.opacity(0.45), lineWidth: 0.5))
            }
        }
    }

    @ViewBuilder
    private func itemView(_ content: EdgeBarContent, unit: CGFloat, style: EdgeBarStyle) -> some View {
        switch content {
        case .apps:
            VStack(spacing: max(1.5, unit * 0.2)) {
                ForEach(0..<4, id: \.self) { idx in
                    let appColors: [Color] = [.blue, .orange, .green, .purple]
                    RoundedRectangle(cornerRadius: max(2, unit * 0.24), style: .continuous)
                        .fill(appColors[idx].opacity(0.9))
                        .frame(width: unit, height: unit)
                        .overlay(alignment: .trailing) {
                            if store.edgePrefs.showRunningDots && idx < 3 {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: max(2, unit * 0.22), height: max(2, unit * 0.22))
                                    .offset(x: 1.5)
                            }
                        }
                }
            }
        case .notes:
            VStack(spacing: -unit * 0.22) {
                ForEach(0..<3, id: \.self) { idx in
                    let entry = NotePalette.entry(at: idx)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(style == .fluid || style == .bezelDock ? Color(white: 0.14) : entry.paperColor)
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(entry.dashColor).frame(width: 1.5)
                        }
                        .frame(width: unit * 1.15, height: unit * 0.95)
                }
            }
        case .status:
            HStack(spacing: 1.5) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(Color.white.opacity(0.75)).frame(width: max(2, unit * 0.28), height: max(2, unit * 0.28))
                }
            }
        case .focus:
            VStack(spacing: 1.5) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(Color.blue, lineWidth: 1)
                    .frame(width: unit * 0.7, height: unit * 0.7)
                    .overlay(Image(systemName: "bolt.fill").font(.system(size: unit * 0.35)).foregroundColor(.white))
                RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(Color.white.opacity(0.3)).frame(width: unit * 0.7, height: unit * 0.25)
            }
            .frame(width: unit * 0.95, height: unit * 1.3)
            .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.black.opacity(0.8)))
        case .clock:
            VStack(spacing: 1) {
                RoundedRectangle(cornerRadius: 1, style: .continuous).fill(Color.white.opacity(0.8)).frame(width: unit * 0.65, height: unit * 0.25)
                RoundedRectangle(cornerRadius: 1, style: .continuous).fill(Color.white.opacity(0.4)).frame(width: unit * 0.5, height: unit * 0.18)
            }
            .frame(width: unit * 0.95, height: unit * 0.85)
            .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.black.opacity(0.8)))
        case .batteryWifi:
            HStack(spacing: 2) {
                Circle().strokeBorder(Color.white, lineWidth: 1).frame(width: unit * 0.35, height: unit * 0.35)
                Image(systemName: "wifi").font(.system(size: unit * 0.3)).foregroundColor(.white)
            }
            .frame(width: unit * 0.95, height: unit * 0.5)
            .background(Capsule().fill(Color.black.opacity(0.8)))
        case .habits:
            VStack(spacing: 1.5) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 1.5) {
                        ForEach(0..<4, id: \.self) { _ in
                            Circle().fill(Color.blue.opacity(0.7)).frame(width: 2, height: 2)
                        }
                    }
                }
            }
            .frame(width: unit * 0.95, height: unit * 0.85)
            .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.black.opacity(0.8)))
        case .hydration:
            VStack(spacing: 1) {
                RoundedRectangle(cornerRadius: 1, style: .continuous).fill(Color.cyan.opacity(0.5)).frame(width: unit * 0.5, height: unit * 0.2)
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Color.cyan).frame(width: unit * 0.7, height: unit * 0.4)
            }
            .frame(width: unit * 0.95, height: unit * 1.0)
            .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.black.opacity(0.8)))
        case .food:
            VStack(spacing: 1.5) {
                Image(systemName: "fork.knife").font(.system(size: unit * 0.35)).foregroundColor(.orange)
                RoundedRectangle(cornerRadius: 1, style: .continuous).fill(Color.white.opacity(0.5)).frame(width: unit * 0.5, height: unit * 0.2)
            }
            .frame(width: unit * 0.95, height: unit * 0.95)
            .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.black.opacity(0.8)))
        case .notesPreview:
            VStack(alignment: .leading, spacing: 1.5) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 1.5) {
                        Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5).frame(width: 2, height: 2)
                        RoundedRectangle(cornerRadius: 0.5).fill(Color.white.opacity(0.6)).frame(width: unit * 0.45, height: 1.5)
                    }
                }
            }
            .frame(width: unit * 0.95, height: unit * 1.1)
            .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.black.opacity(0.8)))
        case .newNote, .settings, .widget, .productivity:
            let tint = buttonTint(content)
            Circle()
                .fill(style == .bezelDock || style == .fluid ? Color.white.opacity(0.18) : (store.edgeTileStyle == .coloured ? tint : Color.white.opacity(0.45)))
                .overlay(Circle().strokeBorder(tint.opacity(style == .bezelDock || style == .fluid ? 0.85 : 0.35), lineWidth: 0.75))
                .frame(width: unit * 0.86, height: unit * 0.86)
        }
    }

    private func buttonTint(_ content: EdgeBarContent) -> Color {
        switch content {
        case .focus: return .blue
        case .clock: return .white
        case .batteryWifi: return .green
        case .habits: return .purple
        case .hydration: return .cyan
        case .food: return .orange
        case .notesPreview: return .yellow
        case .newNote: return NotePalette.entry(at: 0).dashColor
        case .settings: return NotePalette.entry(at: 7).dashColor
        case let .widget(tile):
            let idx: Int
            switch tile {
            case .weather: idx = 1
            case .nowPlaying: idx = 2
            case .bluetooth: idx = 4
            case .systemMonitor: idx = 6
            }
            return NotePalette.entry(at: idx).dashColor
        case let .productivity(item):
            let idx: Int
            switch item {
            case .reminders: idx = 3
            case .alarms: idx = 6
            case .time: idx = 5
            case .tasks: idx = 2
            case .clipboard: idx = 1
            case .capture: idx = 4
            case .screenshot: idx = 2
            case .windows: idx = 7
            case .screenTime: idx = 0
            }
            return NotePalette.entry(at: idx).dashColor
        default: return .white
        }
    }

    private func estimatedHeight(items: [EdgeBarContent], unit: CGFloat, spacing: CGFloat, style: EdgeBarStyle) -> CGFloat {
        let rows = items.reduce(CGFloat(0)) { acc, item in
            switch item {
            case .apps: return acc + 4 * unit + 3 * max(1.5, unit * 0.2)
            case .notes: return acc + 2.5 * unit
            case .status: return acc + unit * 0.35
            default: return acc + unit * 0.86
            }
        }
        return rows + CGFloat(max(0, items.count - 1)) * spacing + (style == .bezelDock ? unit * 1.1 : unit * 0.5)
    }
}

/// Live preview for Drawer: shows the circular Background Apps Drawer capsule on the left or right flank of the Dock bar.
struct StageDrawer: View {
    @ObservedObject var store: AppSettingsStore

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            let scale = w / LayoutThumbnailModel.referenceScreen.width
            let dockY = h - max(22, 26 * scale + 10)
            let flankX = store.drawerPlacement == .left ? max(28, w * 0.19) : min(w - 28, w * 0.81)

            ZStack {
                if store.showsDrawerSlot {
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .frame(width: min(76, w * 0.22), height: 42)
                            .overlay(
                                LazyVGrid(columns: Array(repeating: GridItem(.fixed(12), spacing: 4), count: 3), spacing: 4) {
                                    ForEach(0..<6, id: \.self) { _ in
                                        RoundedRectangle(cornerRadius: 2.5).fill(.white.opacity(0.6)).frame(width: 12, height: 12)
                                    }
                                }
                            )
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(0.32), lineWidth: 0.75))
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 16, height: 16)
                            .overlay(Image(systemName: "chevron.up").font(.system(size: 7, weight: .bold)).foregroundStyle(.white))
                            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 1.5))
                    }
                    .position(x: flankX, y: dockY - 34)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: store.showsDrawerSlot)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: store.drawerPlacement)
    }
}

/// Live preview for Shelf: shows the Notch File Tray auto-open pill and the Floating Card Stack / Compact Grid above the Dock.
struct StageShelf: View {
    @ObservedObject var store: AppSettingsStore
    @AppStorage(ShelfPolicy.presentationStyleKey) private var styleRaw = ShelfPresentationStyle.floatingCardStack.rawValue
    @AppStorage(ShelfPolicy.showTextExcerptKey) private var showTextExcerpt = true
    @AppStorage(ShelfPolicy.notchAutoOpenOnDragKey) private var notchAutoOpenOnDrag = true
    @AppStorage(ShelfPolicy.syncNotchTrayKey) private var syncNotchTray = true

    private var presentationStyle: ShelfPresentationStyle { ShelfPresentationStyle(rawValue: styleRaw) ?? .floatingCardStack }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            VStack(spacing: 0) {
                if notchAutoOpenOnDrag {
                    HStack(spacing: 5) {
                        Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 8, weight: .semibold)).foregroundStyle(.cyan)
                        Text("Notch File Tray").font(.system(size: 8, weight: .semibold)).foregroundStyle(.white)
                        if syncNotchTray { Circle().fill(.green).frame(width: 4, height: 4) }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.24), lineWidth: 0.75))
                    .padding(.top, max(16, h * 0.14))
                }
                Spacer(minLength: 0)
                shelfPreview(width: min(110, w * 0.34))
                    .padding(.bottom, max(24, h * 0.18))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: styleRaw)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: showTextExcerpt)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: notchAutoOpenOnDrag)
    }

    @ViewBuilder
    private func shelfPreview(width: CGFloat) -> some View {
        if presentationStyle == .floatingCardStack {
            VStack(spacing: 4) {
                Text("Browse").font(.system(size: 7.5, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 3)
                    .background(Capsule().fill(Color(red: 0.44, green: 0.40, blue: 0.70).opacity(0.92)))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(white: 0.10))
                    .frame(width: width * 0.82, height: 26)
                    .overlay(RoundedRectangle(cornerRadius: 3).fill(.blue.opacity(0.4)).padding(4))
                    .rotationEffect(.degrees(-2))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(white: 0.96))
                    .frame(width: width * 0.82, height: showTextExcerpt ? 30 : 20)
                    .overlay(alignment: .leading) {
                        VStack(alignment: .leading, spacing: 2) {
                            Capsule().fill(Color.black.opacity(0.75)).frame(width: width * 0.42, height: 2.5)
                            if showTextExcerpt {
                                Capsule().fill(Color.black.opacity(0.38)).frame(width: width * 0.62, height: 2)
                                Capsule().fill(Color.black.opacity(0.32)).frame(width: width * 0.50, height: 2)
                            }
                        }.padding(.horizontal, 6)
                    }
                    .rotationEffect(.degrees(1.6))
            }
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(16), spacing: 4), count: 3), spacing: 4) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(.white.opacity(0.65)).frame(width: 16, height: 16)
                }
            }
            .padding(7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.3), lineWidth: 0.75))
        }
    }
}

// MARK: - Mission Control (MC-3)

/// The Mission Control surface, shared by the live overlay and the stage preview so the two cannot
/// disagree: every border, tint, badge and dim comes from the same `MissionControl*` resolution.
/// `frames` are already in this view's coordinate space (top-left origin, like Mission Control).
struct MissionControlSurface: View {
    var frames: [MissionControlWindowFrame]
    var configuration: MissionControlConfiguration
    var hoveredID: MissionControlWindowFrame.ID?
    var focusedID: MissionControlWindowFrame.ID?
    var query: String = ""
    var spaceTitle: String?
    var spaceAccent: MissionControlColor?
    var showsButtons = false
    /// Only the display that owns the keyboard target (or hover) shows the filter readout.
    var showsFilterChip = true
    var onAction: ((MissionControlWindowAction) -> Void)?

    private var colouring: MissionControlColouring { configuration.colouring }
    private var naming: MissionControlNaming { configuration.naming }
    private var framing: MissionControlFraming { configuration.framing }
    private var presentation: MissionControlPresentation { configuration.presentation }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let groupStyle = framing.groupBorder() {
                ForEach(MissionControlGrouping.groups(for: frames, padding: presentation.groupPadding)) { group in
                    RoundedRectangle(cornerRadius: presentation.cornerRadius + 6, style: .continuous)
                        .stroke(
                            colouring.borderColor(
                                forBundleID: group.bundleID,
                                category: .inferred(fromBundleID: group.bundleID),
                                state: .standard
                            ).color.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1.5, dash: groupStyle == .dashed ? [7, 5] : [])
                        )
                        .frame(width: group.frame.width, height: group.frame.height)
                        .position(x: group.frame.midX, y: group.frame.midY)
                        .allowsHitTesting(false)
                }
            }
            ForEach(frames) { frame in
                window(frame)
            }
            if let spaceTitle {
                spacePill(spaceTitle)
            }
            if presentation.showsFilterChip, showsFilterChip, !query.isEmpty {
                filterChip(query)
            }
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.85), value: hoveredID)
        .animation(.easeInOut(duration: 0.18), value: query)
    }

    private func window(_ frame: MissionControlWindowFrame) -> some View {
        let hovered = frame.id == hoveredID
        let keyboardTargeted = frame.id == focusedID
        let style = framing.style(isFocused: frame.isFocused || keyboardTargeted, isHovered: hovered, state: frame.state)
        let colour = colouring.borderColor(
            forBundleID: frame.bundleID, category: frame.category, state: frame.state
        )
        let tint = colouring.tint(forBundleID: frame.bundleID, category: frame.category)
        let opacity = MissionControlFilter.opacity(query: query, title: frame.title, app: frame.appName)
        let shape = RoundedRectangle(cornerRadius: presentation.cornerRadius, style: .continuous)
        return ZStack(alignment: .topLeading) {
            shape.fill(colour.color.opacity(tint))
            border(style, colour: colour, shape: shape)
            if let badge = naming.badgeTitle(app: frame.appName, title: frame.title) {
                HStack(spacing: 5) {
                    if naming.showsAppIcon {
                        Image(systemName: "app.fill")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    Text(verbatim: badge)
                        .font(.system(size: 9.5, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(Capsule().fill(.black.opacity(presentation.badgeOpacity)))
                .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 0.75))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Self.alignment(for: presentation.badgePlacement))
                .padding(8)
            }
            if hovered, showsButtons, let onAction {
                HStack(spacing: 5) {
                    ForEach(configuration.actions.buttons.shownActions, id: \.self) { action in
                        Button { onAction(action) } label: {
                            Image(systemName: Self.symbol(for: action))
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(.black.opacity(0.66)))
                                .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 0.75))
                        }
                        .buttonStyle(.plain)
                        .help(Text(verbatim: action.rawValue.capitalized))
                    }
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.black.opacity(0.35)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(8)
            }
        }
        .frame(width: max(1, frame.frame.width), height: max(1, frame.frame.height))
        .opacity(opacity)
        .position(x: frame.frame.midX, y: frame.frame.midY)
        .accessibilityLabel(Text(verbatim: naming.badgeTitle(app: frame.appName, title: frame.title) ?? frame.appName))
    }

    @ViewBuilder
    private func border(_ style: MissionControlBorderStyle, colour: MissionControlColor, shape: RoundedRectangle) -> some View {
        switch style {
        case .none:
            EmptyView()
        case .hairline:
            shape.stroke(colour.color, lineWidth: max(1, presentation.borderWidth * 0.4))
        case .solid:
            shape.stroke(colour.color, lineWidth: presentation.borderWidth)
        case .dashed:
            shape.stroke(colour.color, style: StrokeStyle(lineWidth: max(1, presentation.borderWidth * 0.8), dash: [6, 4]))
        case .glow:
            shape.stroke(colour.color, lineWidth: max(1, presentation.borderWidth * 0.8))
                .shadow(color: colour.color.opacity(0.85), radius: 9)
        }
    }

    private func spacePill(_ title: String) -> some View {
        let accent = (spaceAccent ?? presentation.accentFallback).color
        return HStack(spacing: 6) {
            Circle().fill(accent).frame(width: 7, height: 7)
            Text(verbatim: title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(.black.opacity(0.55)))
        .overlay(Capsule().stroke(accent.opacity(0.85), lineWidth: 1))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Self.alignment(for: presentation.spaceTitlePlacement))
        .padding(10)
        .allowsHitTesting(false)
    }

    /// The type-to-filter readout: the query, how many windows match, and Escape as the way out.
    private func filterChip(_ text: String) -> some View {
        let matches = frames.filter {
            MissionControlFilter.matches(query: text, title: $0.title, app: $0.appName)
        }.count
        return HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 10, weight: .semibold))
            Text(verbatim: "\(text)  ·  \(matches)/\(frames.count)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(.black.opacity(0.6)))
        .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.75))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Self.alignment(for: presentation.spaceTitlePlacement.opposite))
        .padding(12)
        .allowsHitTesting(false)
    }

    static func alignment(for placement: MissionControlPlacement) -> Alignment {
        switch placement {
        case .top: return .top
        case .bottom: return .bottom
        case .leading: return .leading
        case .trailing: return .trailing
        }
    }

    static func symbol(for action: MissionControlWindowAction) -> String {
        switch action {
        case .close: return "xmark"
        case .minimize: return "minus"
        case .zoom: return "arrow.up.left.and.arrow.down.right"
        case .hide: return "eye.slash"
        case .quit: return "power"
        }
    }
}

private extension MissionControlColor {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
}

/// MC-3: the stage's Mission Control preview. It draws the same `MissionControlSurface` the live
/// overlay uses, over four symbolic thumbnails, and reloads whenever the section writes a setting —
/// so Naming, Framing, Colouring and the hover cluster are visible before Mission Control opens.
struct StageMissionControl: View {
    var store: AppSettingsStore
    @State private var configuration = MissionControlSettings.load()
    @State private var hoveredID: MissionControlWindowFrame.ID? = 2

    private var frames: [MissionControlWindowFrame] {
        [
            frame(1, app: "Safari", title: "Release notes", x: 0.06, y: 0.16, w: 0.40, h: 0.34, focused: true,
                  bundle: "com.apple.Safari"),
            frame(2, app: "Xcode", title: "KatiKati", x: 0.54, y: 0.10, w: 0.38, h: 0.36,
                  bundle: "com.apple.dt.Xcode"),
            frame(3, app: "Terminal", title: "swift test", x: 0.10, y: 0.58, w: 0.36, h: 0.30,
                  bundle: "com.apple.Terminal"),
            frame(4, app: "Slack", title: "Design", x: 0.52, y: 0.54, w: 0.34, h: 0.32, state: .minimized,
                  bundle: "com.tinyspeck.slackmacgap")
        ]
    }

    var body: some View {
        GeometryReader { proxy in
            MissionControlSurface(
                frames: frames.map { offset($0, in: proxy.size) },
                configuration: configuration,
                hoveredID: hoveredID,
                focusedID: 1,
                spaceTitle: configuration.naming.spaceTitle(forSpaceID: "2", index: 2),
                spaceAccent: configuration.colouring.accent(forSpaceID: "2"),
                showsButtons: true,
                onAction: { _ in }
            )
            .padding(.horizontal, 10)
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            configuration = MissionControlSettings.load()
        }
    }

    private func frame(
        _ id: UInt32, app: String, title: String,
        x: Double, y: Double, w: Double, h: Double,
        state: MissionControlWindowState = .standard, focused: Bool = false, bundle: String?
    ) -> MissionControlWindowFrame {
        MissionControlWindowFrame(
            id: id, bundleID: bundle, appName: app, title: title,
            frame: CGRect(x: x, y: y, width: w, height: h),
            state: state, isFocused: focused
        )
    }

    private func offset(_ frame: MissionControlWindowFrame, in size: CGSize) -> MissionControlWindowFrame {
        MissionControlWindowFrame(
            id: frame.id, bundleID: frame.bundleID, appName: frame.appName, title: frame.title,
            frame: CGRect(
                x: frame.frame.minX * size.width, y: frame.frame.minY * size.height,
                width: frame.frame.width * size.width, height: frame.frame.height * size.height
            ),
            state: frame.state, isFocused: frame.isFocused
        )
    }
}

/// MC-2: the hover control cluster in its own small, click-accepting panel. Keeping it separate from
/// the full-screen surface is what lets the surface ignore the mouse and leave Mission Control's own
/// navigation untouched.
struct MissionControlControlCluster: View {
    var actions: [MissionControlWindowAction]
    var onAction: (MissionControlWindowAction) -> Void

    var body: some View {
        HStack(spacing: 5) {
            ForEach(actions, id: \.self) { action in
                Button { onAction(action) } label: {
                    Image(systemName: MissionControlSurface.symbol(for: action))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.black.opacity(0.72)))
                        .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 0.75))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: action.rawValue.capitalized))
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.35)))
    }
}
