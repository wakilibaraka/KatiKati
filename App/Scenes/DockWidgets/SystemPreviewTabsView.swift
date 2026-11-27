import SwiftUI

enum SystemPreviewPage: String, CaseIterable, Identifiable, Sendable {
    case overview
    case processes
    case storage

    var id: String { rawValue }
}

/// D3: Tabbed System preview popover (`Overview` / `Memory` processes / `Storage` volumes + scan).
/// Reuses `DockSystemFeed`, `ActivityProcessMonitor`, `DriveInventory`, and `StorageScanService`.
struct SystemPreviewTabsView: View {
    @AppStorage("com.katikati.system.previewPage") private var pageRaw = SystemPreviewPage.overview.rawValue
    @ObservedObject private var feed = DockSystemFeed.shared
    @StateObject private var processMonitor = ActivityProcessMonitor()
    @StateObject private var storageScanner = StorageScanService()
    @State private var volumes: [DriveVolume] = []

    private var page: SystemPreviewPage {
        SystemPreviewPage(rawValue: pageRaw) ?? .overview
    }

    var body: some View {
        DockPreviewCard {
            VStack(alignment: .leading, spacing: 12) {
                Picker("System", selection: $pageRaw) {
                    Text("Overview").tag(SystemPreviewPage.overview.rawValue)
                    Text("Memory").tag(SystemPreviewPage.processes.rawValue)
                    Text("Storage").tag(SystemPreviewPage.storage.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch page {
                case .overview:
                    overviewGrid
                case .processes:
                    processesList
                case .storage:
                    storageSection
                }
            }
            .frame(width: 280, alignment: .leading)
        }
        .onAppear {
            feed.retain()
            syncMonitors(for: page)
        }
        .onChange(of: pageRaw) { _, _ in
            syncMonitors(for: page)
        }
        .onDisappear {
            feed.release()
            processMonitor.stop()
        }
    }

    private func syncMonitors(for target: SystemPreviewPage) {
        if target == .processes {
            processMonitor.start(backgroundIDsProvider: { [] })
        } else {
            processMonitor.stop()
        }
        if target == .storage {
            volumes = DriveInventory.volumes()
        }
    }

    private var overviewGrid: some View {
        let snap = feed.snapshot
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], alignment: .leading, spacing: 14) {
            statCell(Text("CPU"), value: SystemMonitorFormat.percent(snap.cpu),
                     history: feed.cpu.normalized(ceiling: 1), tint: loadTint(for: snap.cpu))
            statCell(Text("RAM"), value: SystemMonitorFormat.percent(snap.memory.fraction),
                     history: feed.memory.normalized(ceiling: 1), tint: loadTint(for: snap.memory.fraction))
            statCell(Text("SSD Read"), value: "\(SystemMonitorFormat.bytes(snap.diskRead))/s",
                     history: feed.diskRead.normalized(ceiling: feed.diskRead.values.max() ?? 1), tint: .cyan)
            statCell(Text("SSD Write"), value: "\(SystemMonitorFormat.bytes(snap.diskWrite))/s",
                     history: feed.diskWrite.normalized(ceiling: feed.diskWrite.values.max() ?? 1), tint: .orange)
        }
    }

    private var processesList: some View {
        let top = Array(processMonitor.entries.prefix(6))
        return VStack(alignment: .leading, spacing: 6) {
            if !processMonitor.hasSampled && top.isEmpty {
                ProgressView().controlSize(.small)
            } else {
                ForEach(top) { entry in
                    HStack(spacing: 8) {
                        Text(verbatim: entry.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(verbatim: SystemMonitorFormat.bytes(Double(entry.bytes)))
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(volumes.prefix(3)) { vol in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(verbatim: vol.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(verbatim: SystemMonitorFormat.bytes(Double(vol.freeBytes)))
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.14))
                            Capsule()
                                .fill(vol.usedFraction > 0.9 ? DockWidgetStyle.bad : Color.accentColor)
                                .frame(width: max(4, proxy.size.width * vol.usedFraction))
                        }
                    }
                    .frame(height: 5)
                }
            }

            Divider().opacity(0.25)

            HStack {
                Text("Storage")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                Button {
                    storageScanner.scan()
                } label: {
                    Image(systemName: storageScanner.state == .scanning ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .disabled(storageScanner.state == .scanning)
            }

            if storageScanner.state == .scanning {
                Text("Scanning…").dockCaption()
            } else {
                ForEach(storageScanner.files.prefix(3)) { item in
                    HStack(spacing: 8) {
                        Text(verbatim: item.name).font(.system(size: 11)).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(verbatim: SystemMonitorFormat.bytes(Double(item.bytes)))
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func statCell(_ title: Text, value: String, history: [Double], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            title.dockCaption()
            Text(verbatim: value)
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            DockSparkline(values: history, tint: tint).frame(height: 34)
        }
    }

    private func loadTint(for fraction: Double) -> Color {
        fraction >= 0.85 ? DockWidgetStyle.bad : fraction >= 0.6 ? DockWidgetStyle.warn : DockWidgetStyle.good
    }
}
