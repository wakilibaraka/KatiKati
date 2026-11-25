import SwiftUI

/// SD-7: the deck's dashboard — the four bento widgets the plan lists, on the deck's own cards and surfaces.
/// Feeds are acquired on appear and released on disappear, so an off-screen dashboard polls nothing.
struct SideDeckDashboardView: View {
    let onOpenTab: (SideDeckTab) -> Void

    @ObservedObject private var downloads = DownloadManagerService.shared
    @ObservedObject private var mirror = NotificationMirrorService.shared
    @ObservedObject private var weather = WeatherService.shared
    @ObservedObject private var calendar = DockCalendarFeed.shared
    @State private var freeBytes: Int64 = 0
    /// SD-3d/SD-7: what the Storage page last measured, read from preferences — the dashboard never scans.
    @State private var reclaimableBytes: Int64?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            downloadsCard
            clearDiskCard
            digestCard
            todayCard
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            downloads.retain()
            calendar.retain()
            freeBytes = StorageScanService.freeBytes()
            reclaimableBytes = DevCacheSnapshotStore.load()?.reclaimableBytes
        }
        .onDisappear {
            downloads.release()
            calendar.release()
        }
    }

    // MARK: - Active downloads

    private var downloadsCard: some View {
        let active = downloads.items.filter { $0.bytesDownloaded < $0.totalBytes }
        return card(title: "ACTIVE DOWNLOADS", symbol: SideDeckTab.downloads.symbol) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: DownloadItem.formatBytes(downloads.aggregateDownloadBps) + "/s")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
                Text(verbatim: "\(active.count)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color.green.opacity(0.18)))
            }
            if let first = active.first {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: first.name)
                        .font(.system(size: 11))
                        .lineLimit(1)
                    ProgressView(value: first.totalBytes > 0
                                 ? Double(first.bytesDownloaded) / Double(first.totalBytes) : 0)
                        .progressViewStyle(.linear)
                }
            } else {
                Text(verbatim: "Nothing downloading.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 0)
            openButton("Downloads", tab: .downloads)
        }
    }

    // MARK: - ClearDisk

    private var clearDiskCard: some View {
        card(title: "FREE DISK", symbol: SideDeckTab.storage.symbol) {
            Text(verbatim: DownloadItem.formatBytes(freeBytes))
                .font(.system(size: 26, weight: .semibold, design: .rounded))
            if let reclaimableBytes {
                HStack(spacing: 5) {
                    Image(systemName: "hammer")
                        .font(.system(size: 10))
                    Text(verbatim: "Reclaimable")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                    Spacer(minLength: 0)
                    Text(verbatim: DownloadItem.formatBytes(reclaimableBytes))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.secondary)
            } else {
                Text(verbatim: "ClearDisk lives in Storage.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 0)
            openButton("Storage", tab: .storage)
        }
    }

    // MARK: - Notification digest

    private var digestCard: some View {
        let entries = mirror.historyStore.entries
        let unread = NotificationDigest.unreadCount(entries)
        return card(title: "NOTIFICATIONS", symbol: SideDeckTab.notifications.symbol) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: "\(unread)")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                Text("Unread")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            ForEach(NotificationDigest.previews(entries, limit: 3)) { entry in
                HStack(spacing: 6) {
                    Circle()
                        .fill(entry.isRead ? Color.clear : Color.accentColor)
                        .frame(width: 5, height: 5)
                    Text(verbatim: entry.title)
                        .font(.system(size: 11))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(verbatim: NotificationDigest.label(for: entry.appBundleId))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            if entries.isEmpty {
                Text(verbatim: "No notifications yet.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button { mirror.clearHistoryStore() } label: {
                    Text("Clear").font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .buttonStyle(.plain)
                .disabled(entries.isEmpty)
                openButton("Open", tab: .notifications)
            }
        }
    }

    // MARK: - Today glance

    private var todayCard: some View {
        card(title: "TODAY", symbol: "clock") {
            // A one-minute timeline, only while this card is on screen: an off-screen dashboard schedules nothing.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(verbatim: context.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
            }
            let state = weather.currentState
            if !state.cityName.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: state.symbolName)
                        .font(.system(size: 12))
                    Text(verbatim: "\(Int(state.temperatureCelsius.rounded()))° \(state.conditionText)")
                        .font(.system(size: 11))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
            }
            if let next = calendar.upcoming.first {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11))
                    Text(verbatim: next.title)
                        .font(.system(size: 11))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(verbatim: next.start.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            openButton("Weather", tab: .weather)
        }
    }

    // MARK: - Chrome

    private func card<Content: View>(title: String, symbol: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(verbatim: title)
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer(minLength: 0)
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 150, maxHeight: .infinity, alignment: .topLeading)
        .sideDeckCard()
    }

    private func openButton(_ title: String, tab: SideDeckTab) -> some View {
        Button { onOpenTab(tab) } label: {
            Text(verbatim: title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}
