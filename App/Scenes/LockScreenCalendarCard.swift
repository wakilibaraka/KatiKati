import AppKit
import EventKit
import SwiftUI

/// L1: Droppy-style translucent calendar strip for the lock screen, reading cached EventKit data only
/// (`EKEventStore.authorizationStatus(for: .event) == .fullAccess`, never triggering a prompt).
struct LockScreenCalendarCard: View {
    @ObservedObject private var feed = DockCalendarFeed.shared
    @AppStorage(LockScreenPrefs.calendarDetailKey) private var detailRaw = LockScreenDetailMode.busyOnly.rawValue

    private var hasFullAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let mode = LockScreenPrefs.detailMode(from: detailRaw)
            let rows = hasFullAccess
                ? LockScreenSurfacePolicy.eventRows(
                    from: feed.upcoming,
                    now: context.date,
                    detailMode: mode,
                    limit: 3,
                    busyPlaceholder: String(localized: "Calendar")
                )
                : []

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                    Text("Calendar")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.88))
                    Spacer(minLength: 4)
                    Text(verbatim: context.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }

                if !hasFullAccess {
                    Text("Calendar access is off")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                } else if rows.isEmpty {
                    Text(verbatim: "—")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(rows) { row in
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                    .fill(rowColor(row.colorRGB))
                                    .frame(width: 3, height: 14)
                                Text(verbatim: row.displayTitle)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.92))
                                    .lineLimit(1)
                                Spacer(minLength: 6)
                                if let countdown = row.countdownLabel {
                                    Text(verbatim: countdown)
                                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(row.isOngoing ? Color.green : .white.opacity(0.68))
                                } else if !row.timeLabel.isEmpty {
                                    Text(verbatim: row.timeLabel)
                                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(.white.opacity(0.65))
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.75)
            )
        }
        .onAppear {
            if hasFullAccess { feed.retain() }
        }
        .onDisappear {
            if hasFullAccess { feed.release() }
        }
    }

    private func rowColor(_ rgb: [Double]) -> Color {
        guard rgb.count >= 3 else { return Color.accentColor }
        return Color(red: rgb[0], green: rgb[1], blue: rgb[2])
    }
}

/// L4: Compact lock-screen glance pills (Focus remaining, cached Weather temperature, Next event countdown).
struct LockScreenGlanceRow: View {
    @ObservedObject private var focus = ProductivityServices.shared.focus
    @ObservedObject private var weather = WeatherService.shared
    @ObservedObject private var calendarFeed = DockCalendarFeed.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let focusText = focus.model.isRunning ? NotchLayoutSpec.clockText(TimeInterval(focus.model.remaining)) : nil
            let weatherState = weather.currentState
            let temp: Double? = weatherState.hasData ? weatherState.temperatureCelsius : nil
            let symbol: String? = weatherState.hasData ? weatherState.symbolName : nil
            let nextEvent = EKEventStore.authorizationStatus(for: .event) == .fullAccess
                ? UpcomingEvents.select(calendarFeed.upcoming, now: context.date, limit: 1).first
                : nil
            let nextCountdown = nextEvent.flatMap { EventTimeUntil.resolve(start: $0.start, end: $0.end, now: context.date).label }

            let items = LockScreenSurfacePolicy.glanceItems(
                focusRemaining: focusText,
                temperatureCelsius: temp,
                weatherSymbol: symbol,
                nextEventCountdown: nextCountdown
            )

            if !items.isEmpty {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        HStack(spacing: 4) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 10.5, weight: .semibold))
                            Text(verbatim: item.text)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
                    }
                }
            }
        }
    }
}

/// L3: Full-screen blurred album artwork backdrop drawn behind the lock screen card stack when enabled.
struct LockScreenFullArtBackdropView: View {
    @ObservedObject var service: NowPlayingService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.opacity(0.52)
            if let data = service.state.artworkData, let img = NSImage(data: data) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 56)
                    .saturation(1.25)
                    .opacity(0.75)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: data)
            }
            LinearGradient(
                colors: [Color.black.opacity(0.38), Color.black.opacity(0.18), Color.black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

/// Unified lock-screen stack hosted by `LockScreenMusicCardController`.
struct LockScreenStackView: View {
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject private var queueFetcher = MusicQueueFetcher.shared
    let selection: MusicSurfaceStyleSelection
    let showsCalendar: Bool
    let showsGlance: Bool
    let musicHeight: CGFloat

    var body: some View {
        let cardLayout = selection.layout(for: .lockScreen) == .slim ? .full : selection.layout(for: .lockScreen)
        VStack(spacing: 10) {
            if showsGlance {
                LockScreenGlanceRow()
            }
            MusicGlassCardView(
                service: nowPlaying,
                theme: selection.theme(for: .lockScreen),
                layout: cardLayout,
                scrubber: selection.scrubber(for: .lockScreen),
                palette: MusicArtworkPaletteCache.shared.palette(for: nowPlaying.state.artworkData),
                assignment: MusicSurfaceConfig.assignment(),
                showsChrome: false,
                showsVolumeRow: MusicSurfaceConfig.isLockVolumeEnabled,
                isLockScreen: true,
                externalUpcoming: queueFetcher.upcoming
            )
            .frame(height: musicHeight)
            if showsCalendar {
                LockScreenCalendarCard()
            }
        }
        .onAppear {
            queueFetcher.refreshIfNeeded(appName: nowPlaying.state.appName, currentTitle: nowPlaying.state.title, allowAppleScript: false)
        }
        .onChange(of: nowPlaying.state.title) { _, nextTitle in
            queueFetcher.refreshIfNeeded(appName: nowPlaying.state.appName, currentTitle: nextTitle, allowAppleScript: false)
        }
    }
}
