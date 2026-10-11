import AppKit
import SwiftUI

// Phase 5e (rework) — the floating widget tiles. No outer panel: every widget is its own solid
// rounded tile floating on the wallpaper, content-sized and anchored top-right. Two layouts (Mac
// column / iPad grid) and four colour palettes are the shared widget vocabulary (HYBRID_PLAN §5e).

struct CalendarPanelView: View {
    let layout: CalendarPanelLayout
    let width: CGFloat
    let maxHeight: CGFloat
    let onHeight: (CGFloat) -> Void

    @AppStorage(TilePalette.storageKey) private var palette: TilePalette = .classic
    @AppStorage(CalendarClockStyle.storageKey) private var clockStyle: CalendarClockStyle = .flip
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var calendarService = ProductivityServices.shared.calendar
    @StateObject private var clocks = WorldClockStore()
    @ObservedObject private var focus = ProductivityServices.shared.focus
    @ObservedObject private var alarms = ProductivityServices.shared.alarms
    @ObservedObject private var timer = ProductivityServices.shared.timer
    @ObservedObject private var stopwatch = ProductivityServices.shared.stopwatch
    @ObservedObject private var countdowns = ProductivityServices.shared.countdowns
    @AppStorage(WidgetExtraPrefs.showNotesKey) private var showNotes = true
    @AppStorage(WidgetExtraPrefs.showStopwatchKey) private var showStopwatch = true

    private let gutter: CGFloat = 8
    private let gap: CGFloat = 10
    private let bandHeight: CGFloat = 30
    private let reminderRow: CGFloat = 26
    private let alarmRow: CGFloat = 30

    var body: some View {
        let env = TileEnv(palette: palette, isDark: colorScheme == .dark)
        let inner = width - 2 * gutter
        VStack(spacing: gap) {
            switch layout {
            case .mac: macTiles(env: env, inner: inner)
            case .ipad: ipadTiles(env: env, inner: inner)
            case .tall: tallTiles(env: env, inner: inner)
            }
        }
        .padding(gutter)
        .frame(width: width)
        .background(GeometryReader { Color.clear.preference(key: PanelHeightKey.self, value: $0.size.height) })
        .onPreferenceChange(PanelHeightKey.self) { onHeight($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { calendarService.start(); calendarService.refreshAll() }
    }

    // MARK: Layouts

    private func macTiles(env: TileEnv, inner: CGFloat) -> some View {
        let t = (inner - gap) / 2
        let calendarHeight: CGFloat = 178
        let fixed = 2 * gutter + t + calendarHeight + 3 * gap + bandHeight + 10
        let rows = listRows(budget: maxHeight - fixed)
        return VStack(spacing: gap) {
            HStack(spacing: gap) {
                ClockTile(env: env, store: clocks, style: clockStyle, width: t, height: t, zoneLimit: 3)
                FocusTile(env: env, controller: focus, width: t, height: t)
            }.widgetEntrance(0)
            HStack(alignment: .top, spacing: 12) {
                AgendaPane(env: env, service: calendarService, maxRows: 3, compact: true)
                    .frame(width: (inner - 12) * 0.46, alignment: .topLeading)
                MonthGrid(env: env, service: calendarService, cell: 17, fontSize: 10)
                    .frame(maxWidth: .infinity)
            }
            .padding(12)
            .frame(width: inner, height: calendarHeight, alignment: .topLeading)
            .tileSurface(env)
            listTiles(env: env, tileWidth: t, rows: rows)
        }
    }

    /// Phase 5h Tall layout: every tile stretches so the stack fills the screen height. The pure
    /// `TallLayoutPlanner` decides which optional tiles fit and how leftover space is shared.
    private func tallTiles(env: TileEnv, inner: CGFloat) -> some View {
        var defs = [
            TallTile("clock", min: 150, ideal: 200, max: 260, flex: 2),
            TallTile("calendar", min: 190, ideal: 300, max: 400, flex: 3),
            TallTile("alarms", min: 88, ideal: 150, max: 230, flex: 1),
            TallTile("reminders", min: 88, ideal: 150, max: 230, flex: 1),
            TallTile("timers", min: 165, ideal: 220, max: 280, flex: 1.2),
        ]
        if showNotes { defs.append(TallTile("notes", min: 100, ideal: 170, max: 260, flex: 1, optional: 1)) }
        if showStopwatch { defs.append(TallTile("extras", min: 130, ideal: 190, max: 260, flex: 1, optional: 2)) }
        let plan = TallLayoutPlanner.plan(defs, available: Double(maxHeight - 2 * gutter), gap: Double(gap))
        let half = (inner - gap) / 2
        return VStack(spacing: gap) {
            ForEach(Array(plan.enumerated()), id: \.offset) { index, item in
                let h = CGFloat(item.height)
                Group {
                    switch item.id {
                    case "clock": ClockWideTile(env: env, store: clocks, style: clockStyle, width: inner, height: h)
                    case "calendar": calendarWide(env: env, inner: inner, height: h)
                    case "alarms":
                        AlarmsTile(env: env, store: alarms, width: inner, height: h, rows: max(1, Int((h - bandHeight - 10) / 34)), rowHeight: 34, band: bandHeight)
                    case "reminders":
                        RemindersTile(env: env, service: calendarService, width: inner, height: h, rows: max(1, Int((h - bandHeight - 10) / 34)), rowHeight: 34)
                    case "timers":
                        HStack(spacing: gap) {
                            FocusTile(env: env, controller: focus, width: half, height: h)
                            TimerTile(env: env, controller: timer, width: half, height: h)
                        }
                    case "notes": NotesTile(env: env, width: inner, height: h)
                    default:
                        HStack(spacing: gap) {
                            StopwatchTile(env: env, controller: stopwatch, width: half, height: h)
                            CountdownTile(env: env, store: countdowns, width: half, height: h)
                        }
                    }
                }
                .widgetEntrance(index)
            }
        }
    }

    private func calendarWide(env: TileEnv, inner: CGFloat, height: CGFloat) -> some View {
        let pad: CGFloat = 16
        let monthW = (inner - 2 * pad) * 0.56
        let cell = max(18, min(34, (height - 2 * pad - 52) / 6 - 2))
        let rows = max(2, Int((height - 2 * pad - 60) / 36))
        return HStack(alignment: .top, spacing: 16) {
            AgendaPane(env: env, service: calendarService, maxRows: rows, compact: false)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            MonthGrid(env: env, service: calendarService, cell: cell, fontSize: 12)
                .frame(width: monthW)
        }
        .padding(pad)
        .frame(width: inner, height: height, alignment: .topLeading)
        .tileSurface(env)
    }

    private func ipadTiles(env: TileEnv, inner: CGFloat) -> some View {
        let u = (inner - 2 * gap) / 3
        let wide = 2 * u + gap
        let agendaRows = max(2, Int((u - 24 - 50) / 34))
        let fixed = 2 * gutter + 2 * u + 3 * gap + bandHeight + 10
        let rows = listRows(budget: maxHeight - fixed)
        return VStack(spacing: gap) {
            HStack(spacing: gap) {
                DateTile(env: env, service: calendarService, width: u, height: u)
                AgendaPane(env: env, service: calendarService, maxRows: agendaRows, compact: false)
                    .padding(14)
                    .frame(width: wide, height: u, alignment: .topLeading)
                    .tileSurface(env)
            }
            HStack(spacing: gap) {
                MonthGrid(env: env, service: calendarService, cell: min(30, (wide - 28) / 7 - 2), fontSize: 13)
                    .padding(14)
                    .frame(width: wide, height: u, alignment: .top)
                    .tileSurface(env)
                ClockTile(env: env, store: clocks, style: clockStyle, width: u, height: u, zoneLimit: 3)
            }
            HStack(alignment: .top, spacing: gap) {
                FocusTile(env: env, controller: focus, width: u, height: bandHeight + CGFloat(rows) * reminderRow + 10)
                listTiles(env: env, tileWidth: u, rows: rows)
            }
        }
    }

    /// Reminders + Alarms band tiles; height follows the data (≥ 2 rows), capped by the screen budget.
    private func listTiles(env: TileEnv, tileWidth: CGFloat, rows: Int) -> some View {
        let needed = min(rows, max(2, calendarService.reminders.count, alarms.alarms.count))
        let height = bandHeight + CGFloat(needed) * alarmRow + 10
        return HStack(alignment: .top, spacing: gap) {
            RemindersTile(env: env, service: calendarService, width: tileWidth, height: height, rows: needed, rowHeight: alarmRow)
            AlarmsTile(env: env, store: alarms, width: tileWidth, height: height, rows: needed, rowHeight: alarmRow, band: bandHeight)
        }
    }

    private func listRows(budget: CGFloat) -> Int { max(2, min(5, Int(budget / alarmRow))) }
}

// MARK: - Date tile (iPad)

struct DateTile: View {
    let env: TileEnv
    @ObservedObject var service: CalendarService
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let date = service.selectedDate
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.month(.wide)).uppercased())
                .font(.system(size: 18, weight: .bold)).foregroundColor(env.onAccent(.date))
                .frame(maxWidth: .infinity, minHeight: 40).background(env.accent(.date))
            Spacer(minLength: 0)
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: height * 0.42, weight: .medium)).foregroundColor(env.text)
                .minimumScaleFactor(0.5)
            Spacer(minLength: 0)
            Text(date.formatted(.dateTime.weekday(.wide)).uppercased())
                .font(.system(size: 15, weight: .bold)).foregroundColor(env.secondary)
                .padding(.bottom, 12)
        }
        .frame(width: width, height: height)
        .tileSurface(env)
        .onTapGesture { service.selectedDate = Date(); service.displayedMonth = Date() }
    }
}

// MARK: - Agenda pane (next event + later today)

struct AgendaPane: View {
    let env: TileEnv
    @ObservedObject var service: CalendarService
    let maxRows: Int
    let compact: Bool

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short; return f
    }()

    var body: some View {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(service.selectedDate)
        VStack(alignment: .leading, spacing: 4) {
            if service.eventsAccess == .denied {
                if !compact { Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 26)).foregroundColor(env.secondary) }
                Text("Calendar access is off").font(.system(size: 12)).foregroundColor(env.secondary)
                Button("Open Settings") { Self.openPrivacy("Privacy_Calendars") }.font(.system(size: 12))
            } else {
                TimelineView(.periodic(from: Date(), by: 30)) { ctx in
                    content(now: ctx.date, isToday: isToday)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private func content(now: Date, isToday: Bool) -> some View {
        let timed = service.events.filter { !$0.isAllDay }
        let next = isToday ? timed.first(where: { $0.start > now }) : nil
        let rest = service.events.filter { $0.id != next?.id }
        VStack(alignment: .leading, spacing: 4) {
            if let next {
                Text("Next Event").font(.system(size: 10, weight: .semibold)).foregroundColor(env.secondary)
                Text(Self.relative.localizedString(for: next.start, relativeTo: now))
                    .font(.system(size: compact ? 17 : 24, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                eventRow(next)
            } else if !isToday {
                Text(service.selectedDate.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                    .font(.system(size: compact ? 15 : 20, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
            } else if service.events.isEmpty {
                Text("No events").font(.system(size: compact ? 15 : 20, weight: .bold)).foregroundColor(env.secondary)
            }
            if !rest.isEmpty {
                Text("Later Today").font(.system(size: 10, weight: .semibold)).foregroundColor(env.secondary)
                    .padding(.top, 2)
                let shown = max(0, maxRows - (next == nil ? 0 : 1))
                ForEach(Array(rest.prefix(shown))) { eventRow($0) }
                if rest.count > shown {
                    Text(verbatim: "+\(rest.count - shown)").font(.system(size: 10, weight: .bold)).foregroundColor(env.secondary)
                }
            }
        }
        .foregroundColor(env.text)
    }

    private func eventRow(_ e: AgendaEvent) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(e.color).frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(e.title).font(.system(size: 12, weight: .bold)).lineLimit(1)
                if !e.isAllDay {
                    Text(verbatim: "\(e.start.formatted(date: .omitted, time: .shortened)) – \(e.end.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 10)).foregroundColor(env.secondary).lineLimit(1)
                }
            }
        }
        .frame(height: 30)
    }

    static func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
}

// MARK: - Month grid

struct MonthGrid: View {
    let env: TileEnv
    @ObservedObject var service: CalendarService
    let cell: CGFloat
    let fontSize: CGFloat
    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(service.displayedMonth.formatted(.dateTime.month(.abbreviated).year()))
                    .font(.system(size: fontSize + 2, weight: .bold)).foregroundColor(env.accent(.calendar))
                Spacer()
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain)
                Button { shift(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain)
            }
            .font(.system(size: fontSize, weight: .bold)).foregroundColor(env.secondary)
            .padding(.bottom, 2)
            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, s in
                    Text(s).font(.system(size: fontSize - 1, weight: .bold)).foregroundColor(env.secondary).frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 1) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in dayCell(day) }
                }
            }
        }
    }

    private var weekdaySymbols: [String] {
        let s = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(s[first...] + s[..<first])
    }

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
            let isToday = calendar.isDateInToday(day)
            let isSelected = calendar.isDate(day, inSameDayAs: service.selectedDate)
            Text(verbatim: "\(n)")
                .font(.system(size: fontSize, weight: isToday ? .bold : .semibold))
                .foregroundColor(isToday ? .white : env.text)
                .frame(maxWidth: .infinity).frame(height: cell)
                .background(RoundedRectangle(cornerRadius: cell / 3, style: .continuous)
                    .fill(isToday ? env.accent(.calendar) : heat(service.monthDensity[n] ?? 0)))
                .overlay(RoundedRectangle(cornerRadius: cell / 3, style: .continuous)
                    .stroke(isSelected && !isToday ? env.text.opacity(0.55) : .clear, lineWidth: 1))
                .contentShape(Rectangle())
                .onTapGesture { service.selectedDate = day }
        } else {
            // Explicit height: a bare `Color.clear` is vertically greedy and blows the first row apart.
            Color.clear.frame(maxWidth: .infinity).frame(height: cell)
        }
    }

    private func heat(_ events: Int) -> Color {
        switch events {
        case 0: return .clear
        case 1: return Color.yellow.opacity(0.30)
        case 2, 3: return Color.orange.opacity(0.38)
        default: return Color.red.opacity(0.42)
        }
    }

    private func shift(_ months: Int) {
        if let d = calendar.date(byAdding: .month, value: months, to: service.displayedMonth) { service.displayedMonth = d }
    }
}

// MARK: - Clock tile (flip by default / analog)

struct ClockTile: View {
    let env: TileEnv
    @ObservedObject var store: WorldClockStore
    let style: CalendarClockStyle
    let width: CGFloat
    let height: CGFloat
    let zoneLimit: Int
    @State private var picking = false

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(verbatim: WorldClockModel.city(for: TimeZone.current.identifier).uppercased())
                    .font(.system(size: 11, weight: .bold)).foregroundColor(env.secondary).lineLimit(1)
                Spacer()
                if store.identifiers.count < WorldClockModel.maxClocks {
                    Button { picking.toggle() } label: { Image(systemName: "plus") }
                        .buttonStyle(.plain).foregroundColor(env.secondary)
                        .popover(isPresented: $picking) { TimeZonePicker(store: store, done: { picking = false }) }
                }
            }
            TimelineView(.periodic(from: Date(), by: 1)) { ctx in
                VStack(spacing: 6) {
                    face(at: ctx.date).frame(maxWidth: .infinity)
                    Spacer(minLength: 0)
                    ForEach(store.identifiers.prefix(zoneLimit), id: \.self) { id in
                        if let r = WorldClockModel.reading(for: id, at: ctx.date) {
                            HStack(spacing: 4) {
                                Image(systemName: r.isNight ? "moon.stars.fill" : "sun.max.fill")
                                    .font(.system(size: 9)).foregroundColor(r.isNight ? .indigo : .orange)
                                Text(verbatim: r.city).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                                if r.dayDelta > 0 { Text("Tomorrow").font(.system(size: 9)).foregroundColor(env.secondary) }
                                if r.dayDelta < 0 { Text("Yesterday").font(.system(size: 9)).foregroundColor(env.secondary) }
                                Spacer(minLength: 0)
                                Text(r.time).font(.system(size: 11, weight: .bold)).monospacedDigit()
                            }
                            .contextMenu { Button("Remove") { store.remove(id) } }
                        }
                    }
                }
            }
        }
        .foregroundColor(env.text)
        .padding(12)
        .frame(width: width, height: height)
        .tileSurface(env)
    }

    @ViewBuilder private func face(at date: Date) -> some View {
        switch style {
        case .flip:
            let tile = min(60, (width - 24 - 14) / 2)
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            HStack(spacing: 5) {
                flipDigit(String(format: "%02d", c.hour ?? 0), size: tile)
                VStack(spacing: 7) { Circle().frame(width: 4, height: 4); Circle().frame(width: 4, height: 4) }
                    .foregroundColor(env.secondary)
                flipDigit(String(format: "%02d", c.minute ?? 0), size: tile)
            }
        case .analog:
            AnalogFace(env: env, date: date).frame(width: min(width - 24, height * 0.46), height: min(width - 24, height * 0.46))
        }
    }

    private func flipDigit(_ text: String, size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(env.accent(.clock))
            Text(text).font(.system(size: size * 0.62, weight: .bold, design: .rounded)).monospacedDigit().foregroundColor(.white)
            Rectangle().fill(Color.black.opacity(0.35)).frame(height: 1)
        }
        .frame(width: size, height: size * 1.12)
    }
}

struct AnalogFace: View {
    let env: TileEnv
    let date: Date

    var body: some View {
        let c = Calendar.current
        let h = Double(c.component(.hour, from: date) % 12), m = Double(c.component(.minute, from: date)), s = Double(c.component(.second, from: date))
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height), r = d / 2
            ZStack {
                Circle().fill(env.accent(.clock))
                ForEach(0..<12, id: \.self) { i in
                    Rectangle().fill(Color.white.opacity(i % 3 == 0 ? 0.95 : 0.5))
                        .frame(width: i % 3 == 0 ? 2.5 : 1.5, height: i % 3 == 0 ? 7 : 4)
                        .offset(y: -r + 8).rotationEffect(.degrees(Double(i) * 30))
                }
                hand(length: r * 0.5, width: 3.5, color: .white, angle: (h + m / 60) * 30)
                hand(length: r * 0.75, width: 2.5, color: .white, angle: (m + s / 60) * 6)
                hand(length: r * 0.82, width: 1.2, color: .orange, angle: s * 6)
                Circle().fill(Color.orange).frame(width: 6, height: 6)
            }
            .frame(width: d, height: d)
        }
    }

    private func hand(length: CGFloat, width: CGFloat, color: Color, angle: Double) -> some View {
        Capsule().fill(color).frame(width: width, height: length)
            .offset(y: -length / 2).rotationEffect(.degrees(angle))
    }
}

struct TimeZonePicker: View {
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

// MARK: - Focus tile

struct FocusTile: View {
    let env: TileEnv
    @ObservedObject var controller: FocusTimerController
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let m = controller.model
        let ring = min(width - 34, height - 78)
        VStack(spacing: 5) {
            HStack {
                if m.phase == .focus { Text("Focus") } else { Text("Break") }
                Spacer()
            }
            .font(.system(size: 11, weight: .bold)).textCase(.uppercase).foregroundColor(env.secondary)
            ZStack {
                Circle().stroke(env.accent(.focus).opacity(0.18), lineWidth: 8)
                Circle().trim(from: 0, to: max(0.001, m.progress))
                    .stroke(env.accent(.focus), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(verbatim: String(format: "%02d:%02d", m.remaining / 60, m.remaining % 60))
                    .font(.system(size: ring * 0.26, weight: .bold)).monospacedDigit()
            }
            .frame(width: ring, height: ring)
            HStack(spacing: 14) {
                Button { controller.reset() } label: { Image(systemName: "arrow.counterclockwise") }
                Button { controller.toggle() } label: {
                    Image(systemName: m.isRunning ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 24))
                        .foregroundColor(env.accent(.focus))
                }
                Button { controller.skip() } label: { Image(systemName: "forward.end") }
            }
            .buttonStyle(.plain).font(.system(size: 13, weight: .bold)).foregroundColor(env.secondary)
            HStack(spacing: 5) {
                ForEach(0..<FocusTimerModel.cycleLength, id: \.self) { i in
                    Circle().fill(i < m.completedInCycle ? env.accent(.focus) : env.secondary.opacity(0.25)).frame(width: 6, height: 6)
                }
            }
        }
        .foregroundColor(env.text)
        .padding(12)
        .frame(width: width, height: height)
        .tileSurface(env)
    }
}

// MARK: - Reminders + alarms (header-band tiles)

struct RemindersTile: View {
    let env: TileEnv
    @ObservedObject var service: CalendarService
    let width: CGFloat
    let height: CGFloat
    let rows: Int
    let rowHeight: CGFloat

    var body: some View {
        BandTile(env: env, kind: .reminders, width: width, height: height, header: {
            HStack { Text("Reminders"); Spacer(); Text(verbatim: "\(service.reminders.count)").opacity(0.8) }
        }, content: {
            if service.remindersAccess == .denied {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Reminders access is off").font(.system(size: 11)).foregroundColor(env.secondary)
                    Button("Open Settings") { AgendaPane.openPrivacy("Privacy_Reminders") }.font(.system(size: 11))
                }
            } else if service.reminders.isEmpty {
                Text("No reminders").font(.system(size: 12, weight: .semibold)).foregroundColor(env.secondary).padding(.top, 4)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(service.reminders.prefix(rows))) { r in
                        HStack(spacing: 6) {
                            Button { service.complete(r) } label: { Image(systemName: "circle").font(.system(size: 14)) }
                                .buttonStyle(.plain).foregroundColor(env.accent(.reminders))
                            Text(r.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .frame(height: rowHeight)
                    }
                }
            }
        })
    }
}

struct AlarmsTile: View {
    let env: TileEnv
    @ObservedObject var store: AlarmStore
    let width: CGFloat
    let height: CGFloat
    let rows: Int
    let rowHeight: CGFloat
    let band: CGFloat
    @State private var adding = false
    @State private var newTime = Date()

    var body: some View {
        BandTile(env: env, kind: .alarms, width: width, height: height, band: band, header: {
            HStack {
                Text("Alarms"); Spacer()
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
                Text("No alarms").font(.system(size: 12, weight: .semibold)).foregroundColor(env.secondary).padding(.top, 4)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(store.alarms.prefix(rows))) { a in
                        HStack {
                            Text(verbatim: String(format: "%02d:%02d", a.hour, a.minute))
                                .font(.system(size: 18, weight: .bold)).monospacedDigit().opacity(a.isEnabled ? 1 : 0.35)
                            Spacer()
                            Toggle(isOn: Binding(get: { a.isEnabled }, set: { store.setEnabled($0, for: a.id) })) { EmptyView() }
                                .toggleStyle(.switch).labelsHidden().scaleEffect(0.7)
                        }
                        .frame(height: rowHeight)
                        .contextMenu { Button("Remove") { store.remove(a.id) } }
                    }
                }
            }
        })
    }
}
