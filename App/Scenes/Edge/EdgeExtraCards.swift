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

private struct EdgeBezelCardChrome: ViewModifier {
    let width: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(width: width)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                    )
            )
    }
}

/// E3: Compact vertical bezel counter card (`count` + `-`/`+` controls), sized to fit the narrow Edge Bar column.
struct DeckCounterCardView: View {
    let width: CGFloat
    @ObservedObject private var store = EdgeCounterStore.shared

    var body: some View {
        VStack(spacing: 4) {
            Text(verbatim: "\(store.count)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            HStack(spacing: 8) {
                Button { store.decrement() } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.68))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Counter"))

                Button { store.increment() } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Counter"))
            }
        }
        .padding(.vertical, 6)
        .modifier(EdgeBezelCardChrome(width: width))
        .contextMenu {
            Button("Reset") { store.reset() }
        }
    }
}

/// E4: Compact yellow Sydedock sticky-note preview tile stored under `com.katikati.edge.stickyNoteText`.
/// Tapping opens `StickyNoteFlyoutView` (`takesKey: true`) so typing works reliably outside the non-activating rail.
struct DeckStickyNoteCardView: View {
    let width: CGFloat
    @AppStorage("com.katikati.edge.stickyNoteText") private var noteText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: "note.text")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.58))

            Text(verbatim: noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "…" : noteText)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.84))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .frame(width: width, height: max(54, width * 0.96), alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 1.0, green: 0.93, blue: 0.56))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.black.opacity(0.14), lineWidth: 0.5)
        )
    }
}

/// E4: Key-capable editor flyout opened when tapping `DeckStickyNoteCardView`.
struct StickyNoteFlyoutView: View {
    @AppStorage("com.katikati.edge.stickyNoteText") private var noteText = ""

    static let size = CGSize(width: 240, height: 200)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "note.text")
                    .font(.system(size: 12, weight: .bold))
                Text("Sticky Note")
                    .font(.headline)
                Spacer()
                if !noteText.isEmpty {
                    Button {
                        noteText = ""
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(Text("Reset"))
                }
            }
            .foregroundStyle(Color.black.opacity(0.72))

            TextEditor(text: $noteText)
                .scrollContentBackground(.hidden)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.black.opacity(0.88))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(red: 1.0, green: 0.94, blue: 0.62))
    }
}

/// E4: Bezel-sized analog clock updated once per minute (zero idle CPU).
struct DeckAnalogClockCardView: View {
    let width: CGFloat

    var body: some View {
        let dialSize = max(26, min(36, width - 14))
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(spacing: 3) {
                Canvas { graphics, size in
                    let side = min(size.width, size.height)
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let radius = max(8, side / 2 - 1.5)
                    let ringRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                    graphics.stroke(Path(ellipseIn: ringRect), with: .color(.white.opacity(0.28)), lineWidth: 1.1)

                    let cal = Calendar.current
                    let hour = cal.component(.hour, from: context.date) % 12
                    let minute = cal.component(.minute, from: context.date)
                    let hourAngle = Angle.degrees((Double(hour) + Double(minute) / 60.0) * 30.0 - 90.0)
                    let minuteAngle = Angle.degrees(Double(minute) * 6.0 - 90.0)

                    func hand(_ angle: Angle, length: CGFloat, lineWidth: CGFloat, color: Color) {
                        let rad = CGFloat(angle.radians)
                        let end = CGPoint(x: center.x + cos(rad) * radius * length, y: center.y + sin(rad) * radius * length)
                        var path = Path()
                        path.move(to: center)
                        path.addLine(to: end)
                        graphics.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    }

                    hand(hourAngle, length: 0.52, lineWidth: 1.8, color: .white)
                    hand(minuteAngle, length: 0.78, lineWidth: 1.3, color: .white.opacity(0.85))
                    graphics.fill(
                        Path(ellipseIn: CGRect(x: center.x - 1.6, y: center.y - 1.6, width: 3.2, height: 3.2)),
                        with: .color(.accentColor)
                    )
                }
                .frame(width: dialSize, height: dialSize)

                Text(verbatim: context.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
            .padding(.vertical, 5)
            .modifier(EdgeBezelCardChrome(width: width))
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
