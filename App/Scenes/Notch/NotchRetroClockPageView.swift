import Combine
import SwiftUI

// Phase 33e — Page 3: Retro Time & LED Ticker (Bento Card A: Split-Flap Orange Flip Clock, Card B: Recessed LED Dot Matrix)

struct NotchRetroClockPageView: View {
    @State private var currentTime = Date()
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: currentTime)
        let minute = calendar.component(.minute, from: currentTime)
        let second = calendar.component(.second, from: currentTime)
        let displayHour12 = hour % 12 == 0 ? 12 : hour % 12
        let amPm = hour >= 12 ? "PM" : "AM"

        HStack(spacing: NotchDesignSpec.cardSpacing) {
            // Card A: Orange Split-Flap Clock
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(verbatim: "SOLARI FLIP CLOCK")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.15))
                    Spacer()
                    Text(verbatim: amPm)
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.15)))
                }

                HStack(spacing: 8) {
                    flipTile(value: String(format: "%02d", displayHour12))
                    Text(verbatim: ":")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.15))
                    flipTile(value: String(format: "%02d", minute))
                }
                .frame(maxWidth: .infinity, alignment: .center)

                Spacer(minLength: 0)

                Text(verbatim: "Split-Flap Electro-Mechanical")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
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

            // Card B: Recessed White LED Dot-Matrix Ticker
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 4) {
                        Circle().fill(Color.white).frame(width: 5, height: 5)
                        Text(verbatim: "LED MATRIX")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    Spacer()
                    Text(verbatim: TimeZone.current.abbreviation() ?? "UTC")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                }

                // LED dot-matrix readout
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: String(format: "%02d:%02d:%02d", hour, minute, second))
                        .font(.system(size: 28, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                        .shadow(color: .white.opacity(0.6), radius: 6, x: 0, y: 0)

                    Text(verbatim: currentTime.formatted(date: .complete, time: .omitted).uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer(minLength: 0)

                // Dot ticker status bar
                HStack(spacing: 8) {
                    Image(systemName: "circle.grid.3x3.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(verbatim: "PRECISION TIME PROTOCOL")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(NotchDesignSpec.cardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                    .fill(Color(red: 0.04, green: 0.04, blue: 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(NotchDesignSpec.cardStrokeOpacity), lineWidth: NotchDesignSpec.cardStrokeWidth)
                    )
            )
        }
        .onReceive(timer) { currentTime = $0 }
    }

    private func flipTile(value: String) -> some View {
        ZStack {
            // Flap body
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.88, green: 0.40, blue: 0.08))
                .frame(width: 58, height: 60)
                .overlay(
                    // Split seam
                    Rectangle()
                        .fill(Color.black.opacity(0.5))
                        .frame(height: 1.5)
                )

            Text(verbatim: value)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
    }
}
