import SwiftUI

enum MusicPreviewPage: String, CaseIterable, Identifiable, Sendable {
    case nowPlaying
    case upNext
    case lyrics

    var id: String { rawValue }
}

/// D4: Tabbed Dock Music preview popover (`Now Playing` / `Upcoming` / `Lyrics`),
/// sharing `MusicQueueFetcher` with the Lock Screen music card (`L2`).
struct MusicPreviewTabsView: View {
    let state: NowPlayingState
    let isLiked: Bool
    let onTogglePlay: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSeek: (Double) -> Void
    let onToggleLike: () -> Void
    let onShare: () -> Void

    @AppStorage("com.katikati.music.previewPage") private var pageRaw = MusicPreviewPage.nowPlaying.rawValue
    @ObservedObject private var lyricsStore = LyricsStore.shared
    @ObservedObject private var queueFetcher = MusicQueueFetcher.shared
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var page: MusicPreviewPage {
        MusicPreviewPage(rawValue: pageRaw) ?? .nowPlaying
    }

    var body: some View {
        let hasTrack = !(state.title?.isEmpty ?? true)
        DockPreviewCard {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Now Playing", selection: $pageRaw) {
                    Text("Now Playing").tag(MusicPreviewPage.nowPlaying.rawValue)
                    Text("Upcoming").tag(MusicPreviewPage.upNext.rawValue)
                    Text("Lyrics").tag(MusicPreviewPage.lyrics.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch page {
                case .nowPlaying:
                    nowPlayingTab(hasTrack: hasTrack)
                case .upNext:
                    upNextTab
                case .lyrics:
                    lyricsTab(hasTrack: hasTrack)
                }
            }
            .frame(minWidth: 270)
        }
        .onReceive(timer) { now = $0 }
        .onAppear {
            syncPageData(for: page)
        }
        .onChange(of: pageRaw) { _, _ in
            syncPageData(for: page)
        }
        .onChange(of: state.title) { _, _ in
            syncPageData(for: page)
        }
    }

    private func syncPageData(for current: MusicPreviewPage) {
        if current == .lyrics {
            lyricsStore.loadIfNeeded(title: state.title, artist: state.artist)
        } else if current == .upNext {
            queueFetcher.refreshIfNeeded(appName: state.appName, currentTitle: state.title, allowAppleScript: true)
        }
    }

    private func nowPlayingTab(hasTrack: Bool) -> some View {
        let title = hasTrack ? (state.title ?? "") : String(localized: "Not Playing")
        let artist = state.artist ?? state.appName ?? ""
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Group {
                    if let data = state.artworkData, let img = NSImage(data: data) {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.white.opacity(0.1)
                            .overlay(Image(systemName: "music.note").font(.title3).foregroundStyle(.white.opacity(0.7)))
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                    if !artist.isEmpty {
                        Text(verbatim: artist).dockCaption()
                    }
                    if let album = state.album, !album.isEmpty {
                        Text(verbatim: album)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            if let progress = state.progress(at: now), let duration = state.duration, duration > 0 {
                VStack(spacing: 4) {
                    Slider(
                        value: Binding(get: { progress * duration }, set: { onSeek($0) }),
                        in: 0...duration
                    )
                    .controlSize(.mini)
                    HStack {
                        Text(verbatim: NotchLayoutSpec.clockText(progress * duration))
                        Spacer()
                        Text(verbatim: NotchLayoutSpec.clockText(duration))
                    }
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 14) {
                Button(action: onToggleLike) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .foregroundStyle(isLiked ? Color.green : Color.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .disabled(!hasTrack)

                Spacer()

                Button(action: onPrevious) { Image(systemName: "backward.fill") }
                    .buttonStyle(.plain)
                Button(action: onTogglePlay) {
                    Image(systemName: state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 26))
                }
                .buttonStyle(.plain)
                Button(action: onNext) { Image(systemName: "forward.fill") }
                    .buttonStyle(.plain)

                Spacer()

                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .disabled(!hasTrack)
            }
            .font(.system(size: 13, weight: .semibold))
        }
    }

    private var upNextTab: some View {
        let model = MusicSurfaceConfig.queueModel()
        let sections = model.sections(upcoming: queueFetcher.upcoming, favorites: [])
        return VStack(alignment: .leading, spacing: 8) {
            if queueFetcher.isLoading && sections.isEmpty {
                ProgressView().controlSize(.small)
            } else if sections.isEmpty {
                Text("Nothing played yet")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(sections) { section in
                            Text(section.kind == .upcoming ? "Upcoming" : "History")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            ForEach(section.entries.prefix(6)) { entry in
                                HStack(spacing: 8) {
                                    Image(systemName: "music.note")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(verbatim: entry.title)
                                            .font(.system(size: 11.5, weight: .medium))
                                            .lineLimit(1)
                                        if let artist = entry.artist, !artist.isEmpty {
                                            Text(verbatim: artist)
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150)
            }
        }
    }

    private func lyricsTab(hasTrack: Bool) -> some View {
        let lines = hasTrack ? lyricsStore.lines(title: state.title, artist: state.artist) : []
        return Group {
            if lines.isEmpty {
                Text("No lyrics cached. Enable synced lyrics in Now Playing settings to fetch.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(lines.prefix(16).enumerated()), id: \.offset) { _, line in
                            Text(verbatim: line.text)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.white.opacity(0.86))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150)
            }
        }
    }
}
