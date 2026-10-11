import AppKit
import SwiftUI

// Phase 5e-B…F — content of the floating calendar panel. Every card is visible at once (no
// scrolling): flexible cards measure their height and show only the rows that fit, plus a
// "+N more" line. Colours come from the active dock theme tokens.

struct CalendarPanelView: View {
    let preset: CalendarPanelPreset

    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var calendarService = CalendarService()
    @StateObject private var clocks = WorldClockStore()
    @StateObject private var focus = FocusTimerController()
    @StateObject private var alarms = AlarmStore()

    private var theme: DockThemeTokens {
        let token = UserDefaults.standard.string(forKey: "com.katikati.theme.material") ?? ""
        return .resolved(for: colorScheme, style: DockThemeStyle(token: token) ?? .auto)
    }

    var body: some View {
        let ctx = PanelCardStyle(text: theme.labelActive.color, secondary: theme.labelSubtitle.color, line: theme.zoneDivider.color)
        HStack(alignment: .top, spacing: 10) {
            switch preset {
            case .compact420:
                column {
                    DateCard(service: calendarService, style: ctx)
                    MonthCard(service: calendarService, style: ctx)
                    ClocksCard(store: clocks, style: ctx)
                    AlarmsCard(store: alarms, style: ctx)
                }
                column {
                    AgendaCard(service: calendarService, style: ctx)
                    FocusCard(controller: focus, style: ctx)
                    RemindersCard(service: calendarService, style: ctx)
                }
            case .halfScreen:
                column {
                    DateCard(service: calendarService, style: ctx)
                    MonthCard(service: calendarService, style: ctx)
                    ClocksCard(store: clocks, style: ctx)
                }
                column {
                    AgendaCard(service: calendarService, style: ctx)
                    AlarmsCard(store: alarms, style: ctx)
                }
                column {
                    FocusCard(controller: focus, style: ctx)
                    RemindersCard(service: calendarService, style: ctx)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(ctx.line, lineWidth: 0.5))
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onAppear { calendarService.start(); calendarService.refreshAll() }
    }

    private func column<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 10) { content() }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PanelCardStyle {
    let text: Color
    let secondary: Color
    let line: Color
}

private struct PanelCard<Header: View, Content: View>: View {
    let style: PanelCardStyle
    var flexible = true
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header()
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .foregroundColor(style.secondary)
            content().foregroundColor(style.text)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: flexible ? .infinity : nil, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(style.line, lineWidth: 0.5))
        .clipped()
    }
}

/// Renders as many `rows` as fit in the available height, then "+N more".
private struct FittedRows<Item: Identifiable, Row: View>: View {
    let items: [Item]
    let rowHeight: CGFloat
    let style: PanelCardStyle
    @ViewBuilder var row: (Item) -> Row

    var body: some View {
        GeometryReader { geo in
            let fit = AgendaFitting.visibleCount(total: items.count, height: geo.size.height, rowHeight: rowHeight, reservedForMore: 16)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.prefix(fit.shown))) { item in row(item).frame(height: rowHeight) }
                if fit.more > 0 {
                    Text(verbatim: "+\(fit.more)").font(.system(size: 10, weight: .semibold)).foregroundColor(style.secondary)
                        .frame(height: 16)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Date + month

private struct DateCard: View {
    @ObservedObject var service: CalendarService
    let style: PanelCardStyle

    var body: some View {
        let date = service.selectedDate
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.month(.wide)).uppercased())
                .font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 5)
                .background(Color(red: 0.93, green: 0.18, blue: 0.27))
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: 44, weight: .medium)).foregroundColor(style.text)
                .padding(.top, 2)
            Text(date.formatted(.dateTime.weekday(.wide)).uppercased())
                .font(.system(size: 11, weight: .semibold)).foregroundColor(style.secondary)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.07)))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(style.line, lineWidth: 0.5))
        .onTapGesture { service.selectedDate = Date(); service.displayedMonth = Date() }
    }
}

private struct MonthCard: View {
    @ObservedObject var service: CalendarService
    let style: PanelCardStyle
    private let calendar = Calendar.current

    var body: some View {
        PanelCard(style: style, flexible: false, header: {
            HStack {
                Text(service.displayedMonth.formatted(.dateTime.month(.abbreviated).year())).textCase(nil)
                Spacer()
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain)
                Button { shift(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain)
            }
        }, content: {
            VStack(spacing: 2) {
                HStack(spacing: 0) {
                    ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, s in
                        Text(s).font(.system(size: 9, weight: .semibold)).foregroundColor(style.secondary).frame(maxWidth: .infinity)
                    }
                }
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: 2) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, day in dayCell(day) }
                    }
                }
            }
        })
    }

    private var weekdaySymbols: [String] {
        let s = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(s[first...] + s[..<first])
    }

    /// 6 rows × 7 days; nil outside the displayed month.
    private var weeks: [[Date?]] {
        guard let interval = calendar.dateInterval(of: .month, for: service.displayedMonth) else { return [] }
        let lead = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: service.displayedMonth)?.count ?? 30
        var cells: [Date?] = Array(repeating: nil, count: lead)
        for d in 0..<count { cells.append(calendar.date(byAdding: .day, value: d, to: interval.start)) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    @ViewBuilder private func dayCell(_ day: Date?) -> some View {
        if let day {
            let n = calendar.component(.day, from: day)
            let events = service.monthDensity[n] ?? 0
            let isToday = calendar.isDateInToday(day)
            let isSelected = calendar.isDate(day, inSameDayAs: service.selectedDate)
            Text(verbatim: "\(n)")
                .font(.system(size: 11, weight: isToday ? .bold : .regular))
                .foregroundColor(isToday ? .white : style.text)
                .frame(maxWidth: .infinity, minHeight: 21)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(
                    isToday ? Color.accentColor : heat(events)))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isSelected && !isToday ? style.text.opacity(0.6) : .clear, lineWidth: 1))
                .contentShape(Rectangle())
                .onTapGesture { service.selectedDate = day }
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: 21)
        }
    }

    private func heat(_ events: Int) -> Color {
        switch events {
        case 0: return .clear
        case 1: return Color.yellow.opacity(0.28)
        case 2, 3: return Color.orange.opacity(0.36)
        default: return Color.red.opacity(0.40)
        }
    }

    private func shift(_ months: Int) {
        if let d = calendar.date(byAdding: .month, value: months, to: service.displayedMonth) { service.displayedMonth = d }
    }
}

// MARK: - Agenda

private struct AgendaCard: View {
    @ObservedObject var service: CalendarService
    let style: PanelCardStyle

    var body: some View {
        PanelCard(style: style, header: {
            HStack(spacing: 4) {
                Text("Agenda")
                Spacer()
                if Calendar.current.isDateInToday(service.selectedDate) {
                    Text("Today").textCase(nil)
                } else {
                    Text(service.selectedDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))).textCase(nil)
                }
            }
        }, content: {
            if service.eventsAccess == .denied {
                AccessNotice(message: Text("Calendar access is off"), style: style, pane: "Privacy_Calendars")
            } else if service.events.isEmpty {
                Text("No events").font(.system(size: 12)).foregroundColor(style.secondary)
            } else {
                FittedRows(items: service.events, rowHeight: 38, style: style) { e in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            .foregroundColor(.white).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(e.color))
                        if !e.isAllDay {
                            Text(verbatim: "\(e.start.formatted(date: .omitted, time: .shortened)) – \(e.end.formatted(date: .omitted, time: .shortened))")
                                .font(.system(size: 10)).foregroundColor(style.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        })
    }
}

private struct AccessNotice: View {
    let message: Text
    let style: PanelCardStyle
    let pane: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            message.font(.system(size: 11)).foregroundColor(style.secondary)
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                    NSWorkspace.shared.open(url)
                }
            }
            .font(.system(size: 11))
        }
    }
}

// MARK: - Reminders

private struct RemindersCard: View {
    @ObservedObject var service: CalendarService
    let style: PanelCardStyle

    var body: some View {
        PanelCard(style: style, header: { Text("Reminders") }, content: {
            if service.remindersAccess == .denied {
                AccessNotice(message: Text("Reminders access is off"), style: style, pane: "Privacy_Reminders")
            } else if service.reminders.isEmpty {
                Text("No reminders").font(.system(size: 12)).foregroundColor(style.secondary)
            } else {
                FittedRows(items: service.reminders, rowHeight: 30, style: style) { r in
                    HStack(spacing: 6) {
                        Button { service.complete(r) } label: { Image(systemName: "circle").font(.system(size: 14)) }
                            .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(r.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                            if let due = r.due {
                                Text(due.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 9)).foregroundColor(style.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        })
    }
}

// MARK: - World clocks

private struct ClocksCard: View {
    @ObservedObject var store: WorldClockStore
    let style: PanelCardStyle
    @State private var picking = false

    var body: some View {
        PanelCard(style: style, header: {
            HStack {
                Text("Time Zones")
                Spacer()
                if store.identifiers.count < WorldClockModel.maxClocks {
                    Button { picking.toggle() } label: { Image(systemName: "plus") }
                        .buttonStyle(.plain)
                        .popover(isPresented: $picking) { TimeZonePicker(store: store, done: { picking = false }) }
                }
            }
        }, content: {
            TimelineView(.periodic(from: Date(), by: 20)) { context in
                let readings = store.identifiers.compactMap { WorldClockModel.reading(for: $0, at: context.date) }
                FittedRows(items: readings, rowHeight: 32, style: style) { r in
                    HStack(spacing: 6) {
                        Image(systemName: r.isNight ? "moon.stars.fill" : "sun.max.fill")
                            .font(.system(size: 12)).foregroundColor(r.isNight ? .indigo : .orange)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(r.city).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            HStack(spacing: 3) {
                                if r.dayDelta > 0 { Text("Tomorrow") } else if r.dayDelta < 0 { Text("Yesterday") }
                                Text(verbatim: r.offsetLabel)
                            }
                            .font(.system(size: 9)).foregroundColor(style.secondary)
                        }
                        Spacer(minLength: 0)
                        Text(r.time).font(.system(size: 13, weight: .medium)).monospacedDigit()
                    }
                    .contextMenu { Button("Remove") { store.remove(r.identifier) } }
                }
            }
        })
    }
}

private struct TimeZonePicker: View {
    @ObservedObject var store: WorldClockStore
    let done: () -> Void
    @State private var query = ""

    private var matches: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers
        let q = query.lowercased()
        return Array((q.isEmpty ? WorldClockModel.defaultIdentifiers + ["Europe/Paris", "Asia/Kolkata", "Australia/Sydney", "Africa/Nairobi"]
                      : all.filter { $0.lowercased().contains(q.replacingOccurrences(of: " ", with: "_")) }).prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Search city or zone", text: $query).textFieldStyle(.roundedBorder)
            ForEach(matches, id: \.self) { id in
                Button { store.add(id); done() } label: { Text(verbatim: WorldClockModel.city(for: id) + "  ·  " + id).font(.system(size: 11)) }
                    .buttonStyle(.plain)
                    .disabled(store.identifiers.contains(id))
            }
        }
        .padding(10).frame(width: 240)
    }
}

// MARK: - Focus

private struct FocusCard: View {
    @ObservedObject var controller: FocusTimerController
    let style: PanelCardStyle

    var body: some View {
        let m = controller.model
        PanelCard(style: style, flexible: false, header: {
            if m.phase == .focus { Text("Focus") } else { Text("Break") }
        }, content: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.12), lineWidth: 6)
                    Circle().trim(from: 0, to: m.progress)
                        .stroke(m.phase == .focus ? Color.green : Color.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Button { controller.toggle() } label: {
                        Image(systemName: m.isRunning ? "pause.fill" : "play.fill").font(.system(size: 16))
                    }.buttonStyle(.plain)
                }
                .frame(width: 62, height: 62)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: String(format: "%02d:%02d", m.remaining / 60, m.remaining % 60))
                        .font(.system(size: 22, weight: .medium)).monospacedDigit()
                    HStack(spacing: 8) {
                        Button { controller.reset() } label: { Image(systemName: "arrow.counterclockwise") }.buttonStyle(.plain)
                        ForEach(0..<FocusTimerModel.cycleLength, id: \.self) { i in
                            Circle().fill(i < m.completedInCycle ? Color.green : Color.primary.opacity(0.15)).frame(width: 7, height: 7)
                        }
                        Button { controller.skip() } label: { Image(systemName: "forward.end") }.buttonStyle(.plain)
                    }
                    .font(.system(size: 11)).foregroundColor(style.secondary)
                }
            }
        })
    }
}

// MARK: - Alarms

private struct AlarmsCard: View {
    @ObservedObject var store: AlarmStore
    let style: PanelCardStyle
    @State private var adding = false
    @State private var newTime = Date()

    var body: some View {
        PanelCard(style: style, header: {
            HStack {
                Text("Alarms")
                Spacer()
                Button { adding.toggle() } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain)
                    .popover(isPresented: $adding) {
                        VStack(spacing: 8) {
                            DatePicker(selection: $newTime, displayedComponents: .hourAndMinute) { Text("Alarm") }.labelsHidden()
                            Button("Add") {
                                let c = Calendar.current.dateComponents([.hour, .minute], from: newTime)
                                store.add(hour: c.hour ?? 7, minute: c.minute ?? 0)
                                adding = false
                            }
                        }.padding(12)
                    }
            }
        }, content: {
            if store.alarms.isEmpty {
                Text("No alarms").font(.system(size: 12)).foregroundColor(style.secondary)
            } else {
                FittedRows(items: store.alarms, rowHeight: 30, style: style) { a in
                    HStack {
                        Text(verbatim: String(format: "%02d:%02d", a.hour, a.minute))
                            .font(.system(size: 15, weight: .medium)).monospacedDigit()
                            .opacity(a.isEnabled ? 1 : 0.4)
                        Spacer()
                        Toggle(isOn: Binding(get: { a.isEnabled }, set: { store.setEnabled($0, for: a.id) })) { EmptyView() }
                            .toggleStyle(.switch).labelsHidden().scaleEffect(0.7)
                    }
                    .contextMenu { Button("Remove") { store.remove(a.id) } }
                }
            }
        })
    }
}
