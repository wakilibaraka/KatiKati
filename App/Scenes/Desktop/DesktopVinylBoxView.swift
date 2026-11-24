import AppKit
import CoreImage
import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// One shared system-wide now-playing reader for every music surface (created on first use).
@MainActor
enum DesktopWidgetServices {
    static let nowPlaying = NowPlayingService.shared
}

// MARK: - Favourites (KatiKati-local, never a pretend player API)

/// The only player-agnostic "favourite" that exists: a local set keyed by track, shared by the desktop
/// widget, the lock-screen card, and the notch.
@MainActor
final class MusicFavorites: ObservableObject {
    static let shared = MusicFavorites()

    @Published private(set) var keys: Set<String>

    private init() {
        let stored = UserDefaults.standard.stringArray(forKey: MusicSurfaceConfig.favoritesKey) ?? []
        keys = Set(stored)
    }

    static func key(title: String?, artist: String?) -> String? {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        return "\(title.lowercased())|\(artist?.lowercased() ?? "")"
    }

    func contains(title: String?, artist: String?) -> Bool {
        guard let key = Self.key(title: title, artist: artist) else { return false }
        return keys.contains(key)
    }

    func toggle(title: String?, artist: String?) {
        guard let key = Self.key(title: title, artist: artist) else { return }
        if keys.contains(key) { keys.remove(key) } else { keys.insert(key) }
        UserDefaults.standard.set(Array(keys).sorted(), forKey: MusicSurfaceConfig.favoritesKey)
    }

    /// Favourites are stored as `title|artist`; the queue drawer needs them as rows again.
    var entries: [MusicQueueEntry] {
        keys.compactMap { key in
            let parts = key.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            guard let title = parts.first, !title.isEmpty else { return nil }
            let artist = parts.count > 1 ? String(parts[1]) : ""
            return MusicQueueEntry(title: String(title), artist: artist.isEmpty ? nil : artist)
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}

// MARK: - Small pieces

/// Right-aligned equaliser bars. `scaleY` only, paused whenever nothing is playing or motion is reduced.
/// The five-bar waveform. Core Animation on the render server: a playing card costs no per-frame CPU, and a
/// paused one is a frozen layer. (A SwiftUI `TimelineView` here re-rendered the whole glass card eight times
/// a second, which measured as double-digit idle CPU.)
struct MusicWaveformView: NSViewRepresentable {
    var isPlaying: Bool
    var tint: Color
    var barCount: Int = 5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeNSView(context: Context) -> WaveformLayerView {
        let view = WaveformLayerView()
        view.apply(bars: barCount, tint: NSColor(tint),
                   animating: isPlaying && !reduceMotion && !reduceTransparency)
        return view
    }

    func updateNSView(_ view: WaveformLayerView, context: Context) {
        view.apply(bars: barCount, tint: NSColor(tint),
                   animating: isPlaying && !reduceMotion && !reduceTransparency)
    }

    final class WaveformLayerView: NSView {
        private var bars: [CALayer] = []
        private var barCount = 0

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.masksToBounds = false
        }

        required init?(coder: NSCoder) { nil }

        func apply(bars count: Int, tint: NSColor, animating: Bool) {
            if barCount != count || bars.isEmpty {
                barCount = count
                rebuild(count: count, tint: tint)
            } else {
                bars.forEach { $0.backgroundColor = tint.withAlphaComponent(0.85).cgColor }
            }
            layer?.speed = animating ? 1 : 0
            isHidden = count == 0
        }

        override func layout() {
            super.layout()
            let spacing: CGFloat = 2
            let width: CGFloat = 2.5
            let total = CGFloat(barCount) * width + CGFloat(max(barCount - 1, 0)) * spacing
            var x = bounds.width - total
            for bar in bars {
                bar.frame = CGRect(x: x, y: (bounds.height - 14) / 2, width: width, height: 14)
                x += width + spacing
            }
        }

        private func rebuild(count: Int, tint: NSColor) {
            bars.forEach { $0.removeFromSuperlayer() }
            bars = (0..<count).map { _ in
                let bar = CALayer()
                bar.backgroundColor = tint.withAlphaComponent(0.85).cgColor
                bar.cornerRadius = 1.25
                layer?.addSublayer(bar)
                return bar
            }
            needsLayout = true
            for (index, bar) in bars.enumerated() {
                let pulse = CABasicAnimation(keyPath: "transform.scale.y")
                pulse.fromValue = 0.3
                pulse.toValue = 1.0
                pulse.duration = 0.42 + Double(index) * 0.07
                pulse.autoreverses = true
                pulse.repeatCount = .infinity
                pulse.timeOffset = Double(index) * 0.13
                pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                bar.add(pulse, forKey: "pulse")
            }
        }
    }
}

enum MusicTimecode {
    static func elapsed(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func remaining(elapsed: TimeInterval, duration: TimeInterval?) -> String {
        guard let duration, duration.isFinite, duration > 0 else { return "--:--" }
        let left = Int(max(0, duration - max(0, elapsed)).rounded(.up))
        return "-" + String(format: "%d:%02d", left / 60, left % 60)
    }
}

/// Scrubbable progress with `1:52` / `-1:52` labels. Dragging seeks optimistically through the service.
/// `MusicScrubberStyle` changes only what is drawn — the gesture, labels and seek path are identical.
struct MusicScrubControl: View {
    let state: NowPlayingState
    var tint: Color
    var style: MusicScrubberStyle = .slim
    var labelColor: Color = .white
    let onSeek: (TimeInterval) -> Void

    @State private var dragFraction: Double?

    private func progress(at now: Date) -> Double {
        if let dragFraction { return dragFraction }
        guard let duration = state.duration, duration > 0 else { return 0 }
        return NowPlayingProgress.fraction(at: now, elapsed: state.elapsed, asOf: state.elapsedAsOf,
                                           rate: state.rate, duration: duration) ?? 0
    }

    private func elapsed(at now: Date) -> TimeInterval {
        guard let duration = state.duration, duration > 0 else { return state.elapsed ?? 0 }
        return progress(at: now) * duration
    }

    var body: some View {
        // Half-second ticks only while playing; a paused card schedules nothing.
        TimelineView(.animation(minimumInterval: 0.5, paused: !state.isPlaying || dragFraction != nil)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let progress = progress(at: now)
        let elapsed = elapsed(at: now)
        return VStack(spacing: 4) {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                ZStack(alignment: .leading) {
                    track(progress: progress, width: width)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragFraction = min(max(Double(value.location.x / width), 0), 1)
                        }
                        .onEnded { _ in
                            guard let fraction = dragFraction, let duration = state.duration, duration > 0 else {
                                dragFraction = nil
                                return
                            }
                            onSeek(fraction * duration)
                            dragFraction = nil
                        }
                )
                .accessibilityLabel(Text("Playback Position"))
            }
            .frame(height: 14)

            if style != .waveform {
                HStack {
                    Text(verbatim: MusicTimecode.elapsed(elapsed))
                    Spacer(minLength: 0)
                    Text(verbatim: MusicTimecode.remaining(elapsed: elapsed, duration: state.duration))
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(labelColor.opacity(0.55))
            }
        }
    }

    @ViewBuilder
    private func track(progress: Double, width: CGFloat) -> some View {
        switch style {
        case .pill:
            ZStack(alignment: .leading) {
                Capsule().fill(labelColor.opacity(0.22)).frame(height: 5)
                Capsule().fill(tint).frame(width: CGFloat(progress) * width, height: 5)
                Circle().fill(labelColor)
                    .frame(width: 11, height: 11)
                    .offset(x: max(0, min(width - 11, CGFloat(progress) * width - 5.5)))
            }
        case .slim:
            ZStack(alignment: .leading) {
                Capsule().fill(labelColor.opacity(0.18)).frame(height: 3)
                Capsule().fill(tint).frame(width: CGFloat(progress) * width, height: 3)
                Circle().fill(labelColor)
                    .frame(width: 9, height: 9)
                    .offset(x: max(0, min(width - 9, CGFloat(progress) * width - 4.5)))
            }
        case .dotted:
            let count = style.barCount
            HStack(spacing: 2) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(Double(index) / Double(count) <= progress ? tint : labelColor.opacity(0.16))
                        .frame(maxWidth: .infinity)
                        .frame(height: 4)
                }
            }
        case .waveform:
            // Seeded heights: the same track draws the same shape on every surface and every launch.
            let heights = style.heights(title: state.title, artist: state.artist)
            HStack(alignment: .center, spacing: 1.5) {
                ForEach(heights.indices, id: \.self) { index in
                    Capsule()
                        .fill(Double(index) / Double(max(heights.count, 1)) <= progress
                              ? tint : labelColor.opacity(0.16))
                        .frame(width: 2, height: max(3, heights[index] * 12))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One configurable slot button. A nil slot keeps its space so the transport row never jumps.
struct MusicSlotView: View {
    let slot: MusicControlSlot?
    var isActive: Bool = false
    var textColor: Color = .white
    let action: (MusicControlSlot) -> Void

    var body: some View {
        Group {
            if let slot {
                Button { action(slot) } label: {
                    Image(systemName: slot.symbolName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isActive ? Color.accentColor : textColor.opacity(0.75))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(slot.title))
            } else {
                Color.clear.frame(width: 26, height: 26)
            }
        }
    }
}

// MARK: - Output + AirPods popover

struct MusicOutputPopover: View {
    let tint: Color
    var onPlayLocalFile: (() -> Void)?
    @State private var devices: [AudioOutputDevice] = []
    @State private var volume: Double = 0
    @State private var pods: [BluetoothDevice] = []
    @State private var listeningMode: String?
    @State private var canSetMode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Slider(value: Binding(get: { volume },
                                      set: { volume = $0; AudioOutputSwitcher.setOutputVolume($0) }),
                       in: 0...1)
                Text(verbatim: "\(Int((volume * 100).rounded()))")
                    .font(.system(size: 10, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)
            }

            Divider()

            ForEach(devices) { device in
                Button {
                    AudioOutputSwitcher.setDefault(device.id)
                    refresh()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: device.isDefault ? "checkmark" : "circle")
                            .font(.system(size: 9))
                            .foregroundStyle(device.isDefault ? Color.accentColor : .secondary)
                        Text(verbatim: device.name).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
            }

            if let pod = pods.first(where: { $0.isConnected && $0.isAudioPeripheral }) ?? pods.first {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: pod.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 10) {
                        if let level = pod.batteryLeft { battery("L", level) }
                        if let level = pod.batteryRight { battery("R", level) }
                        if let level = pod.batteryCase { battery("Case", level) }
                    }
                }
            }

            if let listeningMode {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Listening Mode").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    if canSetMode {
                        HStack(spacing: 6) {
                            ForEach(BluetoothListeningMode.allCases) { mode in
                                Button {
                                    _ = AudioOutputSwitcher.setBluetoothListeningMode(mode.rawValue)
                                    self.listeningMode = AudioOutputSwitcher.bluetoothListeningMode()
                                } label: {
                                    Image(systemName: mode.symbolName)
                                        .font(.system(size: 11))
                                        .foregroundStyle(mode.rawValue == listeningMode ? Color.accentColor : .secondary)
                                        .frame(width: 24, height: 20)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help(Text(mode.title))
                            }
                        }
                    } else {
                        Text(verbatim: modeName(listeningMode))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let onPlayLocalFile {
                Divider()
                Button(action: onPlayLocalFile) {
                    Label {
                        Text("Play Local File…")
                    } icon: {
                        Image(systemName: "music.note.list")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(tint)
            }
        }
        .padding(12)
        .frame(width: 230)
        .onAppear(perform: refresh)
    }

    private func battery(_ label: String, _ level: Int) -> some View {
        HStack(spacing: 3) {
            Text(verbatim: label).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            Text(verbatim: "\(level)%").font(.system(size: 10, design: .rounded)).monospacedDigit()
        }
    }

    private func modeName(_ raw: String) -> String {
        BluetoothListeningMode(rawValue: raw)?.title ?? raw
    }

    private func refresh() {
        devices = AudioOutputSwitcher.devices()
        volume = AudioOutputSwitcher.outputVolume() ?? 0
        listeningMode = AudioOutputSwitcher.bluetoothListeningMode()
        canSetMode = AudioOutputSwitcher.canSetBluetoothListeningMode()
        Task {
            let found = await BluetoothDeviceReader.read()
            await MainActor.run { self.pods = found }
        }
    }
}

// MARK: - Lyrics

struct MusicLyricsDrawer: View {
    let lines: [LyricsLine]
    let elapsed: TimeInterval
    var tint: Color

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        let active = LyricTimelineMatcher.activeIndex(in: lines, at: elapsed) == index
                        Text(verbatim: line.text)
                            .font(.system(size: active ? 12 : 11, weight: active ? .semibold : .regular))
                            .foregroundStyle(active ? Color.white : Color.white.opacity(0.42))
                            .id(index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: LyricTimelineMatcher.activeIndex(in: lines, at: elapsed)) { _, index in
                guard let index else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }
}

// MARK: - Glass card (shared by the lock screen and the desktop)

struct MusicGlassCardView: View {
    @ObservedObject var service: NowPlayingService
    /// §5.7 shared design system: the same card renders for the desktop widget and the lock screen.
    var theme: MusicSurfaceTheme = .semiGlass
    var layout: MusicCardLayout = .full
    var scrubber: MusicScrubberStyle = .slim
    var palette: MusicArtworkPalette = .fallback
    var assignment: MusicControlAssignment = MusicControlAssignment()
    var capabilities: MusicControlCapabilities = .standard
    var showsChrome: Bool = true
    /// The lock-screen card can drop the volume row; the desktop widget always keeps it.
    var showsVolumeRow: Bool = true
    var onToggleMode: (() -> Void)?
    var onStash: (() -> Void)?
    var onPlayLocalFile: (() -> Void)?

    @ObservedObject private var favorites = MusicFavorites.shared
    @ObservedObject private var lyricsStore = LyricsStore.shared
    @ObservedObject private var localPlayer = LocalAudioPlayer.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showLyrics = false
    @State private var showOutput = false
    @State private var volumeHUD: Double?

    // Atmospheric: Now Playing / Synced Lyrics / Queue-History, remembered per surface.
    @State private var viewMode: MusicViewMode = MusicSurfaceConfig.viewMode()
    @State private var lyricsExpanded = false
    @State private var showRomanization = false
    @State private var showTranslation = false
    @State private var translatedLines: [String: String] = [:]
    @State private var volumePosition: Double = 0.5
    @State private var deviceName: String?
    @State private var queue = MusicSurfaceConfig.queueModel()

    /// ML-6: a local file takes over the same card while it is loaded; otherwise the system player speaks.
    private var state: NowPlayingState { localPlayer.isActive ? localPlayer.state : service.state }

    private func playPause() {
        if localPlayer.isActive { localPlayer.togglePlayPause() } else { service.togglePlayPause() }
    }

    private func seek(to time: TimeInterval) {
        if localPlayer.isActive { localPlayer.seek(to: time) } else { service.seek(to: time) }
    }
    private var accent: Color {
        Color(red: palette.accent.r, green: palette.accent.g, blue: palette.accent.b)
    }
    private var textColor: Color { theme.isDark ? .white : .black }

    private var elapsed: TimeInterval {
        guard let duration = state.duration, duration > 0 else { return state.elapsed ?? 0 }
        return (NowPlayingProgress.fraction(at: Date(), elapsed: state.elapsed, asOf: state.elapsedAsOf,
                                            rate: state.rate, duration: duration) ?? 0) * duration
    }

    private var lyricLines: [LyricsLine] { lyricsStore.lines(title: state.title, artist: state.artist) }

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, layout == .slim ? 8 : 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(background)
            .overlay(rim)
            .overlay(alignment: .trailing) { edgeVolumeBand }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onAppear {
                lyricsStore.loadIfNeeded(title: state.title, artist: state.artist)
                refreshDeviceName()
                recordHistory()
            }
            .onChange(of: state.title) { _, _ in
                lyricsStore.loadIfNeeded(title: state.title, artist: state.artist)
                if showLyrics { showLyrics = lyricLines.isEmpty ? false : showLyrics }
                translatedLines = [:]
                lyricsExpanded = false
                refreshDeviceName()
                recordHistory()
            }
            .onChange(of: viewMode) { _, mode in
                if mode != .lyrics { lyricsExpanded = false }
                if mode == .nowPlaying || mode == .queue { refreshDeviceName() }
            }
            .popover(isPresented: $showOutput, arrowEdge: .bottom) {
                MusicOutputPopover(tint: accent, onPlayLocalFile: onPlayLocalFile)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .slim:
            VStack(alignment: .leading, spacing: 6) {
                header
                slimRow
            }
        case .full:
            switch viewMode {
            case .nowPlaying:
                nowPlayingBody
            case .lyrics:
                lyricsBody
            case .queue:
                queueBody
            }
        case .hero:
            HStack(alignment: .top, spacing: 12) {
                artwork
                VStack(alignment: .leading, spacing: 8) {
                    header
                    heroLyrics
                    MusicScrubControl(state: state, tint: accent, style: scrubber,
                                      labelColor: textColor) { seek(to: $0) }
                    transportRow
                }
            }
        }
    }

    // MARK: Atmospheric (Full-Bleed) — the three views

    private var nowPlayingBody: some View {
        VStack(alignment: .leading, spacing: 9) {
            atmosphericHeader
            Spacer(minLength: 0)
            MusicScrubControl(state: state, tint: accent, style: scrubber,
                              labelColor: textColor) { seek(to: $0) }
            transportRow
            if showsVolumeRow { volumeRow }
            modeBar
            if let deviceName, !deviceName.isEmpty {
                Text(verbatim: deviceName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(textColor.opacity(0.5))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Title + translucent artist on the left, the two circular glass pills on the right.
    private var atmosphericHeader: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: state.title ?? String(localized: "Not Playing"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                if let artist = state.artist, !artist.isEmpty {
                    Text(verbatim: artist)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(textColor.opacity(theme.secondaryTextOpacity))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            glassPill("star" + (isFavoriteSlot(.favorite) ? ".fill" : ""),
                      active: isFavoriteSlot(.favorite),
                      label: String(localized: "Favorite")) {
                favorites.toggle(title: state.title, artist: state.artist)
            }
            glassPill("ellipsis", active: showOutput,
                      label: String(localized: "More")) { showOutput.toggle() }
        }
    }

    private func glassPill(_ symbol: String, active: Bool, label: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? accent : textColor.opacity(0.85))
                .frame(width: 26, height: 26)
                .background(textColor.opacity(0.14), in: Circle())
                .overlay(Circle().strokeBorder(textColor.opacity(0.12), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
    }

    /// Full-width volume with the perceptual curve in both directions.
    private var volumeRow: some View {
        HStack(spacing: 8) {
            Image(systemName: volumePosition <= 0.001 ? "speaker.slash.fill" : "speaker.fill")
                .font(.system(size: 9))
                .foregroundStyle(textColor.opacity(0.6))
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(textColor.opacity(0.18)).frame(height: 3)
                    Capsule().fill(textColor.opacity(0.85))
                        .frame(width: CGFloat(volumePosition) * width, height: 3)
                    Circle().fill(textColor)
                        .frame(width: 7, height: 7)
                        .offset(x: max(0, min(width - 7, CGFloat(volumePosition) * width - 3.5)))
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let next = min(max(Double(value.location.x / width), 0), 1)
                            volumePosition = next
                            _ = AudioOutputSwitcher.setOutputVolume(MusicVolumeCurve.gain(forPosition: next))
                        }
                )
            }
            .frame(height: 12)
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 9))
                .foregroundStyle(textColor.opacity(0.6))
        }
        .accessibilityLabel(Text("Volume"))
    }

    /// Lyrics | Output | Queue, with the active output device named underneath.
    private var modeBar: some View {
        HStack(spacing: 8) {
            modeButton("quote.bubble", active: viewMode == .lyrics, label: String(localized: "Lyrics")) {
                setViewMode(viewMode == .lyrics ? .nowPlaying : .lyrics)
            }
            modeButton("airplayaudio", active: showOutput, label: String(localized: "Output")) {
                showOutput.toggle()
            }
            modeButton("list.bullet", active: viewMode == .queue, label: String(localized: "Queue")) {
                setViewMode(viewMode == .queue ? .nowPlaying : .queue)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func modeButton(_ symbol: String, active: Bool, label: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? textColor : textColor.opacity(0.55))
                .frame(width: 32, height: 24)
                .background(textColor.opacity(active ? 0.16 : 0), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
    }

    private func setViewMode(_ mode: MusicViewMode) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { viewMode = mode }
        MusicSurfaceConfig.saveViewMode(mode)
    }

    // MARK: Synced lyrics

    private var lyricsBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            miniHeader
            lyricsScroll
                .frame(maxHeight: .infinity)
            if showTranslation, !lyricLines.isEmpty {
                translationHost
            }
            if !lyricsExpanded {
                modeBar
            }
            HStack(spacing: 4) {
                Text(verbatim: "Lyrics by lrclib.net")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(textColor.opacity(0.38))
                Spacer(minLength: 0)
                if MusicRomanizer.supports(lyricLines.map(\.text).joined(separator: " ")) {
                    pillToggle("globe", on: showRomanization, label: String(localized: "Romanization")) {
                        showRomanization.toggle()
                    }
                }
                pillToggle("character.bubble", on: showTranslation, label: String(localized: "Translate")) {
                    showTranslation.toggle()
                }
            }
        }
    }

    private var lyricLinesActive: Int {
        guard !lyricLines.isEmpty else { return 0 }
        return lyricLines.lastIndex { $0.time <= elapsed + 0.1 } ?? 0
    }

    private var lyricsScroll: some View {
        let active = lyricLinesActive
        return ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    if lyricLines.isEmpty {
                        Text("No synced lyrics for this track")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(textColor.opacity(0.5))
                            .padding(.top, 8)
                    }
                    ForEach(Array(lyricLines.enumerated()), id: \.offset) { index, line in
                        Text(verbatim: displayLine(line.text))
                            .font(.system(size: index == active ? 15 : 13,
                                          weight: index == active ? .bold : .medium))
                            .foregroundStyle(textColor.opacity(index == active ? 0.98 : 0.34))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .padding(.vertical, 10)
            }
            .mask(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.10),
                    .init(color: .black, location: 0.86),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            )
            .onChange(of: active) { _, index in
                guard !lyricsExpanded else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(index, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(active, anchor: .center) }
        }
    }

    private func displayLine(_ raw: String) -> String {
        if showTranslation, let translated = translatedLines[raw], !translated.isEmpty {
            return translated
        }
        if showRomanization, let latin = MusicRomanizer.romanize(raw) { return latin }
        return raw
    }

    private func pillToggle(_ symbol: String, on: Bool, label: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(on ? Color.black.opacity(0.8) : textColor.opacity(0.75))
                .frame(width: 22, height: 22)
                .background(on ? textColor.opacity(0.9) : textColor.opacity(0.14), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
    }

    /// Reuses the same Translation framework pass `TranslateCardView` uses; the host is zero-sized and only
    /// present while the 文A pill is on.
    @ViewBuilder
    private var translationHost: some View {
        if #available(macOS 15.0, *) {
            MusicLyricsTranslationHost(lines: lyricLines.map(\.text)) { translated in
                translatedLines = translated
            } content: {
                Color.clear.frame(width: 0, height: 0)
            }
        }
    }

    private var miniHeader: some View {
        HStack(spacing: 8) {
            if let data = state.artworkData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(accent.opacity(0.35))
                    .frame(width: 30, height: 30)
                    .overlay(Image(systemName: "music.note").font(.system(size: 11)))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: state.title ?? String(localized: "Not Playing"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                if let artist = state.artist, !artist.isEmpty {
                    Text(verbatim: artist)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(textColor.opacity(0.5))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            glassPill("star" + (isFavoriteSlot(.favorite) ? ".fill" : ""),
                      active: isFavoriteSlot(.favorite),
                      label: String(localized: "Favorite")) {
                favorites.toggle(title: state.title, artist: state.artist)
            }
            glassPill(lyricsExpanded ? "chevron.down" : "arrow.up.left.and.arrow.down.right",
                      active: lyricsExpanded,
                      label: String(localized: "Synced Lyrics")) {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { lyricsExpanded.toggle() }
            }
        }
    }

    // MARK: Queue / History

    private var queueBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            miniHeader
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    let sections = queue.sections(favorites: favorites.entries)
                    if sections.isEmpty {
                        Text("Nothing played yet")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(textColor.opacity(0.5))
                            .padding(.top, 8)
                    }
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: section.kind.symbolName).font(.system(size: 8))
                                Text(verbatim: queueTitle(section.kind))
                                    .font(.system(size: 9, weight: .semibold))
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(textColor.opacity(0.45))
                            ForEach(section.entries) { entry in
                                queueRow(entry)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: .infinity)
            segmentedControls
            modeBar
        }
    }

    private func queueTitle(_ kind: MusicQueueKind) -> String {
        switch kind {
        case .upcoming: return String(localized: "Upcoming")
        case .history: return String(localized: "History")
        case .favorites: return String(localized: "Favorites")
        }
    }

    private func queueRow(_ entry: MusicQueueEntry) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(accent.opacity(0.4))
                .frame(width: 20, height: 20)
                .overlay(Image(systemName: "music.note").font(.system(size: 8)).foregroundStyle(textColor.opacity(0.8)))
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: entry.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                if let artist = entry.artist, !artist.isEmpty {
                    Text(verbatim: artist)
                        .font(.system(size: 9))
                        .foregroundStyle(textColor.opacity(0.5))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button { favorites.toggle(title: entry.title, artist: entry.artist) } label: {
                Image(systemName: favorites.contains(title: entry.title, artist: entry.artist) ? "star.fill" : "star")
                    .font(.system(size: 9))
                    .foregroundStyle(textColor.opacity(0.55))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Favorite"))
        }
    }

    private var segmentedControls: some View {
        HStack(spacing: 4) {
            segment(String(localized: "Shuffle"), symbol: "shuffle", on: queue.isShuffled) {
                queue.isShuffled.toggle(); MusicSurfaceConfig.saveQueueModel(queue)
            }
            segment(String(localized: "Repeat"), symbol: "repeat", on: queue.repeatsTrack) {
                queue.repeatsTrack.toggle(); MusicSurfaceConfig.saveQueueModel(queue)
            }
            segment(String(localized: "Autoplay"), symbol: "infinity", on: queue.autoplay) {
                queue.autoplay.toggle(); MusicSurfaceConfig.saveQueueModel(queue)
            }
        }
        .padding(2)
        .background(textColor.opacity(0.10), in: Capsule())
    }

    private func segment(_ label: String, symbol: String, on: Bool,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                Text(verbatim: label).font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(on ? textColor : textColor.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(textColor.opacity(on ? 0.16 : 0), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
    }

    private func refreshDeviceName() {
        Task.detached(priority: .utility) {
            let name = AudioOutputSwitcher.cachedDefaultOutputName()
            let gain = AudioOutputSwitcher.outputVolume()
            await MainActor.run {
                deviceName = name
                if let gain { volumePosition = MusicVolumeCurve.position(forGain: gain) }
            }
        }
    }

    private func recordHistory() {
        queue.record(title: state.title, artist: state.artist)
        MusicSurfaceConfig.saveQueueModel(queue)
    }

    // MARK: pieces

    private var artwork: some View {
        Group {
            if let data = state.artworkData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [accent.opacity(0.35), Color.black.opacity(0.35)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(textColor.opacity(0.55))
                    }
            }
        }
        .frame(width: layout.artworkSide, height: layout.artworkSide)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(textColor.opacity(0.12), lineWidth: 0.75)
        }
        .accessibilityLabel(Text("Album Artwork"))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: state.title ?? String(localized: "Not Playing"))
                    .font(.system(size: layout == .slim ? 12 : 14, weight: .bold))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                if let artist = state.artist, !artist.isEmpty {
                    Text(verbatim: artist)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(textColor.opacity(theme.secondaryTextOpacity))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if layout != .hero {
                MusicWaveformView(isPlaying: state.isPlaying, tint: accent)
            }
            if showsChrome, let onStash {
                Button(action: onStash) {
                    Image(systemName: "rectangle.righthalf.inset.filled.arrow.right")
                        .font(.system(size: 10))
                        .foregroundStyle(textColor.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Tuck Away"))
            }
        }
    }

    /// Mooziac's three-line treatment: previous faded, active bold, next faded. One line each, so the card
    /// never grows mid-song.
    @ViewBuilder
    private var heroLyrics: some View {
        if lyricLines.isEmpty {
            Color.clear.frame(height: 44)
        } else {
            VStack(spacing: 2) {
                ForEach(Array(heroLyricWindow.enumerated()), id: \.offset) { _, entry in
                    Text(verbatim: entry.text)
                        .font(.system(size: entry.isActive ? 12.5 : 10.5,
                                      weight: entry.isActive ? .bold : .medium))
                        .foregroundStyle(textColor.opacity(entry.isActive ? 0.95 : 0.34))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .frame(height: 44)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: heroLyricWindow.map(\.text))
        }
    }

    private var heroLyricWindow: [(text: String, isActive: Bool)] {
        guard !lyricLines.isEmpty else { return [] }
        let index = lyricLines.lastIndex { $0.time <= elapsed + 0.1 } ?? 0
        var window: [(Int, Bool)] = []
        if index > 0 { window.append((index - 1, false)) }
        window.append((index, true))
        if index + 1 < lyricLines.count { window.append((index + 1, false)) }
        return window.map { (lyricLines[$0.0].text, $0.1) }
    }

    private var slimRow: some View {
        HStack(spacing: 10) {
            MusicSlotView(slot: resolved.left, isActive: isFavoriteSlot(resolved.left), textColor: textColor, action: perform)
            Button { playPause() } label: {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(textColor)
                    .frame(width: 30, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state.isPlaying ? Text("Pause") : Text("Play"))
            Spacer(minLength: 0)
            MusicSlotView(slot: resolved.right, isActive: isFavoriteSlot(resolved.right), textColor: textColor, action: perform)
        }
    }

    private var transportRow: some View {
        HStack(spacing: 0) {
            MusicSlotView(slot: resolved.left, isActive: isFavoriteSlot(resolved.left), textColor: textColor, action: perform)
            Spacer(minLength: 0)
            Button { service.previousTrack() } label: { transportGlyph("backward.fill", size: 14) }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Previous"))
            Spacer(minLength: 12)
            Button { playPause() } label: {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(textColor)
                    .frame(width: 38, height: 30)
                    .background(Circle().fill(textColor.opacity(0.14)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state.isPlaying ? Text("Pause") : Text("Play"))
            Spacer(minLength: 12)
            Button { service.nextTrack() } label: { transportGlyph("forward.fill", size: 14) }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Next"))
            Spacer(minLength: 0)
            MusicSlotView(slot: resolved.right, isActive: isFavoriteSlot(resolved.right), textColor: textColor, action: perform)
        }
    }

    private func transportGlyph(_ name: String, size: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(textColor.opacity(0.8))
            .frame(width: 28, height: 26)
            .contentShape(Rectangle())
    }

    private func isFavoriteSlot(_ slot: MusicControlSlot?) -> Bool {
        slot == .favorite && favorites.contains(title: state.title, artist: state.artist)
    }

    private var resolved: (left: MusicControlSlot?, right: MusicControlSlot?) {
        assignment.resolved(capabilities)
    }

    private func perform(_ slot: MusicControlSlot) {
        switch slot {
        case .lyrics:
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { showLyrics.toggle() }
        case .favorite:
            favorites.toggle(title: state.title, artist: state.artist)
        case .output:
            showOutput.toggle()
        case .copy:
            let text = [state.title, state.artist].compactMap { $0 }.joined(separator: " — ")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case .shuffle, .repeatTrack:
            break
        }
    }

    /// ML-6 — a 3 pt band on the trailing edge: vertical travel over the card is volume, with a HUD while
    /// dragging and nothing scheduled when the finger is up.
    private var edgeVolumeBand: some View {
        ZStack {
            if let volumeHUD {
                VStack(spacing: 4) {
                    Image(systemName: volumeHUD == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 9))
                    Text(verbatim: "\(Int((volumeHUD * 100).rounded()))")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(textColor.opacity(0.9))
                .padding(.horizontal, 5)
                .padding(.vertical, 6)
                .background(textColor.opacity(0.12), in: Capsule())
                .padding(.trailing, 10)
                .allowsHitTesting(false)
            }
            Color.clear
                .frame(width: 3)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            let start = AudioOutputSwitcher.outputVolume() ?? 0.5
                            let next = min(max(start - Double(value.translation.height) / 260, 0), 1)
                            _ = AudioOutputSwitcher.setOutputVolume(next)
                            volumeHUD = next
                        }
                        .onEnded { _ in
                            UserDefaults.standard.set(AudioOutputSwitcher.outputVolume() ?? 0.5,
                                                      forKey: MusicSurfaceConfig.edgeVolumeKey)
                            volumeHUD = nil
                        }
                )
                .accessibilityLabel(Text("Volume"))
        }
        .frame(width: 3)
    }

    @ViewBuilder
    private var background: some View {
        ZStack {
            if layout == .full, viewMode == .nowPlaying,
               let data = state.artworkData, let image = NSImage(data: data) {
                GeometryReader { proxy in
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height * 0.68, alignment: .top)
                        .clipped()
                        .overlay(
                            LinearGradient(stops: [
                                .init(color: .clear, location: 0.42),
                                .init(color: Color.black.opacity(theme.isDark ? 0.55 : 0.18), location: 0.78),
                                .init(color: Color.black.opacity(theme.isDark ? 0.78 : 0.30), location: 1)
                            ], startPoint: .top, endPoint: .bottom)
                        )
                }
            }
            if theme.usesMaterial {
                DockVisualEffectView(material: .hudWindow)
            }
            if theme.scrimIsLight {
                Color.white.opacity(theme.scrimOpacity)
            } else {
                Color.black.opacity(theme.scrimOpacity)
            }
            if theme.accentMix > 0 {
                accent.opacity(theme.accentMix)
            }
        }
    }

    private var rim: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(
                LinearGradient(colors: [Color.white.opacity(theme.rimOpacity), Color.white.opacity(0.06)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 0.75)
            .allowsHitTesting(false)
    }
}

// MARK: - Desktop host (slim ↔ full, swipes, edge stash)

/// Two-finger scroll bridge. `scrollWheel` phases drive the pure `MusicSwipeMachine`.
private struct MusicScrollCatcher: NSViewRepresentable {
    var onBegan: () -> Void
    var onChanged: (CGFloat, CGFloat) -> Void
    var onEnded: (CGFloat) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onBegan = onBegan
        view.onChanged = onChanged
        view.onEnded = onEnded
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onBegan = onBegan
        nsView.onChanged = onChanged
        nsView.onEnded = onEnded
    }

    final class CatcherView: NSView {
        var onBegan: () -> Void = {}
        var onChanged: (CGFloat, CGFloat) -> Void = { _, _ in }
        var onEnded: (CGFloat) -> Void = { _ in }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func scrollWheel(with event: NSEvent) {
            switch event.phase {
            case .began: onBegan()
            case .ended, .cancelled: onEnded(event.scrollingDeltaX + event.scrollingDeltaY)
            default: onChanged(event.scrollingDeltaX, event.scrollingDeltaY)
            }
            // A gesture is only ours while it is phased; a plain wheel still scrolls the canvas.
            if event.phase == [] { super.scrollWheel(with: event) }
        }
    }
}

struct DesktopVinylBoxView: View {
    @ObservedObject var service: NowPlayingService
    /// Reported when the two-finger vertical swipe (or the size button) changes Slim ↔ Full.
    var onRequestHeight: ((CGFloat) -> Void)? = nil
    /// ML-4: the containing panel does the tucking now, so the card only asks for a toggle.
    var onStashToggle: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var mode: MusicWidgetMode = MusicSurfaceConfig.mode()
    @State private var swiper = MusicSwipeMachine()
    @State private var selection = MusicSurfaceConfig.styleSelection()
    @State private var palette: MusicArtworkPalette = MusicArtworkPaletteCache.shared.palette(for: nil)
    /// ML-5 quick toggle. Off renders a compact placeholder instead of the card.
    @AppStorage(MusicSurfaceConfig.enabledKey) private var widgetEnabled = true

    private var assignment: MusicControlAssignment { MusicSurfaceConfig.assignment() }

    /// Slim/Full still follow the two-finger resize; hero is chosen in Settings.
    private var layout: MusicCardLayout {
        mode == .slim ? .slim : (selection.layout(for: .desktop) == .hero ? .hero : .full)
    }

    var body: some View {
        GeometryReader { _ in
            MusicGlassCardView(
                service: service,
                theme: selection.theme(for: .desktop),
                layout: layout,
                scrubber: selection.scrubber(for: .desktop),
                palette: palette,
                assignment: assignment,
                showsChrome: true,
                onToggleMode: { setMode(mode == .full ? .slim : .full) },
                onStash: { onStashToggle?() },
                onPlayLocalFile: { MusicLocalFilePicker.present() }
            )
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: mode)
            .background(
                MusicScrollCatcher(
                    onBegan: { swiper.begin() },
                    onChanged: { dx, dy in swiper.accumulate(deltaX: dx, deltaY: dy) },
                    onEnded: { velocity in
                        switch swiper.end(velocity: velocity,
                                          at: ProcessInfo.processInfo.systemUptime,
                                          currentMode: mode) {
                        case .resize(let next): setMode(next)
                        case .skip(let forward): forward ? service.nextTrack() : service.previousTrack()
                        case .none: break
                        }
                    }
                )
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: MusicSurfaceConfig.didChangeNotification)) { _ in
            selection = MusicSurfaceConfig.styleSelection()
        }
        .task(id: MusicArtworkSignature.of(service.state.artworkData)) {
            let data = service.state.artworkData
            guard let data, !data.isEmpty else {
                palette = .fallback
                return
            }
            let resolved = await Task.detached(priority: .utility) {
                MusicArtworkPaletteCache.shared.palette(for: data)
            }.value
            guard !Task.isCancelled else { return }
            palette = resolved
        }
    }

    private func setMode(_ next: MusicWidgetMode) {
        mode = next
        UserDefaults.standard.set(next == .slim, forKey: MusicSurfaceConfig.slimKey)
        onRequestHeight?(MusicCardLayout.from(mode: next, heroEnabled: selection.layout(for: .desktop) == .hero).height(width: 0))
    }

}

/// ML-6 — the only new entry point: pick a file, hand it to `LocalAudioPlayer`. No folder watching, no web
/// client, no playlist engine.
@MainActor
enum MusicLocalFilePicker {
    static func present() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
        panel.message = String(localized: "Choose an audio file to play locally.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        LocalAudioPlayer.shared.play(url: url)
    }
}


/// Lyrics translation reuses the same Translation framework pass as `TranslateCardView`: the view itself is
/// zero-sized, so the lyrics list keeps owning its layout.
@available(macOS 15.0, *)
private struct MusicLyricsTranslationHost<Content: View>: View {
    var lines: [String]
    var onResult: ([String: String]) -> Void
    @ViewBuilder var content: Content

    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        content
            .onAppear {
                if configuration == nil {
                    configuration = TranslationSession.Configuration(source: nil, target: nil)
                }
            }
            .translationTask(configuration) { session in
                var result: [String: String] = [:]
                for line in lines where !line.isEmpty {
                    if let response = try? await session.translate(line) {
                        result[line] = response.targetText
                    }
                }
                await MainActor.run { onResult(result) }
            }
    }
}

// MARK: - §10 Desktop music widget presets

/// The four desktop presets, all drawn by the existing `MusicGlassCardView`. Nothing here renders a new
/// card: poster and stage add an art-derived wash behind it, card and strip are the card alone.
struct MusicDesktopPresetView: View {
    var preset: MusicDesktopWidgetPreset
    @ObservedObject var service: NowPlayingService
    /// Set only by the live desktop panel: dragging the card moves its window and the corner grip resizes it.
    /// The Settings preview passes nil, so it never moves or resizes a real window.
    var interaction: MusicDesktopWidgetInteraction?
    @State private var selection = MusicSurfaceConfig.styleSelection()
    @State private var palette: MusicArtworkPalette = MusicArtworkPaletteCache.shared.palette(for: nil)
    @State private var backdropImage: NSImage?
    @State private var moveLastMouse: CGPoint?
    @State private var resizeLastMouse: CGPoint?

    init(preset: MusicDesktopWidgetPreset,
         service: NowPlayingService = DesktopWidgetServices.nowPlaying,
         interaction: MusicDesktopWidgetInteraction? = nil) {
        self.preset = preset
        self.service = service
        self.interaction = interaction
    }

    private var layout: MusicCardLayout {
        switch preset {
        case .poster: return .hero
        case .strip: return .slim
        case .stage, .card: return .full
        }
    }

    private var accent: Color {
        Color(red: palette.accent.r, green: palette.accent.g, blue: palette.accent.b)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if preset == .poster || preset == .stage {
                backdrop
            }
            card
                .frame(width: preset == .poster ? 360 : nil)
                .frame(maxWidth: preset == .strip ? .infinity : nil,
                       maxHeight: preset == .poster ? 316 : .infinity)
                .padding(preset == .poster ? 36 : (preset == .stage ? 16 : 0))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .gesture(moveGesture)
        .overlay(alignment: .top) { moveHint }
        .overlay(alignment: preset == .strip ? .trailing : .bottomTrailing) { resizeGrip }
        .onReceive(NotificationCenter.default.publisher(for: MusicSurfaceConfig.didChangeNotification)) { _ in
            selection = MusicSurfaceConfig.styleSelection()
        }
        .task(id: "\(MusicArtworkSignature.of(service.state.artworkData))-\(preset.rawValue)") {
            let data = service.state.artworkData
            let needsBackdrop = preset == .poster || preset == .stage
            let blurSigma = preset == .poster ? 24.0 : 16.0
            guard let data, !data.isEmpty else {
                palette = .fallback
                backdropImage = nil
                return
            }
            let result = await Task.detached(priority: .utility) {
                let resolvedPalette = MusicArtworkPaletteCache.shared.palette(for: data)
                let blurredCG = needsBackdrop ? Self.renderBlurredBackdrop(data: data, blurRadius: blurSigma) : nil
                return (resolvedPalette, blurredCG)
            }.value
            guard !Task.isCancelled else { return }
            palette = result.0
            backdropImage = result.1.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        }
    }

    // MARK: §10 move & resize

    /// Dragging the card's own surface (not a control) moves the window in screen coordinates. Buttons
    /// and the scrubber keep their gestures, so this only fires where there is nothing to click.
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { _ in
                guard let interaction else { return }
                let mouse = NSEvent.mouseLocation
                guard let previous = moveLastMouse else {
                    moveLastMouse = mouse
                    return
                }
                let delta = MusicDesktopWidgetGeometry.dragDelta(from: previous, to: mouse)
                moveLastMouse = mouse
                if delta != .zero { interaction.move(delta) }
            }
            .onEnded { _ in
                let hadDrag = moveLastMouse != nil
                moveLastMouse = nil
                if hadDrag { interaction?.commit() }
            }
    }

    private func resizeGesture(_ interaction: MusicDesktopWidgetInteraction) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { _ in
                let mouse = NSEvent.mouseLocation
                guard let previous = resizeLastMouse else {
                    resizeLastMouse = mouse
                    return
                }
                let delta = MusicDesktopWidgetGeometry.resizeDelta(from: previous, to: mouse)
                resizeLastMouse = mouse
                if delta != .zero { interaction.resize(delta) }
            }
            .onEnded { _ in
                let hadResize = resizeLastMouse != nil
                resizeLastMouse = nil
                if hadResize { interaction.commit() }
            }
    }

    /// A grabber on the card's top edge: the affordance for "this can be dragged", never a hit target.
    @ViewBuilder private var moveHint: some View {
        if interaction != nil, preset != .strip {
            Capsule()
                .fill(Color.white.opacity(0.25))
                .frame(width: 34, height: 4)
                .padding(.top, 6)
                .allowsHitTesting(false)
        }
    }

    /// Bottom-trailing grip for the card and the stage; a strip resizes from its trailing edge, width only.
    @ViewBuilder private var resizeGrip: some View {
        if let interaction {
            let vertical = preset == .strip
            Image(systemName: vertical ? "arrow.left.and.right" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.5))
                .frame(width: vertical ? 14 : 16, height: vertical ? 44 : 16)
                .contentShape(Rectangle())
                .gesture(resizeGesture(interaction))
        }
    }

    private var card: some View {
        MusicGlassCardView(
            service: service,
            theme: selection.theme(for: .desktop),
            layout: layout,
            scrubber: selection.scrubber(for: .desktop),
            palette: palette,
            assignment: MusicSurfaceConfig.assignment(),
            showsChrome: true,
            onPlayLocalFile: { MusicLocalFilePicker.present() }
        )
    }

    private static let backdropCIContext = CIContext(options: [.useSoftwareRenderer: false])

    private nonisolated static func renderBlurredBackdrop(data: Data, blurRadius: Double) -> CGImage? {
        guard let source = CIImage(data: data), source.extent.width > 1, source.extent.height > 1 else { return nil }
        let targetSide: CGFloat = 256
        let scale = targetSide / max(source.extent.width, source.extent.height)
        let scaled = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let crop = scaled.extent
        let blurred = scaled.clampedToExtent().applyingGaussianBlur(sigma: blurRadius).cropped(to: crop)
        return backdropCIContext.createCGImage(blurred, from: crop)
    }

    /// Art-derived wash for the two large presets: pre-blurred off-main once per track.
    @ViewBuilder private var backdrop: some View {
        ZStack {
            LinearGradient(colors: [accent.opacity(0.9), Color.black.opacity(0.95)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if let backdropImage {
                Image(nsImage: backdropImage)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.5)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        }
        .clipped()
        .allowsHitTesting(false)
    }
}
