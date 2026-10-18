import SwiftUI

// Phase 33e — Page 4: Productivity & Calendar (Bento Card A: Calendar, Card B: Focus).
//
// Phase 48a — both cards carry live data instead of a sample. Card A is the selected day's agenda on a
// week strip you can walk a day or a week at a time, and a tap on a row opens the meeting's own link when
// the event has one (otherwise Calendar on that day) — `AgendaEventAction` decides, one rule, shared with
// the floating panel. Card B drives the real Pomodoro (`FocusTimerModel`: 25/5/15, four to a cycle) and
// ticks off the next reminder. The random "decision" spinner that used to sit here is gone: it was the one
// thing on the page with nothing behind it.

struct NotchProductivityPageView: View {
    @ObservedObject private var agenda = ProductivityServices.shared.calendar
    @ObservedObject var feed: LiveActivityFeed

    private let accent = Color(red: 0.95, green: 0.25, blue: 0.30)
    private let todayAccent = Color(red: 0.90, green: 0.20, blue: 0.25)

    var body: some View {
        HStack(spacing: NotchDesignSpec.cardSpacing) {
            musicCard
            calendarCard
        }
        .onAppear {
            agenda.start()
            if !Calendar.current.isDateInToday(agenda.selectedDate) { agenda.selectedDate = Date() }
        }
    }

    // MARK: - Card A: music (merged in from the old Vinyl Audio Deck page)

    private var musicCard: some View {
        NotchMusicPanel(feed: feed, isIdle: feed.nowPlayingState.title == nil)
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

    // MARK: - Card B: agenda on a walkable week strip

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: NotchProductivityLayout.rowSpacing) {
            calendarHeader
            weekStrip
            agendaList
            Spacer(minLength: 0)
        }
        .padding(NotchDesignSpec.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                .fill(Color(red: 0.08, green: 0.06, blue: 0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                        .stroke(accent.opacity(0.25), lineWidth: NotchDesignSpec.cardStrokeWidth)
                )
        )
    }

    private var calendarHeader: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().fill(todayAccent).frame(width: 18, height: 18)
                Image(systemName: "calendar").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
            }
            Text(verbatim: agenda.selectedDate.formatted(.dateTime.month(.wide).year()).uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(verbatim: selectedDayChip)
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(todayAccent)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(todayAccent.opacity(0.15)))
        }
        .frame(height: NotchProductivityLayout.cardHeader)
    }

    private var selectedDayChip: String {
        Calendar.current.isDateInToday(agenda.selectedDate)
            ? "TODAY"
            : agenda.selectedDate.formatted(.dateTime.weekday(.abbreviated)).uppercased()
    }

    private var weekStrip: some View {
        HStack(spacing: 0) {
            weekShift(-7, symbol: "chevron.left")
            ForEach(NotchLayoutSpec.weekStrip(now: agenda.selectedDate), id: \.date) { day in
                dayCell(day)
            }
            weekShift(7, symbol: "chevron.right")
        }
        .frame(height: NotchProductivityLayout.weekStrip)
    }

    /// A week at a time, so any day is reachable without a month grid the notch has no room for.
    private func weekShift(_ days: Int, symbol: String) -> some View {
        Button {
            guard let moved = Calendar.current.date(byAdding: .day, value: days, to: agenda.selectedDate) else { return }
            withAnimation(.easeOut(duration: 0.15)) { agenda.selectedDate = moved }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 11, height: NotchProductivityLayout.weekStrip)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dayCell(_ day: NotchLayoutSpec.WeekDay) -> some View {
        let calendar = Calendar.current
        let selected = calendar.isDate(day.date, inSameDayAs: agenda.selectedDate)
        let isToday = calendar.isDateInToday(day.date)
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { agenda.selectedDate = day.date }
        } label: {
            VStack(spacing: 1) {
                Text(verbatim: day.date.formatted(.dateTime.weekday(.narrow)))
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
                Text(verbatim: "\(day.dayNumber)")
                    .font(.system(size: 10, weight: selected ? .heavy : .semibold))
                    .monospacedDigit()
                    .foregroundStyle(selected ? .white : .white.opacity(0.8))
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(selected ? todayAccent : Color.white.opacity(isToday ? 0.10 : 0)))
                    .overlay(Circle().stroke(todayAccent.opacity(isToday && !selected ? 0.6 : 0), lineWidth: 1))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The visible label is the day's number alone, which reads as seven identical "button"s. The
        // formatted date is the accessible name (and `help` is the idiom this app's other buttons use for
        // theirs), which localises itself — no catalog key.
        .accessibilityLabel(Text(day.date.formatted(.dateTime.weekday(.wide).day().month(.wide))))
        .help(Text(day.date.formatted(.dateTime.weekday(.wide).day().month(.wide))))
    }

    @ViewBuilder
    private var agendaList: some View {
        if agenda.eventsAccess == .denied {
            // The door to the grant, the same route the floating panel offers.
            Button("Open Settings") { AgendaPane.openPrivacy("Privacy_Calendars") }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accent)
                .frame(height: agendaListHeight, alignment: .top)
        } else if agenda.events.isEmpty {
            Text("No events")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .frame(height: agendaListHeight, alignment: .top)
        } else {
            let rows = Array(agenda.events.prefix(NotchProductivityLayout.agendaRowCount))
            ForEach(rows) { event in
                eventRow(event)
            }
            if agenda.events.count > rows.count {
                Text(verbatim: "+\(agenda.events.count - rows.count) more")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }

    private var agendaListHeight: CGFloat {
        CGFloat(NotchProductivityLayout.agendaRowCount) * NotchProductivityLayout.agendaRow
    }

    private func eventRow(_ event: AgendaEvent) -> some View {
        Button { AgendaEventOpener.open(event) } label: {
            HStack(spacing: 4) {
                Capsule().fill(event.color).frame(width: 2.5)
                Text(verbatim: event.isAllDay ? "ALL DAY" : event.start.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 38, alignment: .leading)
                Text(verbatim: event.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if event.isJoinable {
                    Image(systemName: "video.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(accent)
                }
            }
            .frame(height: NotchProductivityLayout.agendaRow)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
