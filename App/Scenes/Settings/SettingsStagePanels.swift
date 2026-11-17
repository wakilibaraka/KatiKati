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

    /// Four sample windows from the engine's own solver, so the preview cannot drift from what tiling does.
    /// Monocle windows overlap by design, so they are drawn as an offset stack.
    static func rects(preset: TilingLayoutPreset, area: CGRect, gap: CGFloat) -> [CGRect] {
        if preset == .monocle {
            return (0..<3).map { i in
                CGRect(x: area.minX + CGFloat(i) * 8, y: area.minY + CGFloat(i) * 8, width: area.width - 16, height: area.height - 16)
            }
        }
        var tree = TilingTree()
        let ids = (0..<4).map { WindowID(rawValue: "preview\($0)") }
        ids.forEach { tree.insert($0) }
        let solved = TilingLayout.resolve(tree: tree, preset: preset, workArea: area, gaps: TilingGaps(inner: gap, outer: 0))
        // Solver output is bottom-left origin; SwiftUI offsets are top-left.
        return ids.compactMap { solved[$0] }.map {
            CGRect(x: $0.minX, y: area.minY + area.maxY - $0.maxY, width: $0.width, height: $0.height)
        }
    }
}

/// Shortcuts: keycaps for the feature shortcuts the user has bound. Reads the store only; no key monitor.
struct StageShortcuts: View {
    @ObservedObject var store: AppSettingsStore

    private static let features: [ShortcutAction] = [.launcher, .pinboard, .commandBar, .quickSettings, .drawer, .keepAwake, .translate]

    private func glyphs(_ trigger: ShortcutTrigger) -> String? { trigger.displayGlyphs }

    var body: some View {
        let bound = Self.features.compactMap { action in
            store.shortcutBindings[action].flatMap(glyphs).map { (action, $0) }
        }
        VStack(spacing: 6) {
            ForEach(bound, id: \.0) { action, keys in
                HStack(spacing: 8) {
                    Text(verbatim: SettingsLayoutPane.shortcutActionName(action))
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(verbatim: keys)
                        .font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.primary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.ultraThinMaterial))
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white.opacity(0.5), lineWidth: 1))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.2), value: bound.map(\.1))
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
