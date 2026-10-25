import SwiftUI

/// Phase 10a-6 — shared state for Smart Stack slots: the manual "Show Next in Stack" overrides and what each
/// host slot is currently showing (so the menu can step from the right member).
@MainActor
final class SmartStackState: ObservableObject {
    static let shared = SmartStackState()
    @Published private(set) var overrides: [BarSection: StackOverride] = [:]
    private(set) var shown: [BarSection: BarSection] = [:]

    func recordShown(_ member: BarSection, for host: BarSection) { shown[host] = member }

    func showNext(host: BarSection, members: [BarSection], now: Date = Date()) {
        let current = shown[host] ?? members.first ?? .clock
        overrides[host] = StackOverride(member: StackRelevance.next(after: current, in: members),
                                        until: now.addingTimeInterval(StackRelevance.overrideDuration))
    }
}

/// One slot that shows the most relevant of its members (`StackRelevance`). Re-scores only when the live
/// activity or the weather condition changes; holds the shared feed only while it is on screen (the feed's
/// 1 Hz tick is refcounted, so nothing runs once every surface is gone).
struct SmartStackSlot<Content: View>: View {
    let host: BarSection
    let members: [BarSection]
    let content: (BarSection) -> Content

    @ObservedObject private var feed = LiveActivityFeed.shared
    @ObservedObject private var state = SmartStackState.shared
    @ObservedObject private var calendarFeed = DockCalendarFeed.shared
    @ObservedObject private var systemFeed = DockSystemFeed.shared
    @ObservedObject private var devicesFeed = DockDevicesFeed.shared
    @EnvironmentObject private var weatherService: WeatherService
    @State private var current: BarSection?

    var body: some View {
        let now = Date()
        let signals = StackSignals(
            liveKind: feed.activity.kind, weatherCondition: weatherService.currentState.conditionFamily,
            meetingSoon: members.contains(.calendar) && calendarFeed.upcoming.contains {
                EventTimeUntil.isJoinable(start: $0.start, end: $0.end, now: now)
            },
            systemBusy: members.contains(.system) && (systemFeed.snapshot.cpu > 0.8 || systemFeed.snapshot.memory.fraction > 0.9),
            deviceLow: members.contains(.devices) && devicesFeed.devices.contains { ($0.lowestBattery ?? 100) <= 20 })
        let shown = StackRelevance.resolve(members: members, signals: signals, current: current,
                                           override: state.overrides[host], now: now)
        content(shown)
            .id(shown)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: shown)
            .onAppear { retainFeeds(); current = shown; state.recordShown(shown, for: host) }
            .onDisappear { releaseFeeds() }
            .onChange(of: shown) { newValue in
                current = newValue
                state.recordShown(newValue, for: host)
            }
    }

    private func retainFeeds() {
        feed.retain()
        if members.contains(.calendar) { calendarFeed.retain() }
        if members.contains(.system) { systemFeed.retain() }
        if members.contains(.devices) { devicesFeed.retain() }
    }

    private func releaseFeeds() {
        feed.release()
        if members.contains(.calendar) { calendarFeed.release() }
        if members.contains(.system) { systemFeed.release() }
        if members.contains(.devices) { devicesFeed.release() }
    }
}
