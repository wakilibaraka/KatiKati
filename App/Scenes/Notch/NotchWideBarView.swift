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
            VStack(alignment: .leading, spacing: 0) {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(verbatim: ctx.date.formatted(.dateTime.hour().minute().second()))
                        .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    Text(verbatim: ctx.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                }
            }
            .foregroundStyle(.white).lineLimit(1).fixedSize()
            Spacer(minLength: 0)
            if items.contains(.nowPlaying), let title = feed.nowPlayingState.title {
                HStack(spacing: 5) {
                    Image(systemName: feed.nowPlayingState.isPlaying ? "waveform" : "pause.fill")
                        .font(.system(size: 10)).foregroundStyle(.pink)
                    Text(verbatim: [title, feed.nowPlayingState.artist].compactMap { $0 }.joined(separator: " – "))
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                }
                .frame(maxWidth: width * 0.4)
                Spacer(minLength: 0)
            }
            if items.contains(.storage) {
                HStack(spacing: 3) {
                    Image(systemName: "internaldrive.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(.cyan)
                    Text(verbatim: StorageScanMath.compact(free))
                        .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(.white)
                }
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
