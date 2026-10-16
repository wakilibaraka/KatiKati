import Combine
import SwiftUI

// Phase 33e — Page 3: Retro Time & LED Ticker (Bento Card A: Split-Flap Orange Flip Clock, Card B: Recessed LED Dot Matrix)
//
// Phase 48b — Card B stopped repeating the local time Card A already flips and became the page's world
// clocks: the local time keeps the LED line (with its zone), and the card's body is the user's stored
// clocks from `ProductivityServices.worldClocks` — the same store the floating panel and the widget tiles
// edit, so adding a city in either place is visible in both. Rows are removed from their own context
// menu and added from the shared `TimeZonePicker`; both are the panel's existing affordances, not new
// ones.

struct NotchRetroClockPageView: View {
    @State private var currentTime = Date()
    @ObservedObject private var clocks = ProductivityServices.shared.worldClocks
    @State private var picking = false
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

            // Card B: Recessed LED Time + the world clocks the owner picked
            VStack(alignment: .leading, spacing: NotchWorldClockLayout.rowSpacing) {
                HStack(spacing: 4) {
                    Circle().fill(Color.white).frame(width: 5, height: 5)
                    Text(verbatim: String(format: "%02d:%02d:%02d", hour, minute, second))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: .white.opacity(0.5), radius: 4, x: 0, y: 0)
                    Spacer(minLength: 0)
                    Text(verbatim: TimeZone.current.abbreviation() ?? "UTC")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                    // Only under the cap: at four cities the store refuses a fifth, so the button would
                    // be a lie. Remove one from a row's menu and it comes back.
                    if clocks.identifiers.count < WorldClockModel.maxClocks {
                        Button { picking.toggle() } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 9, weight: .bold))
                                .frame(width: 16, height: 12)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.6))
                        .help(Text("Add City"))
                        .popover(isPresented: $picking) { TimeZonePicker(store: clocks, done: { picking = false }) }
                    }
                }
                .frame(height: NotchWorldClockLayout.header)

                ForEach(clocks.identifiers, id: \.self) { identifier in
                    if let reading = WorldClockModel.reading(for: identifier, at: currentTime) {
                        HStack(spacing: 5) {
                            Image(systemName: reading.isNight ? "moon.stars.fill" : "sun.max.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(reading.isNight ? Color.indigo : Color.orange)
                            Text(verbatim: reading.city)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(1)
                            if reading.dayDelta != 0 {
                                Text(reading.dayDelta > 0 ? "Tomorrow" : "Yesterday")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                            Spacer(minLength: 0)
                            Text(verbatim: reading.offsetLabel)
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))
                            Text(verbatim: reading.time)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                        }
                        .frame(height: NotchWorldClockLayout.row)
                        .contentShape(Rectangle())
                        .contextMenu { Button("Remove") { clocks.remove(identifier) } }
                    }
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
