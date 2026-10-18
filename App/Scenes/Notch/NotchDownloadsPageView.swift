import AppKit
import SwiftUI

// Phase 33e addition — Page 4: Download Manager & Torrent Hub
// Bento Card A: Browser Downloads & In-Flight Transfers
// Bento Card B: Torrent & Direct URL Ingestion Hub (Magnet / .torrent / Direct HTTP)

struct NotchDownloadsPageView: View {
    @ObservedObject var feed: LiveActivityFeed
    @ObservedObject private var downloadService = DownloadManagerService.shared

    @State private var inputURLText: String = ""
    @State private var inputError: String? = nil
    @State private var successToast: String? = nil

    var body: some View {
        HStack(spacing: NotchDesignSpec.cardSpacing) {
            // Card A: Browser Downloads & In-Flight Transfers
            cardABrowserDownloads

            // Card B: Torrent & Link Ingestion Hub
            cardBTorrentIngestion
        }
        .onAppear {
            downloadService.retain()
        }
        .onDisappear {
            downloadService.release()
        }
    }

    // MARK: - Card A: Browser Downloads & In-Flight Transfers

    private var cardABrowserDownloads: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: Title & Total Down Throughput
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.green)
                    Text(verbatim: "IN-FLIGHT TRANSFERS")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                }

                Spacer()

                // Aggregate download speed badge
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 9, weight: .bold))
                    Text(verbatim: DownloadItem.formatBytes(downloadService.aggregateDownloadBps) + "/s")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(.green)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.green.opacity(0.15)))
            }

            // Transfer list
            let browserItems = downloadService.items.filter { $0.type == .browser || $0.type == .directUrl }
            if browserItems.isEmpty {
                VStack(spacing: 3) {
                    Spacer(minLength: 0)
                    Text(verbatim: "No Active Browser Downloads")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(verbatim: "Downloads from Safari or Chrome appear here live")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.25))
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(browserItems) { item in
                            browserItemRow(item)
                        }
                    }
                }
            }
        }
        .padding(NotchDesignSpec.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(NotchDesignSpec.cardFillOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(NotchDesignSpec.cardStrokeOpacity), lineWidth: NotchDesignSpec.cardStrokeWidth)
                )
        )
    }

    private func browserItemRow(_ item: DownloadItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // File type icon
                Image(systemName: fileIconName(for: item.name))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 16, height: 16)

                Text(verbatim: item.name)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 4)

                // Status or ETA badge
                if item.state == .completed {
                    Text(verbatim: "DONE")
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.green.opacity(0.15)))
                } else {
                    Text(verbatim: item.formattedETA)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                }

                // Row action buttons
                Button {
                    downloadService.revealInFinder(id: item.id)
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)

                if item.state == .active {
                    Button {
                        downloadService.pause(id: item.id)
                    } label: {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                } else if item.state == .paused {
                    Button {
                        downloadService.resume(id: item.id)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                        .frame(height: 4)
                    Capsule()
                        .fill(item.state == .completed ? Color.green : Color.mint)
                        .frame(width: max(4, geo.size.width * CGFloat(item.fraction)), height: 4)
                }
            }
            .frame(height: 4)

            // Subtitle stats (Bytes & Speed)
            HStack {
                Text(verbatim: item.formattedSizeProgress)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                if item.state == .active {
                    Text(verbatim: item.formattedSpeed)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.mint)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Card B: Torrent & Link Ingestion Hub

    private var cardBTorrentIngestion: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: Title & Total Up Throughput
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.cyan)
                    Text(verbatim: "TORRENT HUB")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                }

                Spacer()

                // Aggregate upload speed badge
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 9, weight: .bold))
                    Text(verbatim: DownloadItem.formatBytes(downloadService.aggregateUploadBps) + "/s")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(.cyan)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.cyan.opacity(0.15)))
            }

            // Input deck for magnet / direct URL paste
            inputBar

            // Feedback toast if present
            if let toast = successToast {
                Text(verbatim: toast)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.green)
                    .transition(.opacity)
            } else if let error = inputError {
                Text(verbatim: error)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }

            // Active Torrents List
            let torrentItems = downloadService.items.filter { $0.type == .torrent }
            if torrentItems.isEmpty {
                VStack(spacing: 3) {
                    Spacer(minLength: 0)
                    Text(verbatim: "No Active Torrents")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(verbatim: TorrentEngine.shared.isAvailable
                         ? "Paste a magnet link or .torrent URL above"
                         : "Install aria2 to download magnet links")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.25))
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(torrentItems) { item in
                            torrentItemRow(item)
                        }
                    }
                }
            }
        }
        .padding(NotchDesignSpec.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(NotchDesignSpec.cardFillOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(NotchDesignSpec.cardStrokeOpacity), lineWidth: NotchDesignSpec.cardStrokeWidth)
                )
        )
    }

    private func torrentItemRow(_ item: DownloadItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.cyan)

                Text(verbatim: item.name)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 4)

                // Swarm peers badge
                HStack(spacing: 3) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 8))
                    Text(verbatim: "\(item.seeders)S · \(item.peers)P")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(.cyan)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.cyan.opacity(0.15)))

                // Row action buttons
                Button {
                    downloadService.revealInFinder(id: item.id)
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)

                if item.state == .active || item.state == .initializing {
                    Button {
                        downloadService.pause(id: item.id)
                    } label: {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                } else if item.state == .paused {
                    Button {
                        downloadService.resume(id: item.id)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    downloadService.cancel(id: item.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.white.opacity(0.05)))
                }
                .buttonStyle(.plain)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                        .frame(height: 4)
                    Capsule()
                        .fill(LinearGradient(colors: [Color.cyan, Color.blue], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, geo.size.width * CGFloat(item.fraction)), height: 4)
                }
            }
            .frame(height: 4)

            // Subtitle stats (Progress & Speed)
            HStack {
                Text(verbatim: item.formattedSizeProgress)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                if item.state == .active {
                    HStack(spacing: 6) {
                        Text(verbatim: "↓ " + item.formattedSpeed)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.cyan)
                        Text(verbatim: "↑ " + DownloadItem.formatBytes(item.uploadSpeedBps) + "/s")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }

            // Why the engine refused to go on (a dead swarm, a bad magnet): shown, not swallowed.
            if case .failed(let reason) = item.state {
                Text(verbatim: reason)
                    .font(.system(size: 9))
                    .foregroundStyle(.red.opacity(0.85))
                    .lineLimit(1)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "link")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))

                TextField(
                    String(""),
                    text: $inputURLText,
                    prompt: Text(verbatim: "Paste a magnet, .torrent or https:// link")
                )
                .textFieldStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white)

                if !inputURLText.isEmpty {
                    Button {
                        inputURLText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        pasteFromClipboard()
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 10))
                            .foregroundStyle(.cyan)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
            )

            Button {
                submitLink()
            } label: {
                Text(verbatim: "Download")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.cyan))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func pasteFromClipboard() {
        if let string = NSPasteboard.general.string(forType: .string) {
            inputURLText = string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func submitLink() {
        inputError = nil
        successToast = nil
        let text = inputURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let success = downloadService.addDownload(input: text)
        if success {
            inputURLText = ""
            successToast = "Download queued successfully"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation { successToast = nil }
            }
        } else {
            inputError = text.lowercased().hasPrefix("magnet:") && !TorrentEngine.shared.isAvailable
                ? "Install aria2 to download magnet links"
                : "Only magnet, .torrent or http(s) links can be downloaded"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation { inputError = nil }
            }
        }
    }

    private func fileIconName(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "dmg", "iso", "img": return "opticaldisc.fill"
        case "zip", "tar", "gz", "7z", "bz2": return "doc.zipper"
        case "mp4", "mkv", "mov", "avi": return "film"
        case "mp3", "flac", "wav", "m4a": return "music.note"
        case "pdf": return "doc.text.fill"
        case "pkg", "app": return "shippingbox.fill"
        default: return "doc.fill"
        }
    }
}
