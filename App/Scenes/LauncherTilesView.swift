import AppKit
import SwiftUI

/// The widget row above the launcher grid (Phase 7B-L5). Tiles are the ones switched on in Settings; each is a
/// small card, nothing runs for a tile that is off.
struct LauncherTilesRow: View {
    let tiles: [LauncherTile]
    let onClose: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(LauncherTile.ordered(tiles), id: \.self) { tile in
                    switch tile {
                    case .clock: LauncherClockTile()
                    case .calculator: LauncherCalculatorTile()
                    case .countdown: LauncherCountdownTile()
                    case .files: LauncherFilesTile(onOpen: onClose)
                    }
                }
            }
        }
        .frame(height: 132)
    }
}

private struct TileCard<Content: View>: View {
    let title: Text
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            title.font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
            content
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 210, height: 128, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.10)))
    }
}

private struct LauncherClockTile: View {
    var body: some View {
        TileCard(title: Text("Clock")) {
            // One update a minute is enough; the timeline stops with the view.
            TimelineView(.periodic(from: Date(), by: 1)) { ctx in
                VStack(alignment: .leading, spacing: 2) {
                    Text(ctx.date, style: .time).font(.system(size: 34, weight: .light)).monospacedDigit()
                    Text(ctx.date, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }
            }
        }
    }
}

private struct LauncherCalculatorTile: View {
    @State private var expression = ""

    var body: some View {
        TileCard(title: Text("Calculator")) {
            TextField("Expression", text: $expression).textFieldStyle(.plain).font(.system(size: 20, weight: .light))
            Text(verbatim: result).font(.system(size: 26, weight: .light)).monospacedDigit()
                .foregroundColor(.accentColor).lineLimit(1).minimumScaleFactor(0.5)
        }
    }

    private var result: String {
        guard let v = CalculatorEngine.evaluate(expression) else { return "" }
        return CalculatorEngine.format(v)
    }
}

private struct LauncherCountdownTile: View {
    @ObservedObject private var store = ProductivityServices.shared.countdowns

    var body: some View {
        TileCard(title: Text("Countdown")) {
            if store.events.isEmpty {
                Text("No events").font(.system(size: 12)).foregroundColor(.secondary)
            } else {
                ForEach(Array(store.events.prefix(3))) { e in
                    let days = e.daysRemaining(from: Date())
                    HStack {
                        Text(verbatim: e.label).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(verbatim: "\(days)").font(.system(size: 14, weight: .bold)).monospacedDigit()
                            .foregroundColor(days < 0 ? .secondary : .accentColor)
                    }
                }
            }
        }
    }
}

/// Newest items in Downloads. The folder is read when the tile first appears (the first read can raise the system's
/// folder-access prompt), never before.
private struct LauncherFilesTile: View {
    let onOpen: () -> Void
    @State private var items: [URL] = []

    var body: some View {
        TileCard(title: Text("Downloads")) {
            if items.isEmpty {
                Text("No Files").font(.system(size: 12)).foregroundColor(.secondary)
            } else {
                ForEach(items, id: \.self) { url in
                    Button {
                        NSWorkspace.shared.open(url)
                        onOpen()
                    } label: {
                        HStack(spacing: 6) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 16, height: 16)
                            Text(verbatim: url.lastPathComponent).font(.system(size: 12)).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear { items = Self.recentDownloads() }
    }

    private static func recentDownloads(limit: Int = 4) -> [URL] {
        guard let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first,
              let urls = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        else { return [] }
        func date(_ u: URL) -> Date { (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
        return Array(urls.sorted { date($0) > date($1) }.prefix(limit))
    }
}
