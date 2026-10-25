import SwiftUI

extension EventTimeUntil {
    /// "in 3m", "in 1h 5m", "in 2d", "Now"; nil once the event is over.
    var label: String? {
        switch self {
        case .minutes(let m): return String(format: String(localized: "in %lldm"), m)
        case .hours(let h, let m): return m == 0 ? String(format: String(localized: "in %lldh"), h) : String(format: String(localized: "in %lldh %lldm"), h, m)
        case .days(let d): return String(format: String(localized: "in %lldd"), d)
        case .now: return String(localized: "Now")
        case .ended: return nil
        }
    }
}

/// Date badge: month over day, like the Calendar app icon.
private struct DateBadge: View {
    let date: Date
    var size: CGFloat = 32

    var body: some View {
        VStack(spacing: 0) {
            Text(verbatim: date.formatted(.dateTime.month(.abbreviated)).uppercased())
                .font(.system(size: size * 0.26, weight: .bold))
                .foregroundStyle(DockWidgetStyle.bad)
            Text(verbatim: date.formatted(.dateTime.day()))
                .font(.system(size: size * 0.52, weight: .semibold)).monospacedDigit()
                .minimumScaleFactor(0.7)
        }
        .frame(width: size, height: size)
        .background(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(Color.white.opacity(0.1)))
        .accessibilityHidden(true)
    }
}

/// Bar widget: date badge plus the next meeting and how soon it starts. S = badge, M = + title and countdown,
/// L = + the meeting after it.
struct CalendarDockChip: View {
    @Environment(\.widgetSize) private var size
    @ObservedObject private var feed = DockCalendarFeed.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let events = UpcomingEvents.select(feed.upcoming, now: context.date, limit: 2)
            HStack(spacing: 8) {
                DateBadge(date: context.date)
                if size != .small {
                    VStack(alignment: .leading, spacing: 1) {
                        if let next = events.first {
                            Text(verbatim: next.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text(verbatim: EventTimeUntil.resolve(start: next.start, end: next.end, now: context.date).label ?? "")
                                .dockCaption()
                            if size == .large, events.count > 1 {
                                Text(verbatim: "\(events[1].start.formatted(date: .omitted, time: .shortened)) · \(events[1].title)")
                                    .dockCaption()
                            }
                        } else {
                            Text(verbatim: context.date.formatted(.dateTime.weekday(.wide))).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text(feed.access == .denied ? "Calendar access is off" : "No upcoming meetings").dockCaption()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .dockWidgetChip()
        .dockHoverPreview { CalendarPreviewCard() }
        .onTapGesture { CalendarDockActions.openCalendar() }
        .onAppear { feed.retain() }
        .onDisappear { feed.release() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Side-rail tile: the date badge, with a dot when a meeting starts within the hour.
struct RailCalendarTile: View {
    @ObservedObject private var feed = DockCalendarFeed.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let soon = UpcomingEvents.select(feed.upcoming, now: context.date, limit: 1).first
                .map { $0.start.timeIntervalSince(context.date) < 3600 } ?? false
            DateBadge(date: context.date, size: 28)
                .overlay(alignment: .topTrailing) {
                    if soon { Circle().fill(DockWidgetStyle.bad).frame(width: 7, height: 7).offset(x: 3, y: -3) }
                }
        }
        .dockWidgetRailTile()
        .dockHoverPreview { CalendarPreviewCard() }
        .onTapGesture { CalendarDockActions.openCalendar() }
        .onAppear { feed.retain() }
        .onDisappear { feed.release() }
        .accessibilityLabel(Text("Calendar"))
        .accessibilityAddTraits(.isButton)
    }
}

enum CalendarDockActions {
    static func openCalendar() {
        if let url = URL(string: "ical://") { NSWorkspace.shared.open(url) }
    }
}

/// Hover preview: the next meetings, each with a Join button when it carries a Zoom / Meet / Teams link.
struct CalendarPreviewCard: View {
    @ObservedObject private var feed = DockCalendarFeed.shared

    var body: some View {
        DockPreviewCard {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                let events = UpcomingEvents.select(feed.upcoming, now: context.date, limit: 4)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Upcoming").font(.system(size: 13, weight: .semibold))
                    if events.isEmpty {
                        Text(feed.access == .denied ? "Calendar access is off" : "No upcoming meetings").dockCaption()
                    } else {
                        ForEach(events) { event in
                            row(event, now: context.date)
                            if event.id != events.last?.id { Divider().opacity(0.2) }
                        }
                    }
                }
            }
        }
        .onAppear { feed.retain() }
        .onDisappear { feed.release() }
    }

    private func row(_ event: DockEvent, now: Date) -> some View {
        let until = EventTimeUntil.resolve(start: event.start, end: event.end, now: now)
        let joinable = EventTimeUntil.isJoinable(start: event.start, end: event.end, now: now)
        return HStack(spacing: 10) {
            Capsule().fill(Color(.sRGB, red: event.colorRGB[safe: 0] ?? 0.4, green: event.colorRGB[safe: 1] ?? 0.6,
                                 blue: event.colorRGB[safe: 2] ?? 1, opacity: 1))
                .frame(width: 3, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: event.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(verbatim: "\(event.start.formatted(date: .omitted, time: .shortened)) · \(until.label ?? "")").dockCaption()
            }
            Spacer(minLength: 6)
            if let link = event.link {
                Button { NSWorkspace.shared.open(link.url) } label: {
                    Label { Text("Join") } icon: { Image(systemName: link.provider.symbolName) }
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(joinable ? DockWidgetStyle.good : Color.white.opacity(0.14)))
                        .foregroundStyle(joinable ? Color.black : DockWidgetStyle.ink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Join"))
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
