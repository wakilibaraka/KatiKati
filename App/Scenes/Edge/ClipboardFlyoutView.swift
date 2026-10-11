import SwiftUI

/// Clipboard history (Phase 7A-P4): click a row to copy it back. Recording is opt-in and memory-only.
struct ClipboardFlyoutView: View {
    @ObservedObject private var monitor = ProductivityServices.shared.clipboard
    @AppStorage(TilePalette.storageKey) private var palette: TilePalette = .classic
    @Environment(\.colorScheme) private var colorScheme
    @State private var copiedID: UUID?

    var body: some View {
        let size = ProductivityFlyout.size(.clipboard)
        let env = TileEnv(palette: palette, isDark: colorScheme == .dark)
        BandTile(env: env, kind: .countdown, width: size.width - 16, height: size.height - 16, header: {
            HStack {
                Text("Clipboard")
                Spacer()
                if !monitor.history.entries.isEmpty {
                    Button { monitor.clear() } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).help(Text("Clear History"))
                }
                Toggle(isOn: Binding(get: { monitor.isRecording }, set: { monitor.setRecording($0) })) { EmptyView() }
                    .toggleStyle(.switch).labelsHidden().scaleEffect(0.7).help(Text("Record Clipboard"))
            }
        }, content: {
            if !monitor.isRecording && monitor.history.entries.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Clipboard history is off").font(.system(size: 12, weight: .semibold))
                    Text("Turn it on to remember text you copy. History stays in memory only and is never saved, and copies marked secret by password managers are skipped.")
                        .font(.system(size: 11)).foregroundColor(env.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 6)
            } else if monitor.history.entries.isEmpty {
                Text("Nothing copied yet").font(.system(size: 12, weight: .semibold)).foregroundColor(env.secondary).padding(.top, 4)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(monitor.history.displayOrder) { entry in row(entry, env: env) }
                    }
                }
            }
        })
        .padding(8)
    }

    private func row(_ entry: ClipEntry, env: TileEnv) -> some View {
        Button {
            monitor.copy(entry)
            copiedID = entry.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { if copiedID == entry.id { copiedID = nil } }
        } label: {
            HStack(spacing: 6) {
                if entry.pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundColor(env.accent(.countdown)) }
                Text(verbatim: ClipboardHistory.previewLine(entry.text)).font(.system(size: 12)).lineLimit(2)
                Spacer(minLength: 4)
                if copiedID == entry.id { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
            }
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if entry.pinned { Button("Unpin") { monitor.togglePin(entry.id) } } else { Button("Pin") { monitor.togglePin(entry.id) } }
            Button("Delete") { monitor.remove(entry.id) }
        }
    }
}
