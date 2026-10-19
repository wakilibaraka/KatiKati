import SwiftUI

/// Window zones (Phase 7A-P6): a grid of small zone icons; a press moves the window you were working in.
struct WindowsFlyoutView: View {
    @State private var blocked = false
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
