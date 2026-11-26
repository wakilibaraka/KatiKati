import SwiftUI

/// Right half of the full notch skin: month / year, a one-week strip with today highlighted, then the
/// next event or the empty state.
struct NotchCalendarPanel: View {
    @ObservedObject var calendar: CalendarService
    var onExpand: (() -> Void)?

    var body: some View {
        let date = calendar.selectedDate
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: date.formatted(.dateTime.month(.abbreviated))).font(.system(size: 18, weight: .bold, design: .rounded))
                    Text(verbatim: date.formatted(.dateTime.year())).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                if let onExpand {
                    Button(action: onExpand) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 26, height: 20)
                            .background(Capsule().fill(.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Calendar"))
                    .help(Text("Open Details"))
                }
            }
            weekStrip(date)
            events(for: date)
            Spacer(minLength: 0)
        }
        .onAppear { calendar.startEvents(requestAccess: false) }
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
    private func events(for date: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        let now = Date()
        let upcoming = calendar.events.filter { !isToday || $0.isAllDay || $0.end > now }
        if calendar.eventsAccess == .unknown {
            Button("Connect Calendar") { calendar.startEvents() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        } else if calendar.eventsAccess == .denied {
            Text("Calendar access is off").font(.system(size: 11)).foregroundStyle(.secondary)
        } else if let next = upcoming.first {
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
                (isToday ? Text("No events today") : Text("No events"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Image(systemName: "calendar").font(.system(size: 22)).foregroundStyle(.white.opacity(0.4))
            }
        }
    }
}
