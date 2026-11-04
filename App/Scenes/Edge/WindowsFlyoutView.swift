import SwiftUI

/// Window zones (Phase 7A-P6): a grid of small zone icons; a press moves the window you were working in.
struct WindowsFlyoutView: View {
    @State private var blocked = false
    @State private var showLayouts = false
    @ObservedObject private var tiling = TilingEngine.shared
    @AppStorage(TilePalette.storageKey) private var palette: TilePalette = .classic
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.edgeBarStyle) private var barStyle

    private struct Zone: Identifiable { let id: SnapPosition; let title: Text }
    private static let rows: [[SnapPosition]] = [
        [.leftHalf, .rightHalf, .topHalf, .bottomHalf],
        [.topLeft, .topRight, .bottomLeft, .bottomRight],
        [.leftThird, .centerThird, .rightThird, .center],
        [.leftTwoThirds, .rightTwoThirds, .maximize],
    ]

    var body: some View {
        let size = ProductivityFlyout.size(.windows)
        let env = TileEnv(palette: palette, isDark: colorScheme == .dark, glass: barStyle == .liquidGlass)
        BandTile(env: env, kind: .alarms, width: size.width - 16, height: size.height - 16, header: {
            Text("Windows")
        }, content: {
            VStack(spacing: 10) {
                Picker("Mode", selection: $showLayouts) {
                    Text("Zones").tag(false)
                    Text("Layouts").tag(true)
                }
                .labelsHidden().pickerStyle(.segmented).controlSize(.small)
                if showLayouts { layoutsGrid(env: env) } else { zonesGrid(env: env) }
                if blocked {
                    Text("Windows needs Accessibility access.").font(.system(size: 11)).foregroundColor(env.secondary)
                    Button("Open Settings") { AgendaPane.openPrivacy("Privacy_Accessibility") }.font(.system(size: 11))
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
        })
        .padding(8)
    }

    private func zonesGrid(env: TileEnv) -> some View {
        VStack(spacing: 10) {
            ForEach(Array(Self.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { zone in
                        Button { press(zone) } label: { icon(zone, env: env) }
                            .buttonStyle(.plain)
                            .help(Self.title(zone))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// The display the pointer is on: that is where the drawer opened.
    private var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    }

    private func layoutsGrid(env: TileEnv) -> some View {
        let screen = targetScreen
        let current = screen.flatMap { tiling.layout(for: $0) }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
        return VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(LayoutCatalog.allCases, id: \.self) { layout in
                    Button {
                        guard AXIsProcessTrusted() else { blocked = true; return }
                        blocked = false
                        if let screen { tiling.setLayout(layout, forDisplay: screen.localizedName) }
                    } label: {
                        VStack(spacing: 3) {
                            layoutIcon(layout, env: env, selected: layout == current && tiling.isEnabled)
                            Text(layout.title).font(.system(size: 10)).foregroundColor(env.secondary).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(layout.summary)
                }
            }
            if let current, tiling.isEnabled {
                HStack {
                    Text("\(current.title) is on").font(.system(size: 11))
                    Spacer()
                    Button("Turn Off") { tiling.setEnabled(false) }.font(.system(size: 11))
                }
            }
        }
    }

    /// Miniature of the layout with four sample windows, so parked ones show as missing slots.
    private func layoutIcon(_ layout: LayoutCatalog, env: TileEnv, selected: Bool) -> some View {
        let w: CGFloat = 70, h: CGFloat = 44
        let ids = (1...4).map { WindowID(rawValue: "s\($0)") }
        let frames = layout.frames(for: ids, workArea: CGRect(x: 0, y: 0, width: w, height: h),
                                   gaps: TilingGaps(inner: 2, outer: 2))
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4).fill(selected ? env.accent(.alarms).opacity(0.25) : env.hairline)
            ForEach(Array(ids.filter { frames[$0] != nil }.enumerated()), id: \.element) { slot, id in
                let f = frames[id]!
                RoundedRectangle(cornerRadius: 2).fill(env.accent(.alarms))
                    .frame(width: f.width, height: f.height)
                    .offset(x: f.minX, y: h - f.maxY)
                    .onDrop(of: [.plainText], isTargeted: nil) { drop($0, layout: layout, slot: slot) }
            }
        }
        .frame(width: w, height: h)
    }

    /// A window dragged from the drawer lands in this slot of `layout` on the display under the mouse.
    private func drop(_ providers: [NSItemProvider], layout: LayoutCatalog, slot: Int) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }),
              let screen = targetScreen else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let raw = object as? String else { return }
            Task { @MainActor in
                TilingEngine.shared.place(WindowID(rawValue: raw), inSlot: slot, layout: layout, on: screen)
            }
        }
        return true
    }

    private func press(_ zone: SnapPosition) {
        blocked = WindowSnapService.apply(zone) == .needsAccessibility
    }

    /// A miniature screen with the zone filled in.
    private func icon(_ zone: SnapPosition, env: TileEnv) -> some View {
        let w: CGFloat = 52, h: CGFloat = 34
        let u = zone.unit
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4).fill(env.hairline)
            RoundedRectangle(cornerRadius: 3).fill(env.accent(.alarms))
                .frame(width: max(4, u.width * w - 2), height: max(4, u.height * h - 2))
                .offset(x: u.minX * w + 1, y: (1 - u.maxY) * h + 1)
        }
        .frame(width: w, height: h)
    }

    private static func title(_ zone: SnapPosition) -> Text {
        switch zone {
        case .leftHalf: return Text("Left Half")
        case .rightHalf: return Text("Right Half")
        case .topHalf: return Text("Top Half")
        case .bottomHalf: return Text("Bottom Half")
        case .topLeft: return Text("Top Left")
        case .topRight: return Text("Top Right")
        case .bottomLeft: return Text("Bottom Left")
        case .bottomRight: return Text("Bottom Right")
        case .leftThird: return Text("Left Third")
        case .centerThird: return Text("Center Third")
        case .rightThird: return Text("Right Third")
        case .leftTwoThirds: return Text("Left Two Thirds")
        case .rightTwoThirds: return Text("Right Two Thirds")
        case .center: return Text("Center")
        case .maximize: return Text("Maximize")
        }
    }
}
