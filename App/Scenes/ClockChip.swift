import AppKit
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

    /// 10c-2: four-step axis. Day / night reuse the frozen 8d stops above.
    public static func stops(phase: ClockArtPhase) -> (Color, Color) {
        switch phase {
        case .night: return stops(isNight: true)
        case .day: return stops(isNight: false)
        case .dawn:
            return (Color(red: 236/255, green: 112/255, blue: 156/255),
                    Color(red: 250/255, green: 176/255, blue: 82/255))
        case .dusk:
            return (Color(red: 238/255, green: 97/255, blue: 84/255),
                    Color(red: 142/255, green: 88/255, blue: 206/255))
        }
    }

    public static func gradient(phase: ClockArtPhase) -> LinearGradient {
        let (a, b) = stops(phase: phase)
        return LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Bar widget (combined clock chip)

public struct ClockChip: View {
    @AppStorage("com.katikati.clock.preset") private var preset: ClockPreset = .stackedCard
    @AppStorage(CalendarDockAction.singleClickKey) private var singleClickAction: CalendarDockAction = .togglePanel
    @AppStorage(CalendarDockAction.doubleClickKey) private var doubleClickAction: CalendarDockAction = .openCalendarApp
    @Environment(\.widgetSize) private var widgetSize
    @EnvironmentObject private var weatherService: WeatherService
    private let provider: ClockDataProvider

    public init(provider: ClockDataProvider = StandardClockProvider()) {
        self.provider = provider
    }

    public var body: some View {
        baseBody
            .dockHoverPreview { ClockCalendarPreviewCard() }
    }

    @ViewBuilder
    private var baseBody: some View {
        // Flip tiles are their own form (owner's hand-built variant kept as a
        // third preset): they bypass the 8d gradient card entirely.
        if preset == .flipTiles && widgetSize != .small {
            FlipClockChip()
                .simultaneousGesture(TapGesture(count: 2).onEnded { performAction(doubleClickAction) })
                .onTapGesture { performAction(singleClickAction) }
        } else if preset == .minimal {
            TimelineView(.periodic(from: ClockTick.nextMinute(after: Date()), by: 60)) { context in
                MinimalClockCard(content: provider.currentContent(for: context.date), widgetSize: widgetSize)
            }
            .simultaneousGesture(TapGesture(count: 2).onEnded { performAction(doubleClickAction) })
            .onTapGesture { performAction(singleClickAction) }
        } else if preset == .stackedCard {
            TimelineView(.periodic(from: widgetSize == .large ? Date() : ClockTick.nextMinute(after: Date()), by: widgetSize == .large ? 1 : 60)) { context in
                StackedClockCardView(content: provider.currentContent(for: context.date), widgetSize: widgetSize, date: context.date)
            }
            .simultaneousGesture(TapGesture(count: 2).onEnded { performAction(doubleClickAction) })
            .onTapGesture { performAction(singleClickAction) }
        } else {
            // 4e: minute-aligned.
            TimelineView(.periodic(from: ClockTick.nextMinute(after: Date()), by: 60)) { context in
                card(for: context.date)
            }
            .simultaneousGesture(TapGesture(count: 2).onEnded { performAction(doubleClickAction) })
            .onTapGesture { performAction(singleClickAction) }
        }
    }

    private func performAction(_ action: CalendarDockAction) {
        switch action {
        case .togglePanel:
            WidgetPanelController.calendar.toggle()
        case .openCalendarApp:
            if let url = AgendaEventAction.calendarURL(for: Date()) {
                NSWorkspace.shared.open(url)
            } else if let calURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
                NSWorkspace.shared.openApplication(at: calURL, configuration: .init())
            }
        case .createEvent:
            WidgetPanelController.calendar.toggle()
        case .none:
            break
        }
    }

    /// 8d locked spec: the weather-pill twin. Identical construction to `WeatherChip`
    /// (8/4 padding, radius-10 continuous gradient card, white 0.18 rim, tap → popup),
    /// own hue from `ClockArt` split by `ClockChipDaylight`, content = large time + a
    /// smaller weekday/date line. Both presets live here — they change the typography,
    /// never the form.
    private func card(for date: Date) -> some View {
        let content = provider.currentContent(for: date)
        let art = ClockArt.gradient(phase: ClockArtPhase.phase(date, sunTimes: weatherService.currentState.sunTimes(on: date)))

        return Group {
            if widgetSize == .small {
                compactCard(content: content)
            } else {
                ViewThatFits(in: .horizontal) {
                    fullCard(content: content)
                    compactCard(content: content)
                }
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
    /// `flipTiles` never reaches here (it bypasses the card in `body`).
    private var timeFont: Font {
        switch preset {
        case .modernMac, .stackedCard, .minimal:
            return .system(size: widgetSize == .large ? 22 : 19, weight: .semibold, design: .rounded).monospacedDigit()
        case .pixelRetro:
            return .system(size: 18, weight: .bold, design: .monospaced)
        case .flipTiles:
            return .system(size: 19, weight: .semibold, design: .rounded)
        }
    }

    private var dateFont: Font {
        switch preset {
        case .modernMac, .stackedCard, .minimal:
            return .system(size: 10, weight: .regular, design: .rounded)
        case .pixelRetro:
            return .system(size: 10, weight: .medium, design: .monospaced)
        case .flipTiles:
            return .system(size: 10, weight: .regular, design: .rounded)
        }
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

// MARK: - Rail tile (Phase 18c)

/// The time on a side rail: hours over minutes, in the same 40 × 40 chrome as the app chips and FABs
/// beside it (Phase 40b/40f — it used to be 44 × 56 on a 10 pt-radius phase gradient). Same minute-aligned
/// timeline as the pill — no per-second work.
struct RailClockTile: View {
    @EnvironmentObject private var weatherService: WeatherService
    @ObservedObject private var calendarService = ProductivityServices.shared.calendar
    @ObservedObject private var alarmStore = ProductivityServices.shared.alarms
    @State private var isHovered = false

    var body: some View {
        TimelineView(.periodic(from: ClockTick.nextMinute(after: Date()), by: 60)) { context in
            let parts = Self.hourMinute(context.date)
            let eventColor = upcomingDotColor(now: context.date)
            VStack(spacing: -1) {
                Text(verbatim: parts.hour)
                Text(verbatim: parts.minute)
            }
            // Phase 40g refinement: 14pt with -1pt spacing gives clean top/bottom breathing room inside 40×40.
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: BarSection.railTileSize, height: BarSection.railTileSize)
            .overlay(alignment: .topTrailing) {
                if let eventColor {
                    Circle().fill(eventColor).frame(width: 5, height: 5).padding(4.5)
                }
            }
            .dockTileChrome(isHovered: isHovered)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { WidgetPanelController.calendar.toggle() }
        .dockHoverPreview { ClockCalendarPreviewCard() }
    }

    private func upcomingDotColor(now: Date) -> Color? {
        if let upcoming = calendarService.upcoming.first {
            let rgb = upcoming.colorRGB
            return rgb.count >= 3 ? Color(red: rgb[0], green: rgb[1], blue: rgb[2]) : .accentColor
        }
        if AlarmList.next(in: alarmStore.alarms, after: now) != nil {
            return Color(red: 1.0, green: 0.82, blue: 0.25)
        }
        return nil
    }

    /// Two-digit hour in the user's 12/24-hour preference and two-digit minute.
    static func hourMinute(_ date: Date, locale: Locale = .current, calendar: Calendar = .current) -> (hour: String, minute: String) {
        let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "HH"
        let uses12 = template.contains("h") || template.contains("K")
        var hour = calendar.component(.hour, from: date)
        if uses12 { hour = hour % 12 == 0 ? 12 : hour % 12 }
        let minute = calendar.component(.minute, from: date)
        return (String(format: "%02d", hour), String(format: "%02d", minute))
    }
}

// MARK: - Stacked Time & Date Pod (Phase 32)

private struct StackedClockCardView: View {
    let content: ClockContent
    let widgetSize: WidgetSize
    var date: Date = Date()
    @ObservedObject private var calendarService = ProductivityServices.shared.calendar
    @ObservedObject private var alarmStore = ProductivityServices.shared.alarms
    @State private var isHovered = false

    var body: some View {
        Group {
            switch widgetSize {
            case .small:
                compactView
            case .medium:
                mediumView
            case .large:
                largeView
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .dockTileChrome(isHovered: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .contentShape(Rectangle())
        // Nothing is requested here on purpose. This card sits on the bar at launch, so asking from
        // `onAppear` turned the calendar permission into a prompt with no user action. The card offers an
        // "Allow calendar access" row instead, and tapping through to the panel or the notch page asks
        // from that click — a calendar-intent action, not a launch.
    }

    private var compactView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(content.primaryText)
                .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let secondary = content.secondaryText {
                Text(secondary)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }

    private struct CardNextEvent {
        let title: String
        let start: Date
        let isAllDay: Bool
        let color: Color
    }

    private func resolvedNextEvent(cal: Calendar) -> CardNextEvent? {
        if let upcoming = calendarService.upcoming.first {
            let rgb = upcoming.colorRGB
            let c = rgb.count >= 3 ? Color(red: rgb[0], green: rgb[1], blue: rgb[2]) : .accentColor
            return CardNextEvent(title: upcoming.title, start: upcoming.start, isAllDay: upcoming.isAllDay, color: c)
        }
        if let today = calendarService.events
            .filter({ ($0.start > date || ($0.start <= date && $0.end > date)) && !cal.isDateInYesterday($0.start) })
            .sorted(by: { $0.start < $1.start })
            .first {
            return CardNextEvent(title: today.title, start: today.start, isAllDay: today.isAllDay, color: today.color)
        }
        return nil
    }

    private var mediumView: some View {
        let cal = Calendar.current
        let nextEvent = resolvedNextEvent(cal: cal)
        let nextAlarmTuple = AlarmList.next(in: alarmStore.alarms, after: date)

        return HStack(spacing: 8) {
            // Left: Time & Date
            VStack(alignment: .leading, spacing: 1.5) {
                Text(content.primaryText)
                    .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if let secondary = content.secondaryText {
                    Text(secondary)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.80))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }

            // Hairline separator
            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 1, height: 24)

            // Right: Upcoming event / alarm / live seconds
            VStack(alignment: .leading, spacing: 2) {
                if let event = nextEvent {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(event.color)
                            .frame(width: 5, height: 5)
                        Text(verbatim: event.title)
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }

                    Text(verbatim: formatEventRelative(event.start, isAllDay: event.isAllDay))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.70))
                        .lineLimit(1)
                } else if let (alarm, fireDate) = nextAlarmTuple {
                    HStack(spacing: 3) {
                        Image(systemName: "alarm.fill")
                            .font(.system(size: 8.5))
                            .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.25))
                        Text(verbatim: String(format: "%02d:%02d", alarm.hour, alarm.minute))
                            .font(.system(size: 9.5, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                    }

                    Text(verbatim: formatAlarmRelative(fireDate))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.25).opacity(0.85))
                        .lineLimit(1)
                } else {
                    HStack(spacing: 3) {
                        Image(systemName: "calendar")
                            .font(.system(size: 8.5))
                            .foregroundStyle(Color.white.opacity(0.60))
                        Text("No Events")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.82))
                            .lineLimit(1)
                    }

                    Text(verbatim: "W\(cal.component(.weekOfYear, from: date)) • D\(cal.ordinality(of: .day, in: .year, for: date) ?? 1)")
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.60))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var largeView: some View {
        let cal = Calendar.current
        let nextEvent = resolvedNextEvent(cal: cal)
        let nextAlarmTuple = AlarmList.next(in: alarmStore.alarms, after: date)
        let sec = cal.component(.second, from: date)

        return HStack(spacing: 10) {
            // Left: Time with live seconds + Date
            VStack(alignment: .leading, spacing: 1.5) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(content.primaryText)
                        .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)

                    Text(verbatim: ":\(String(format: "%02d", sec))")
                        .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color(red: 0.38, green: 0.68, blue: 1.0))
                }
                .lineLimit(1)

                if let secondary = content.secondaryText {
                    Text(secondary)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.82))
                        .lineLimit(1)
                }
            }

            // Hairline separator
            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 1, height: 26)

            // Right: Upcoming event + Alarm badge
            VStack(alignment: .leading, spacing: 2.5) {
                if let event = nextEvent {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(event.color)
                            .frame(width: 5, height: 5)
                        Text(verbatim: event.title)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }

                    Text(verbatim: formatEventRelative(event.start, isAllDay: event.isAllDay))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .lineLimit(1)
                } else if calendarService.eventsAccess == .unknown {
                    // Nothing has read the calendar yet, so this is the card's own calendar-intent action:
                    // the only thing on the bar that raises the prompt, and only because it was clicked.
                    Button {
                        calendarService.startEvents()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.white.opacity(0.60))
                            Text("Allow calendar access")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.80))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                    .buttonStyle(.plain)
                } else if calendarService.eventsAccess == .denied {
                    // Never "No Events" for a calendar we are not allowed to read.
                    HStack(spacing: 4) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.white.opacity(0.60))
                        Text("Calendar access is off")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.80))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.white.opacity(0.60))
                        Text("No Events")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.80))
                    }
                    Text(verbatim: "W\(cal.component(.weekOfYear, from: date)) • D\(cal.ordinality(of: .day, in: .year, for: date) ?? 1)")
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.60))
                        .lineLimit(1)
                }

                if let (alarm, fireDate) = nextAlarmTuple {
                    HStack(spacing: 3) {
                        Image(systemName: "alarm.fill")
                            .font(.system(size: 8.5))
                            .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.25))
                        Text(verbatim: "\(String(format: "%02d:%02d", alarm.hour, alarm.minute)) (\(formatAlarmRelative(fireDate)))")
                            .font(.system(size: 8.5, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.25).opacity(0.90))
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func formatEventRelative(_ start: Date, isAllDay: Bool = false) -> String {
        CalendarEventCompactFormatter.relativeLine(for: start, isAllDay: isAllDay, now: date)
    }

    private func formatAlarmRelative(_ fireDate: Date) -> String {
        let diff = Int(fireDate.timeIntervalSince(date))
        let m = max(1, diff / 60)
        let h = m / 60
        if h > 0 {
            return "in \(h)h \(m % 60)m"
        }
        return "in \(m)m"
    }
}

/// Hover preview card matching `WeatherPreviewCard`: today's date/week summary + next 4 upcoming events.
private struct ClockCalendarPreviewCard: View {
    @ObservedObject private var calendarService = ProductivityServices.shared.calendar

    var body: some View {
        let cal = Calendar.current
        let now = Date()
        DockPreviewCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(now, style: .date)
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    Text(verbatim: "W\(cal.component(.weekOfYear, from: now)) · D\(cal.ordinality(of: .day, in: .year, for: now) ?? 1)")
                        .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Divider().opacity(0.25)

                if calendarService.upcoming.isEmpty {
                    Text("No upcoming events in lookahead window")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(calendarService.upcoming.prefix(4)) { ev in
                            let c = ev.colorRGB.count >= 3 ? Color(red: ev.colorRGB[0], green: ev.colorRGB[1], blue: ev.colorRGB[2]) : .accentColor
                            HStack(spacing: 6) {
                                Circle().fill(c).frame(width: 6, height: 6)
                                Text(verbatim: ev.title).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(verbatim: CalendarEventCompactFormatter.relativeLine(for: ev.start, isAllDay: ev.isAllDay, now: now))
                                    .font(.system(size: 10.5).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}
