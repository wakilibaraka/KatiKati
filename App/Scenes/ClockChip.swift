import SwiftUI


// MARK: - Art tokens (Phase 4U decision 8d)

/// The combined clock chip's own palette: a weather-pill twin, not a colour twin — same
/// rounded gradient-card construction at the bar's right end, its own hues so the pair
/// (weather left / clock right) reads as matched siblings rather duplicates.
///
/// Hues picked at build time (2026-10-09), to be signed off on the render:
/// - **Day (warm):** amber → coral, echoing the sun spot on the weather card.
/// - **Night (indigo):** deeper indigo → violet, deliberately one step darker than the
///   weather night family so the two night pills stay distinguishable.
public enum ClockArt {
    /// (leading, trailing) gradient stops for the clock card.
    public static func stops(isNight: Bool) -> (Color, Color) {
        if isNight {
            return (Color(red: 62/255, green: 72/255, blue: 198/255),
                    Color(red: 124/255, green: 98/255, blue: 220/255))
        }
        return (Color(red: 247/255, green: 148/255, blue: 62/255),
                Color(red: 238/255, green: 97/255, blue: 84/255))
    }

    public static func gradient(isNight: Bool) -> LinearGradient {
        let (a, b) = stops(isNight: isNight)
        return LinearGradient(colors: [a, b], startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - Bar widget (combined clock chip)

public struct ClockChip: View {
    @AppStorage("com.katikati.clock.preset") private var preset: ClockPreset = .modernMac
    private let provider: ClockDataProvider

    public init(provider: ClockDataProvider = StandardClockProvider()) {
        self.provider = provider
    }

    @State private var showingCalendar = false

    public var body: some View {
        // 4e: minute-aligned. The timeline starts on the next whole-minute boundary and ticks
        // every 60s from there, so the main thread wakes once a minute and the chip can never
        // show a reading that is up to 59s stale. A per-second `Timer.publish` used to run here
        // even though the provider's content is minute-resolution.
        TimelineView(.periodic(from: ClockTick.nextMinute(after: Date()), by: 60)) { context in
            card(for: context.date)
        }
        .onTapGesture {
            showingCalendar.toggle()
        }
        .popover(isPresented: $showingCalendar, arrowEdge: .top) {
            CalendarPopupView()
        }
    }

    /// 8d locked spec: the weather-pill twin. Identical construction to `WeatherChip`
    /// (8/4 padding, radius-10 continuous gradient card, white 0.18 rim, tap → popup),
    /// own hue from `ClockArt` split by `ClockChipDaylight`, content = large time + a
    /// smaller weekday/date line. Both presets live here — they change the typography,
    /// never the form.
    private func card(for date: Date) -> some View {
        let content = provider.currentContent(for: date)
        let art = ClockArt.gradient(isNight: ClockChipDaylight.isNight(date))

        // ViewThatFits is macOS 13+; the floor is 12, so the fallback there is the full
        // layout truncating (same rule as the weather pill).
        return Group {
            if #available(macOS 13.0, *) {
                ViewThatFits(in: .horizontal) {
                    fullCard(content: content)
                    compactCard(content: content)
                }
            } else {
                fullCard(content: content)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(art))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    /// Large time leading, the smaller weekday/date line trailing — horizontal so the card
    /// clears the slot's fixed 36pt height (a stacked pair cannot: 19pt time + 10pt date +
    /// padding overshoots and would clip).
    private func fullCard(content: ClockContent) -> some View {
        HStack(spacing: 8) {
            Text(content.primaryText)
                .font(timeFont)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 4)

            if let secondary = content.secondaryText {
                Text(secondary)
                    .font(dateFont)
                    .opacity(preset == .modernMac ? 0.85 : 0.9)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .foregroundStyle(.white)
    }

    /// Narrow widget widths (the Settings slider goes down to 60pt): keep the load-bearing
    /// element instead of crushing the pair.
    private func compactCard(content: ClockContent) -> some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            Text(content.primaryText)
                .font(preset == .modernMac
                      ? .system(size: 15, weight: .semibold, design: .rounded)
                      : .system(size: 15, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }

    /// Preset identity survives the restyle as typography: `modern` stays SF Rounded,
    /// `pixel` stays monospaced and shouts its date line — both inside the one new form.
    private var timeFont: Font {
        switch preset {
        case .modernMac:
            return .system(size: 19, weight: .semibold, design: .rounded)
        case .pixelRetro:
            return .system(size: 18, weight: .bold, design: .monospaced)
        }
    }

    private var dateFont: Font {
        switch preset {
        case .modernMac:
            return .system(size: 10, weight: .regular, design: .rounded)
        case .pixelRetro:
            return .system(size: 10, weight: .medium, design: .monospaced)
        }
    }
}

// MARK: - Calendar popup (baseline — the owner redesigns it in Phase 5)

struct CalendarPopupView: View {
    @State private var currentDate = Date()
    private let calendar = Calendar.current

    var body: some View {
        // 4e gap fixed: the month grid was never composed into the body — the popup rendered an
        // empty box while `header`/`daysOfWeek`/`monthGrid` sat unused. Baseline only; the owner
        // redesigns this popup in Phase 5.
        VStack(spacing: 12) {
            header
            daysOfWeek
            monthGrid
        }
        .padding(16)
        .frame(width: 280)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 8)
    }

    private var header: some View {
        HStack {
            Text(currentDate.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            Spacer()
            HStack(spacing: 8) {
                Button(action: {
                    if let newDate = calendar.date(byAdding: .month, value: -1, to: currentDate) {
                        currentDate = newDate
                    }
                }) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Button(action: {
                    if let newDate = calendar.date(byAdding: .month, value: 1, to: currentDate) {
                        currentDate = newDate
                    }
                }) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var daysOfWeek: some View {
        let symbols = calendar.veryShortWeekdaySymbols
        return HStack {
            ForEach(symbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        let days = extractDays(for: currentDate)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(days, id: \.self) { date in
                if let date = date {
                    DayCell(date: date, isToday: calendar.isDateInToday(date))
                } else {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }

    private func extractDays(for month: Date) -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let monthFirstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let monthLastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end - 1)
        else {
            return []
        }

        let startDate = monthFirstWeek.start
        let endDate = monthLastWeek.end

        var days: [Date?] = []
        var currentDate = startDate

        while currentDate < endDate {
            if calendar.isDate(currentDate, equalTo: month, toGranularity: .month) {
                days.append(currentDate)
            } else {
                days.append(nil)
            }
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        return days
    }
}

private struct DayCell: View {
    let date: Date
    let isToday: Bool

    var body: some View {
        // 4d: a bare day-of-month is a number, not translatable copy — verbatim so the
        // localization gate stops treating the interpolation as a missing key.
        Text(verbatim: "\(Calendar.current.component(.day, from: date))")
            .font(.system(size: 14))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(isToday ? Color.blue : Color.clear)
            .foregroundColor(isToday ? .white : .primary)
            .clipShape(Circle())
    }
}


public struct FlipClockChip: View {
    @State private var currentTime = Date()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init() {}

    public var body: some View {
        HStack(spacing: 6) {
            let components = Calendar.current.dateComponents([.hour, .minute], from: currentTime)
            let hourStr = String(format: "%02d", components.hour ?? 0)
            let minuteStr = String(format: "%02d", components.minute ?? 0)

            flipTile(text: hourStr)
            
            VStack(spacing: 8) {
                Circle().fill(Color.white.opacity(0.8)).frame(width: 4, height: 4)
                Circle().fill(Color.white.opacity(0.8)).frame(width: 4, height: 4)
            }
            
            flipTile(text: minuteStr)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .onReceive(timer) { input in
            currentTime = input
        }
    }

    private func flipTile(text: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(white: 0.18))
                .frame(width: 32, height: 32)
            
            Text(text)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            
            // Horizontal split line
            Rectangle()
                .fill(Color.black.opacity(0.4))
                .frame(height: 1)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.black.opacity(0.2), lineWidth: 1)
        )
    }
}
