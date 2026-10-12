import SwiftUI

/// Right half of the full notch skin: month / year, a one-week strip with today highlighted, then the
/// next event or the empty state.
struct NotchCalendarPanel: View {
    @ObservedObject var calendar: CalendarService

    var body: some View {
        let now = Date()
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: now.formatted(.dateTime.month(.abbreviated))).font(.system(size: 18, weight: .bold, design: .rounded))
                    Text(verbatim: now.formatted(.dateTime.year())).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
            }
            weekStrip(now)
            events(now)
            Spacer(minLength: 0)
        }
        .onAppear {
            if calendar.eventsAccess == .unknown { calendar.start() }
            if !Foundation.Calendar.current.isDateInToday(calendar.selectedDate) { calendar.selectedDate = Date() }
        }
    }

    private func weekStrip(_ now: Date) -> some View {
        HStack(spacing: 0) {
            ForEach(NotchLayoutSpec.weekStrip(now: now), id: \.date) { day in
                VStack(spacing: 2) {
                    Text(verbatim: day.date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                    Text(verbatim: "\(day.dayNumber)")
                        .font(.system(size: 12, weight: day.isToday ? .bold : .regular)).monospacedDigit()
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(day.isToday ? Color.accentColor : .clear))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func events(_ now: Date) -> some View {
        let upcoming = calendar.events.filter { $0.isAllDay || $0.end > now }
        if let next = upcoming.first {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(next.color).frame(width: 3, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: next.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    if !next.isAllDay {
                        Text(verbatim: next.start.formatted(date: .omitted, time: .shortened)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    }
                }
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("No events today").font(.system(size: 12, weight: .semibold))
                    Text("Enjoy your free time!").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
                Image(systemName: "calendar").font(.system(size: 22)).foregroundStyle(.white.opacity(0.4))
            }
        }
    }
}
