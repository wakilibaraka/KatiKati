import SwiftUI

/// E3: Persisted tap counter store for the Sydedock / Edge Bar counter widget.
@MainActor
final class EdgeCounterStore: ObservableObject {
    static let shared = EdgeCounterStore()

    private static let countKey = "com.katikati.edge.counter.count"
    private static let labelKey = "com.katikati.edge.counter.label"

    @Published var count: Int {
        didSet { UserDefaults.standard.set(count, forKey: Self.countKey) }
    }

    @Published var label: String {
        didSet { UserDefaults.standard.set(label, forKey: Self.labelKey) }
    }

    private init() {
        let d = UserDefaults.standard
        count = d.integer(forKey: Self.countKey)
        label = d.string(forKey: Self.labelKey) ?? "#"
    }

    func increment() { count += 1 }
    func decrement() { count = max(0, count - 1) }
    func reset() { count = 0 }
}

/// E3: Sydedock-style inline counter card (`-` / count / `+`) with context-menu reset.
struct DeckCounterCardView: View {
    @ObservedObject private var store = EdgeCounterStore.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dockThemeStyle) private var dockThemeStyle

    private var theme: DockThemeTokens { .resolved(for: colorScheme, style: dockThemeStyle) }

    var body: some View {
        HStack(spacing: 8) {
            Button { store.decrement() } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.labelSubtitle.color)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            VStack(spacing: 1) {
                Text(verbatim: "\(store.count)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.labelActive.color)
                Text(verbatim: store.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.labelSubtitle.color)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button { store.increment() } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contextMenu {
            Button("Reset") { store.reset() }
        }
    }
}

/// E4: Warm yellow Sydedock sticky-note card stored under `com.katikati.edge.stickyNoteText`.
struct DeckStickyNoteCardView: View {
    @AppStorage("com.katikati.edge.stickyNoteText") private var noteText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "note.text")
                    .font(.system(size: 10, weight: .bold))
                Text("Quick Notes")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.black.opacity(0.62))

            TextEditor(text: $noteText)
                .scrollContentBackground(.hidden)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.86))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 1.0, green: 0.93, blue: 0.56))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.black.opacity(0.10), lineWidth: 0.5)
        )
    }
}

/// E4: Canvas analog clock updated once per minute (zero idle CPU).
struct DeckAnalogClockCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dockThemeStyle) private var dockThemeStyle

    private var theme: DockThemeTokens { .resolved(for: colorScheme, style: dockThemeStyle) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 8) {
                Canvas { graphics, size in
                    let side = min(size.width, size.height)
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let radius = max(8, side / 2 - 2)
                    let ringRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                    graphics.stroke(Path(ellipseIn: ringRect), with: .color(theme.labelSubtitle.color.opacity(0.35)), lineWidth: 1.2)

                    let cal = Calendar.current
                    let hour = cal.component(.hour, from: context.date) % 12
                    let minute = cal.component(.minute, from: context.date)
                    let hourAngle = Angle.degrees((Double(hour) + Double(minute) / 60.0) * 30.0 - 90.0)
                    let minuteAngle = Angle.degrees(Double(minute) * 6.0 - 90.0)

                    func hand(_ angle: Angle, length: CGFloat, width: CGFloat, color: Color) {
                        let rad = CGFloat(angle.radians)
                        let end = CGPoint(x: center.x + cos(rad) * radius * length, y: center.y + sin(rad) * radius * length)
                        var path = Path()
                        path.move(to: center)
                        path.addLine(to: end)
                        graphics.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
                    }

                    hand(hourAngle, length: 0.52, width: 2.0, color: theme.labelActive.color)
                    hand(minuteAngle, length: 0.78, width: 1.4, color: theme.labelActive.color.opacity(0.85))
                    graphics.fill(
                        Path(ellipseIn: CGRect(x: center.x - 1.8, y: center.y - 1.8, width: 3.6, height: 3.6)),
                        with: .color(Color.accentColor)
                    )
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: context.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(theme.labelActive.color)
                    Text("Clock")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.labelSubtitle.color)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }
}

/// E5: Translucent screen-edge reveal lip shown when the auto-hidden Edge Bar is tucked away.
struct EdgeRevealLipView: View {
    let side: EdgeSide
    let isHovered: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(isHovered ? 0.35 : 0.18), lineWidth: 0.75)
            )
            .frame(width: isHovered ? 8 : 5, height: isHovered ? 64 : 44)
            .padding(side == .right ? .trailing : .leading, 2)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.78), value: isHovered)
    }
}
