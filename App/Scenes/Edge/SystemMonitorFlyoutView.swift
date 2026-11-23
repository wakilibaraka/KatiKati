import SwiftUI

/// CPU, memory, disk and network at a glance (Phase 7A-8c). Samples only while open.
struct SystemMonitorFlyoutView: View {
    static let size = CGSize(width: 280, height: 372)
    @ObservedObject private var monitor = ProductivityServices.shared.systemMonitor
    @State private var topProcesses: [TopProcess] = []
    @State private var processTask: Task<Void, Never>?

    var body: some View {
        let s = monitor.snapshot
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("System").font(.headline)
                Spacer(minLength: 0)
                // OW-2: the header says why the readings are moving slowly.
                if monitor.isThrottled {
                    Text("Game Mode • Throttled")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                        .help(Text("Telemetry slows down while a full-screen app or Low Power Mode is active."))
                }
            }
            meter(Text("CPU"), fraction: s.cpu, detail: SystemMonitorFormat.percent(s.cpu))
            meter(Text("Memory"), fraction: s.memory.fraction,
                  detail: "\(SystemMonitorFormat.bytes(Double(s.memory.used))) / \(SystemMonitorFormat.bytes(Double(s.memory.total)))")
            meter(Text("Disk"), fraction: s.disk.usedFraction, detail: Text(verbatim: SystemMonitorFormat.bytes(Double(s.disk.free)) + " ") + Text("free"))
            HStack {
                Label { Text(verbatim: SystemMonitorFormat.bytes(s.down) + "/s") } icon: { Image(systemName: "arrow.down") }
                Spacer()
                Label { Text(verbatim: SystemMonitorFormat.bytes(s.up) + "/s") } icon: { Image(systemName: "arrow.up") }
            }
            .font(.callout.monospacedDigit())
            HStack {
                Label { Text(verbatim: "SSD ↓ " + SystemMonitorFormat.bytes(s.diskRead) + "/s") } icon: { Image(systemName: "internaldrive") }
                Spacer()
                Text(verbatim: "↑ " + SystemMonitorFormat.bytes(s.diskWrite) + "/s")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            if !topProcesses.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(topProcesses, id: \.self) { proc in
                        HStack {
                            Text(verbatim: proc.name)
                                .font(.caption2)
                                .lineLimit(1)
                            Spacer()
                            Text(verbatim: String(format: "%.1f%%", proc.cpu))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            // OW-4: the Rig badge — the machine's inventory, read at startup and copied in one click.
            Divider()
            HStack(alignment: .firstTextBaseline) {
                Text(monitor.rigSpec.chip).font(.caption.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(monitor.rigSpec.formattedMarkdownSpec, forType: .string)
                } label: {
                    Text("Copy Specs")
                }
                .controlSize(.mini)
            }
            Text(verbatim: monitor.rigSpec.coreSummary
                 + " · " + "\(monitor.rigSpec.unifiedMemoryGB) GB")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(verbatim: "macOS " + monitor.rigSpec.macOSVersion + " (" + monitor.rigSpec.macOSBuild + ")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .onAppear {
            monitor.acquire()
            startProcessSampling()
        }
        .onDisappear {
            monitor.release()
            processTask?.cancel()
            processTask = nil
        }
    }

    private func startProcessSampling() {
        processTask?.cancel()
        processTask = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                let list = TopProcessReader.read(limit: 3)
                await MainActor.run { topProcesses = list }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func meter(_ title: Text, fraction: Double, detail: String) -> some View {
        meter(title, fraction: fraction, detail: Text(verbatim: detail))
    }

    private func meter(_ title: Text, fraction: Double, detail: Text) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { title.font(.callout.weight(.semibold)); Spacer(); detail.font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            ProgressView(value: min(1, max(0, fraction))).progressViewStyle(.linear)
                .tint(fraction > 0.85 ? .red : (fraction > 0.65 ? .orange : .accentColor))
        }
    }
}
