import SwiftUI

/// 51h: the closed notch on a display without a cutout — a menu-bar-height bar with more data than the ears
/// can carry. Which items show at this width is decided in `NotchWideBarSpec` (Core, tested).
struct NotchWideBarView: View {
    let width: CGFloat
    let height: CGFloat
    @ObservedObject private var feed = LiveActivityFeed.shared
    @StateObject private var power = SystemStatusService()
    @State private var free: Int64 = 0

    var body: some View {
        let items = NotchWideBarSpec.items(width: width)
        HStack(spacing: 12) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: ctx.date.formatted(.dateTime.hour().minute().second()))
                        .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    Text(verbatim: ctx.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                }
            }
            .foregroundStyle(.white).lineLimit(1).fixedSize()
            if items.contains(.timer) { WideBarTimer() }
            Spacer(minLength: 0)
            if items.contains(.nowPlaying), let title = feed.nowPlayingState.title {
                HStack(spacing: 5) {
                    Image(systemName: feed.nowPlayingState.isPlaying ? "waveform" : "pause.fill")
                        .font(.system(size: 10)).foregroundStyle(.pink)
                    Text(verbatim: [title, feed.nowPlayingState.artist].compactMap { $0 }.joined(separator: " – "))
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                }
                .frame(maxWidth: width * 0.35)
                Spacer(minLength: 0)
            }
            if items.contains(.system) { WideBarSystem() }
            if items.contains(.weather), let service = WeatherPanelHost.service { WideBarWeather(service: service) }
            if items.contains(.storage) {
                HStack(spacing: 3) {
                    Image(systemName: "internaldrive.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(.cyan)
                    Text(verbatim: StorageScanMath.compact(free))
                        .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(.white)
                }
            }
            if items.contains(.status) {
                HStack(spacing: 6) {
                    Image(systemName: power.status.wifi.symbolName)
                    Image(systemName: power.status.volume.symbolName)
                }
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
            }
            if items.contains(.battery), let level = power.status.battery.level {
                NotchBatteryChip(level: level, battery: power.status.battery)
            }
        }
        .padding(.horizontal, 6)
        .frame(width: width, height: height)
        .onAppear { power.acquire() }
        .onDisappear { power.release() }
        .task {
            while !Task.isCancelled {
                free = StorageScanService.freeBytes()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }
}

/// Countdown remaining, shown only while the shared Timer is running.
private struct WideBarTimer: View {
    @ObservedObject private var timer = ProductivityServices.shared.timer

    var body: some View {
        if timer.model.isRunning {
            let r = timer.model.remaining
            HStack(spacing: 3) {
                Image(systemName: "timer").font(.system(size: 10, weight: .semibold)).foregroundStyle(.orange)
                Text(verbatim: String(format: "%d:%02d", r / 60, r % 60))
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(.white)
            }
        }
    }
}

private struct WideBarWeather: View {
    @ObservedObject var service: WeatherService
    @AppStorage(WeatherUnits.temperatureKey) private var unit: TemperatureUnit = .celsius

    var body: some View {
        let state = service.currentState
        if !service.needsLocation {
            HStack(spacing: 4) {
                WeatherIllustration(condition: state.conditionFamily, isNight: state.isNight, size: 14)
                Text(verbatim: WeatherUnits.degrees(state.temperatureCelsius, unit))
                    .font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            }
        }
    }
}

/// CPU / RAM from the shared sampler; its 1 s timer runs only while this item is on screen.
private struct WideBarSystem: View {
    @StateObject private var monitor = SystemMonitorController()

    var body: some View {
        Text(verbatim: "CPU \(Int((monitor.snapshot.cpu * 100).rounded()))%  RAM \(Int((monitor.snapshot.memory.fraction * 100).rounded()))%")
            .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(.white)
            .onAppear { monitor.acquire() }
            .onDisappear { monitor.release() }
    }
}
