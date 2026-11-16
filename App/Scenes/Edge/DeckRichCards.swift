import SwiftUI
import AppKit

// MARK: - Rich Card Extension

extension DeckButton {
    var isRichCard: Bool {
        switch self {
        case .focus, .clock, .batteryWifi, .habits, .hydration, .food, .notesPreview:
            return true
        default:
            return false
        }
    }

    func cardHeight(unit: CGFloat) -> CGFloat {
        switch self {
        case .focus: return max(56, unit * 2.3)
        case .clock: return max(38, unit * 1.5)
        case .batteryWifi: return max(24, unit * 0.95)
        case .habits: return max(40, unit * 1.6)
        case .hydration: return max(48, unit * 1.85)
        case .food: return max(46, unit * 1.8)
        case .notesPreview: return max(54, unit * 2.2)
        default: return unit
        }
    }
}

// MARK: - Unified Card View

struct DeckRichCardView: View {
    let button: DeckButton
    let width: CGFloat
    var onRight: Bool = true
    var barStyle: EdgeBarStyle = .bezelDock

    var body: some View {
        Group {
            switch button {
            case .focus:
                DeckFocusCardView(width: width, onRight: onRight)
            case .clock:
                DeckClockCardView(width: width, onRight: onRight)
            case .batteryWifi:
                DeckBatteryWifiCardView(width: width, onRight: onRight)
            case .habits:
                DeckHabitsCardView(width: width, onRight: onRight)
            case .hydration:
                DeckHydrationCardView(width: width, onRight: onRight)
            case .food:
                DeckFoodCardView(width: width, onRight: onRight)
            case .notesPreview:
                DeckNotesPreviewCardView(width: width, onRight: onRight)
            default:
                EmptyView()
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - 1. Focus & Task Timer Card

struct DeckFocusCardView: View {
    let width: CGFloat
    var onRight: Bool = true

    @ObservedObject private var tasks = ProductivityServices.shared.tasks
    @ObservedObject private var focus = ProductivityServices.shared.focus

    private var activeTaskTitle: String {
        tasks.list.items.first(where: { !$0.done })?.text ?? "Deep focus"
    }

    private var formattedTime: String {
        let remaining = focus.model.remaining
        let mins = remaining / 60
        let secs = remaining % 60
        return String(format: "%02d : %02d", mins, secs)
    }

    var body: some View {
        VStack(spacing: 3) {
            // Glowing rounded neon squircle with bolt
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.85))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color(red: 0.2, green: 0.55, blue: 1.0), Color(red: 0.1, green: 0.4, blue: 0.9)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 2.5
                    )
                    .shadow(color: Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.65), radius: 4)

                Image(systemName: "bolt")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: max(28, width * 0.72), height: max(28, width * 0.72))
            .padding(.top, 4)

            // Timer display
            Text(verbatim: formattedTime)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white.opacity(0.12)))

            // Active task title subtext
            Text(verbatim: activeTaskTitle)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.65))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 2)
                .padding(.bottom, 3)
        }
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

// MARK: - 2. Clock & Date Card

struct DeckClockCardView: View {
    let width: CGFloat
    var onRight: Bool = true

    @State private var now = Date()
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "h:mm"
        return df
    }()

    private static let ampmFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "a"
        return df
    }()

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "EEE, MMM d"
        return df
    }()

    var body: some View {
        VStack(spacing: 1.5) {
            HStack(alignment: .firstTextBaseline, spacing: 1.5) {
                Text(verbatim: Self.timeFormatter.string(from: now))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Text(verbatim: Self.ampmFormatter.string(from: now).uppercased())
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.65))
            }

            Text(verbatim: Self.dateFormatter.string(from: now))
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(Color.white.opacity(0.6))
                .lineLimit(1)
        }
        .padding(.vertical, 5)
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                )
        )
        .onReceive(timer) { now = $0 }
    }
}

// MARK: - 3. Battery & Wi-Fi Combo Capsule

struct DeckBatteryWifiCardView: View {
    let width: CGFloat
    var onRight: Bool = true

    @StateObject private var service = SystemStatusService()

    private var batteryLevel: Double {
        Double(service.status.battery.level ?? 82) / 100.0
    }

    private var isCharging: Bool {
        service.status.battery.isCharging
    }

    private var isWifiConnected: Bool {
        service.status.wifi.isConnected
    }

    var body: some View {
        HStack(spacing: 3) {
            // Arc progress + percentage
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: CGFloat(batteryLevel))
                    .stroke(
                        isCharging ? Color.cyan : Color.white,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 14, height: 14)

            Text(verbatim: "\(Int(batteryLevel * 100))%")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            Spacer(minLength: 0)

            // Wi-Fi glyph
            Image(systemName: "wifi")
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(isWifiConnected ? .white : Color.white.opacity(0.4))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(width: width)
        .background(
            Capsule(style: .continuous)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.14).opacity(0.92))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
                )
        )
        .onAppear { service.acquire() }
        .onDisappear { service.release() }
    }
}

// MARK: - 4. Habits 6-Week Dot Matrix Card

struct DeckHabitsCardView: View {
    let width: CGFloat
    var onRight: Bool = true

    @ObservedObject private var habits = HabitStreakStore.shared

    var body: some View {
        let matrix = habits.matrix42Days()
        // 7 columns × 6 rows = 42 dots
        let columns = Array(repeating: GridItem(.fixed(3.5), spacing: 2), count: 7)

        VStack(spacing: 2) {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<min(42, matrix.count), id: \.self) { idx in
                    let dot = matrix[idx]
                    Circle()
                        .fill(dotColor(level: dot.level, isToday: dot.isToday))
                        .frame(width: 3.5, height: 3.5)
                        .overlay(
                            dot.isToday ? Circle().strokeBorder(Color.white, lineWidth: 0.5) : nil
                        )
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 5)
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

    private func dotColor(level: Int, isToday: Bool) -> Color {
        switch level {
        case 0: return Color.white.opacity(0.12)
        case 1: return Color(red: 0.2, green: 0.45, blue: 0.9).opacity(0.55)
        case 2: return Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.85)
        default: return Color.white
        }
    }
}

// MARK: - 5. Hydration Fluid Wave Card

struct DeckHydrationCardView: View {
    let width: CGFloat
    var onRight: Bool = true

    @ObservedObject private var hydro = HydrationController.shared

    var body: some View {
        VStack(spacing: 2) {
            Text(verbatim: hydro.formattedRemainingTime)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(hydro.isOverdue ? Color(red: 1.0, green: 0.4, blue: 0.3) : .white)
                .padding(.top, 3)

            // Sloshing wave graphic
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.5))

                HydrationWaveShape(phase: hydro.wavePhase, progress: hydro.intervalProgress)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.1, green: 0.5, blue: 1.0), Color(red: 0.0, green: 0.75, blue: 1.0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .frame(width: max(24, width * 0.78), height: 18)
            .padding(.bottom, 3)
        }
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            hydro.isOverdue ? Color(red: 1.0, green: 0.4, blue: 0.3).opacity(0.8) : Color.white.opacity(0.14),
                            lineWidth: 0.5
                        )
                )
        )
    }
}

struct HydrationWaveShape: Shape {
    var phase: Double
    var progress: Double

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let fillHeight = max(2, rect.height * CGFloat(progress))
        let baseY = rect.maxY - fillHeight
        let waveAmp: CGFloat = 2.0

        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: baseY))

        let step: CGFloat = 3.0
        for x in stride(from: rect.minX, through: rect.maxX, by: step) {
            let relX = (x - rect.minX) / rect.width
            let y = baseY + sin(relX * .pi * 2 + CGFloat(phase)) * waveAmp
            p.addLine(to: CGPoint(x: x, y: y))
        }

        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - 6. Food, Fasting & Cadence Card

struct DeckFoodCardView: View {
    let width: CGFloat
    var onRight: Bool = true

    @ObservedObject private var nutri = NutritionController.shared

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "fork.knife")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color(red: 1.0, green: 0.65, blue: 0.2))
                .padding(.top, 3)

            if nutri.isFasting {
                Text(verbatim: nutri.formattedFastTime)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text("Fasting")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.6))
                    .padding(.bottom, 2)
            } else {
                Text(verbatim: nutri.formattedNextMealTime)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text(verbatim: "\(nutri.todayCalories) kcal")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.6))
                    .padding(.bottom, 2)
            }
        }
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

// MARK: - 7. Notes Preview Card

struct DeckNotesPreviewCardView: View {
    let width: CGFloat
    var onRight: Bool = true

    @ObservedObject private var tasks = ProductivityServices.shared.tasks

    private var previewItems: [String] {
        let titles = tasks.list.items.filter { !$0.done }.prefix(3).map(\.text)
        if titles.isEmpty {
            return ["Ship update", "Call back", "Notes memo"]
        }
        return Array(titles)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Notes")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.7))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.white.opacity(0.1)))
                .padding(.top, 3)
                .padding(.horizontal, 3)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(previewItems.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 2.5) {
                        Circle()
                            .stroke(Color.white.opacity(0.4), lineWidth: 0.8)
                            .frame(width: 4, height: 4)
                        Text(verbatim: item)
                            .font(.system(size: 7, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 3)
        }
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
