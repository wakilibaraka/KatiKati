import SwiftUI

// Phase 33e — Page 4: Productivity & Calendar (Bento Card A: Obsidian/Scarlet Calendar, Card B: Focus Hourglass & Decision Spinner)

struct NotchProductivityPageView: View {
    @ObservedObject private var focus = ProductivityServices.shared.focus
    @State private var decisionResult: String = "Ready"
    @State private var spinDegrees: Double = 0.0

    private let decisions = ["Ship It 🚀", "Take a Break ☕", "Refactor 🧹", "Write Tests 🧪", "Deep Focus 🧘"]

    var body: some View {
        HStack(spacing: NotchDesignSpec.cardSpacing) {
            calendarCard
            focusCard
        }
    }

    // MARK: - Card A: Obsidian / Scarlet Calendar Card
    @ViewBuilder
    private var calendarCard: some View {
        let calendar = Calendar.current
        let today = Date()
        let dayNumber = calendar.component(.day, from: today)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.90, green: 0.20, blue: 0.25))
                        .frame(width: 22, height: 22)
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text(verbatim: today.formatted(.dateTime.month(.wide).year()).uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text(verbatim: "TODAY")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Color(red: 0.90, green: 0.20, blue: 0.25))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(red: 0.90, green: 0.20, blue: 0.25).opacity(0.15)))
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "\(dayNumber)")
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.95, green: 0.25, blue: 0.30))

                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: today.formatted(.dateTime.weekday(.wide)))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Text(verbatim: "No conflicts today")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            Spacer(minLength: 0)

            // Mini week row dots
            HStack(spacing: 8) {
                ForEach(1...7, id: \.self) { day in
                    let isToday = (day == calendar.component(.weekday, from: today))
                    Circle()
                        .fill(isToday ? Color(red: 0.95, green: 0.25, blue: 0.30) : Color.white.opacity(0.15))
                        .frame(width: isToday ? 8 : 6, height: isToday ? 8 : 6)
                }
            }
        }
        .padding(NotchDesignSpec.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                .fill(Color(red: 0.08, green: 0.06, blue: 0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                        .stroke(Color(red: 0.95, green: 0.25, blue: 0.30).opacity(0.25), lineWidth: NotchDesignSpec.cardStrokeWidth)
                )
        )
    }

    // MARK: - Card B: Neon Focus Hourglass & Decision Spinner
    @ViewBuilder
    private var focusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZStack {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 22, height: 22)
                    Image(systemName: "hourglass")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text(verbatim: "Focus & Decision")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        spinDegrees += 720 + Double.random(in: 45...315)
                        decisionResult = decisions.randomElement() ?? "Ship It 🚀"
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10, weight: .bold))
                            .rotationEffect(.degrees(spinDegrees))
                        Text(verbatim: "SPIN")
                            .font(.system(size: 9, weight: .heavy))
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                }
                .buttonStyle(.plain)
            }

            // Decision Roulette banner
            HStack {
                Text(verbatim: "Decision:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Text(verbatim: decisionResult)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))

            Spacer(minLength: 0)

            // Focus Timer controls
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: String(format: "%d min", focus.model.remaining / 60))
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text(verbatim: focus.model.isRunning ? "In Session" : "Paused")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                Button {
                    focus.toggle()
                } label: {
                    Image(systemName: focus.model.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.orange))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(NotchDesignSpec.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(NotchDesignSpec.cardFillOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(NotchDesignSpec.cardStrokeOpacity), lineWidth: NotchDesignSpec.cardStrokeWidth)
                )
        )
    }
}
