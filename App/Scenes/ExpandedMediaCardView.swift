import AppKit
import Foundation
import SwiftUI

private struct LiveIslandVerticalKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Phase 18: the Live Island chip renders its side-rail (vertical) layout.
    var liveIslandVertical: Bool {
        get { self[LiveIslandVerticalKey.self] }
        set { self[LiveIslandVerticalKey.self] = newValue }
    }
}

// MARK: - Expanded Media Player Card (Phase 32)

struct ExpandedMediaCardView: View {
    @Environment(\.dockPopoverEdge) private var popoverEdge
    @ObservedObject private var feed = LiveActivityFeed.shared
    @StateObject private var systemStatus = SystemStatusService()
    @ObservedObject private var focus = ProductivityServices.shared.focus
    @ObservedObject private var alarmStore = ProductivityServices.shared.alarms
    @ObservedObject private var quickToggles = QuickToggleEngine.shared
    @AppStorage("com.katikati.stayawake.preset") private var awakePresetRaw: Int = 30
    @State private var awakeRemainingSeconds: Int = 0
    @State private var awakeTimerActive: Bool = false
    @State private var isHovered = false
    @State private var timelineNow = Date()
    @AppStorage("com.katikati.media.preset") private var mediaPreset: NowPlayingPreset = .accentCard
    @AppStorage("com.katikati.media.expandedCard.page") private var storedPage: Int = 0
    @State private var scrollDirection: Int = 1
    @State private var showPopup = false
    @State private var armingAlarm = false
    @State private var alarmDraft = Date()
    @Environment(\.widgetSize) private var widgetSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var currentPage: Int {
        WidgetPageCycle.clamped(storedPage, count: 5)
    }

    private func stepPage(_ delta: Int) {
        scrollDirection = delta >= 0 ? 1 : -1
        let next = WidgetPageCycle.next(current: currentPage, count: 5, delta: delta)
        if reduceMotion {
            storedPage = next
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                storedPage = next
            }
        }
    }

    var body: some View {
        let state = feed.nowPlayingState
        // Never invent a track: with no title from the system the card says so, and the scrubber is
        // drawn only for a position the system actually reported (it used to show a guessed 0.35).
        let progress = state.progress(at: timelineNow)
        let hasTrack = !(state.title?.isEmpty ?? true)
        // A player we may not read says so, instead of the card claiming nothing is playing (Phase 45).
        let unreadable = hasTrack ? nil : feed.playerAccess.unreadableMessage
        let title = hasTrack ? (state.title ?? "") : (unreadable ?? String(localized: "Not Playing"))
        let artist = hasTrack ? (state.artist ?? "") : (state.appName ?? "")

        HStack(spacing: 8) {
            // Paged Content area with vertical sliding animation
            ZStack {
                if currentPage == 0 {
                    trackPageView(state: state, progress: progress, title: title, artist: artist, unreadable: unreadable)
                        .transition(.asymmetric(
                            insertion: .move(edge: scrollDirection >= 0 ? .bottom : .top).combined(with: .opacity),
                            removal: .move(edge: scrollDirection >= 0 ? .top : .bottom).combined(with: .opacity)
                        ))
                } else if currentPage == 1 {
                    volumePageView
                        .transition(.asymmetric(
                            insertion: .move(edge: scrollDirection >= 0 ? .bottom : .top).combined(with: .opacity),
                            removal: .move(edge: scrollDirection >= 0 ? .top : .bottom).combined(with: .opacity)
                        ))
                } else if currentPage == 2 {
                    pomodoroPageView
                        .transition(.asymmetric(
                            insertion: .move(edge: scrollDirection >= 0 ? .bottom : .top).combined(with: .opacity),
                            removal: .move(edge: scrollDirection >= 0 ? .top : .bottom).combined(with: .opacity)
                        ))
                } else if currentPage == 3 {
                    stayAwakePageView
                        .transition(.asymmetric(
                            insertion: .move(edge: scrollDirection >= 0 ? .bottom : .top).combined(with: .opacity),
                            removal: .move(edge: scrollDirection >= 0 ? .top : .bottom).combined(with: .opacity)
                        ))
                } else {
                    alarmPageView
                        .transition(.asymmetric(
                            insertion: .move(edge: scrollDirection >= 0 ? .bottom : .top).combined(with: .opacity),
                            removal: .move(edge: scrollDirection >= 0 ? .top : .bottom).combined(with: .opacity)
                        ))
                }
            }
            .frame(maxWidth: .infinity)
            .clipped()

            // Vertical Pagination Dots (tactile click cycles to next page & remembers last page)
            WidgetPagerDotsStrip(pageCount: 5, currentPage: currentPage, axis: .vertical) {
                stepPage(1)
            }
            .padding(.trailing, 1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if mediaPreset == .accentCard, currentPage == 0, let a = ArtworkAccentCache.accent(for: feed.nowPlayingState.artworkData) {
                Color(red: a.red, green: a.green, blue: a.blue).opacity(0.22)
                    .animation(.easeInOut(duration: 0.6), value: feed.nowPlayingState.artworkData?.count)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .dockTileChrome(isHovered: isHovered, fill: mediaPreset == .graphiteCard ? LinearGradient(colors: [Color(white: 0.085)], startPoint: .top, endPoint: .bottom) : nil)
        .onHover { isHovered = $0 }
        .overlay(
            VerticalWheelScrollNSViewRepresentable { direction in
                stepPage(direction)
            }
            .allowsHitTesting(true)
        )
        .onReceive(timer) { input in
            timelineNow = input
            if awakeTimerActive && quickToggles.keepAwakeOn {
                if awakeRemainingSeconds > 1 {
                    awakeRemainingSeconds -= 1
                } else {
                    awakeRemainingSeconds = 0
                    awakeTimerActive = false
                    quickToggles.setKeepAwake(false)
                    NSSound(named: "Glass")?.play()
                }
            }
        }
        // The volume page reads and writes the real output device through `SystemStatusService`, which
        // binds its CoreAudio listeners on `acquire()`: without this the page showed a default level and
        // every drag was a no-op (Phase 43).
        .onAppear { feed.retain(); systemStatus.acquire() }
        .onDisappear { feed.release(); systemStatus.release() }
        .popover(isPresented: $showPopup, arrowEdge: popoverEdge) {
            NowPlayingPopup(
                state: state,
                theme: .auto,
                access: feed.playerAccess,
                onToggle: { feed.togglePlayPause() },
                onNext: { feed.nextTrack() },
                onPrevious: { feed.previousTrack() },
                onSeek: { feed.seek(to: $0) },
                sessions: feed.mediaSessions,
                onCyclePlayer: { feed.cycleMediaSession() }
            )
        }
    }

    // MARK: - Page 0: Track Info & Transport

    private func trackPageView(state: NowPlayingState, progress: Double?, title: String, artist: String, unreadable: String?) -> some View {
        HStack(spacing: 8) {
            // Album Artwork (never clipped)
            ZStack {
                if let data = state.artworkData, let img = NSImage(data: data) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(
                        colors: [Color(red: 0.35, green: 0.25, blue: 0.75),
                                 Color(red: 0.15, green: 0.18, blue: 0.45)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    TurntableView(isPlaying: state.isPlaying)
                        .padding(2)
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { NowPlayingTapRunner.openSource(state) }
            .onTapGesture { showPopup.toggle() }

            // Track details + Scrubber Bar
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(text: title, font: .system(size: 11.5, weight: mediaPreset == .graphiteCard ? .regular : .bold, design: .rounded), nearEnd: (progress ?? 0) > 0.88)
                    .foregroundStyle(.white)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { NowPlayingTapRunner.openSource(state) }
                    .onTapGesture { showPopup.toggle() }

                if unreadable == nil {
                    MarqueeText(text: artist, font: .system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { NowPlayingTapRunner.openSource(state) }
                        .onTapGesture { showPopup.toggle() }
                } else {
                    // The refused-player line is already the empty artist slot's own height, so the row
                    // does not grow — and it is the door to the fix, not only the report.
                    Button(String(localized: "Open System Settings")) {
                        if let url = PlayerAccess.automationSettingsURL { NSWorkspace.shared.open(url) }
                    }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                // Tracking bar — only for a real position and a real track length; a track with no
                // reported elapsed time (or nothing playing) draws no bar rather than a fraction we
                // made up. Elapsed sits on the left, the duration on the right (Phase 43). It is
                // scrubbable now (Phase 47): the bar is its own drag target, and the strip scrolls on the
                // wheel, so the two gestures never fight.
                if let progress, let duration = state.duration, duration > 0 {
                    let elapsed = NowPlayingProgress.elapsed(at: timelineNow, elapsed: state.elapsed,
                                                              asOf: state.elapsedAsOf, rate: state.rate,
                                                              duration: duration) ?? progress * duration
                    HStack(spacing: 3) {
                        Text(verbatim: NotchLayoutSpec.clockText(elapsed))
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)

                        MusicScrubBar(progress: progress, duration: duration, trackHeight: 3,
                                      tint: ArtworkAccentCache.accent(for: state.artworkData).map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? .white,
                                      onSeek: { feed.seek(to: $0) })
                            .frame(minWidth: 16, maxWidth: .infinity)
                            .frame(height: 6)

                        Text(verbatim: NotchLayoutSpec.clockText(duration))
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
                    }
                    .font(.system(size: 8.5, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.62))
                }
            }
            .frame(minWidth: 55, maxWidth: .infinity, alignment: .leading)

            // Playback Transport Controls
            HStack(spacing: 5) {
                Button(action: { feed.previousTrack() }) {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: { feed.togglePlayPause() }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.20))
                            .frame(width: 22, height: 22)
                        Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)

                Button(action: { feed.nextTrack() }) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Page 1: Volume & Audio Destination

    private var volumePageView: some View {
        let vol = systemStatus.status.volume
        return HStack(spacing: 8) {
            // Audio destination icon
            AudioOutputMenu {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 32, height: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                    Image(systemName: "airplayaudio")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(red: 0.38, green: 0.68, blue: 1.0))
                }
            }

            // Volume level slider & device label
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Volume")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Text(vol.isMuted ? "Muted" : "\(vol.percent)%")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.75))
                }

                // Interactive volume slider
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.18))
                            .frame(height: 4)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.38, green: 0.68, blue: 1.0),
                                             Color(red: 0.58, green: 0.45, blue: 0.95)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(3, geo.size.width * CGFloat(vol.isMuted ? 0 : vol.level)), height: 4)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                let fraction = Float(min(max(val.location.x / geo.size.width, 0.0), 1.0))
                                systemStatus.setVolume(fraction)
                            }
                    )
                }
                .frame(height: 6)
            }
            .frame(minWidth: 55, maxWidth: .infinity, alignment: .leading)

            // Quick Mute / Unmute
            Button(action: {
                let current = systemStatus.status.volume.level
                if current > 0 {
                    systemStatus.setVolume(0)
                } else {
                    systemStatus.setVolume(0.5)
                }
            }) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.20))
                        .frame(width: 22, height: 22)
                    Image(systemName: vol.symbolName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Page 2: Pomodoro Focus

    private var pomodoroPageView: some View {
        let model = focus.model
        let phase = model.phase
        let phaseColor: Color = {
            switch phase {
            case .focus: return Color(red: 1.0, green: 0.45, blue: 0.35)
            case .shortBreak: return Color(red: 0.25, green: 0.85, blue: 0.65)
            case .longBreak: return Color(red: 0.45, green: 0.65, blue: 1.0)
            }
        }()
        let phaseIcon: String = {
            switch phase {
            case .focus: return "flame.fill"
            case .shortBreak: return "cup.and.saucer.fill"
            case .longBreak: return "sparkles"
            }
        }()
        let phaseTitle: String = {
            switch phase {
            case .focus: return "Focus"
            case .shortBreak, .longBreak: return "Break"
            }
        }()
        let rem = model.remaining
        let timeStr = String(format: "%02d:%02d", rem / 60, rem % 60)

        return HStack(spacing: 8) {
            // Focus Dial / Ring Squircle
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(phaseColor.opacity(0.14))
                    .frame(width: 32, height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(phaseColor.opacity(0.28), lineWidth: 1)
                    )

                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 2)
                    .frame(width: 22, height: 22)

                Circle()
                    .trim(from: 0, to: model.progress)
                    .stroke(phaseColor, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .frame(width: 22, height: 22)
                    .rotationEffect(.degrees(-90))

                Image(systemName: phaseIcon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(phaseColor)
            }

            // Session Info + Time
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(phaseTitle)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(phaseColor)
                        .lineLimit(1)

                    // 4 session progress dots
                    HStack(spacing: 2.5) {
                        ForEach(0..<FocusTimerModel.cycleLength, id: \.self) { idx in
                            Circle()
                                .fill(idx < model.completedInCycle ? phaseColor : Color.white.opacity(0.20))
                                .frame(width: 3.5, height: 3.5)
                        }
                    }
                }

                HStack(spacing: 4) {
                    Text(verbatim: timeStr)
                        .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)

                    Text(verbatim: model.isRunning ? "• Active" : "• Paused")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.65))
                }

                // Mini progress track
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 3)
                        Capsule()
                            .fill(phaseColor)
                            .frame(width: max(3, geo.size.width * CGFloat(model.progress)), height: 3)
                    }
                }
                .frame(height: 3)
            }
            .frame(minWidth: 55, maxWidth: .infinity, alignment: .leading)

            // Play/Pause + Skip controls
            HStack(spacing: 5) {
                Button(action: { focus.skip() }) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.80))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: { focus.toggle() }) {
                    ZStack {
                        Circle()
                            .fill(phaseColor.opacity(model.isRunning ? 0.30 : 0.20))
                            .frame(width: 22, height: 22)
                        Image(systemName: model.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Page 3: Stay Awake & Sleep Inhibitor

    private var stayAwakePageView: some View {
        let isAwake = quickToggles.keepAwakeOn
        let preset = StayAwakePreset(rawValue: awakePresetRaw) ?? .m30
        let awakeColor = Color(red: 1.0, green: 0.65, blue: 0.20)

        return HStack(spacing: 8) {
            // Visual Squircle: glowing ember coffee/eye when on, sleepy moon/mug when off
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isAwake ? awakeColor.opacity(0.18) : Color.white.opacity(0.08))
                    .frame(width: 32, height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isAwake ? awakeColor.opacity(0.40) : Color.white.opacity(0.16), lineWidth: 1)
                    )

                if isAwake {
                    Circle()
                        .stroke(awakeColor.opacity(0.40), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                }

                Image(systemName: isAwake ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isAwake ? awakeColor : Color.white.opacity(0.45))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                toggleStayAwake()
            }

            // Status description & remaining countdown
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Keep Awake")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(isAwake ? awakeColor : .white)
                        .lineLimit(1)

                    Circle()
                        .fill(isAwake ? awakeColor : Color.white.opacity(0.25))
                        .frame(width: 4.5, height: 4.5)
                }

                HStack(spacing: 4) {
                    if isAwake {
                        if awakeTimerActive && awakeRemainingSeconds > 0 {
                            let m = awakeRemainingSeconds / 60
                            let s = awakeRemainingSeconds % 60
                            Text(verbatim: String(format: "%d:%02d Left", m, s))
                                .font(.system(size: 9.5, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(awakeColor)
                        } else {
                            Text("Keep Awake On")
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                .foregroundStyle(awakeColor)
                        }
                    } else {
                        Text("Keep Awake Off")
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.60))
                    }
                }

                // Mini duration progress track
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 3)

                        if isAwake {
                            let progressFraction: CGFloat = {
                                if let total = preset.seconds, total > 0 && awakeTimerActive {
                                    return CGFloat(awakeRemainingSeconds) / CGFloat(total)
                                }
                                return 1.0
                            }()
                            Capsule()
                                .fill(awakeColor)
                                .frame(width: max(3, geo.size.width * progressFraction), height: 3)
                        }
                    }
                }
                .frame(height: 3)
            }
            .frame(minWidth: 55, maxWidth: .infinity, alignment: .leading)

            // Duration Preset pill + Master Toggle
            HStack(spacing: 5) {
                Button(action: cycleStayAwakePreset) {
                    Text(verbatim: preset.label)
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(isAwake ? awakeColor : Color.white.opacity(0.85))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2.5)
                        .background(
                            Capsule()
                                .fill(isAwake ? awakeColor.opacity(0.20) : Color.white.opacity(0.12))
                        )
                        .overlay(
                            Capsule()
                                .stroke(isAwake ? awakeColor.opacity(0.45) : Color.white.opacity(0.18), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button(action: toggleStayAwake) {
                    ZStack {
                        Circle()
                            .fill(isAwake ? awakeColor : Color.white.opacity(0.20))
                            .frame(width: 22, height: 22)
                        Image(systemName: "power")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(isAwake ? Color.black : Color.white)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggleStayAwake() {
        let next = !quickToggles.keepAwakeOn
        let preset = StayAwakePreset(rawValue: awakePresetRaw) ?? .m30
        quickToggles.setKeepAwake(next)
        KeepAwakeService.shared.setManual(next, duration: preset.duration)   // the service owns expiry
        if next {
            if let sec = preset.seconds {
                awakeRemainingSeconds = sec
                awakeTimerActive = true
            } else {
                awakeRemainingSeconds = 0
                awakeTimerActive = false
            }
            NSSound(named: "Blow")?.play()
        } else {
            awakeRemainingSeconds = 0
            awakeTimerActive = false
        }
    }

    private func cycleStayAwakePreset() {
        let all = StayAwakePreset.allCases
        let current = StayAwakePreset(rawValue: awakePresetRaw) ?? .m30
        let nextIndex = ((all.firstIndex(of: current) ?? 0) + 1) % all.count
        let nextPreset = all[nextIndex]
        awakePresetRaw = nextPreset.rawValue
        if quickToggles.keepAwakeOn {
            KeepAwakeService.shared.setManual(true, duration: nextPreset.duration)
            if let sec = nextPreset.seconds {
                awakeRemainingSeconds = sec
                awakeTimerActive = true
            } else {
                awakeRemainingSeconds = 0
                awakeTimerActive = false
            }
        }
    }

    // MARK: - Page 4: Smart Alarm & Power Nap

    private var alarmPageView: some View {
        let nextAlarmTuple = AlarmList.next(in: alarmStore.alarms, after: timelineNow)
        let alarmGold = Color(red: 1.0, green: 0.82, blue: 0.25)

        return HStack(spacing: 8) {
            // Bell / Alarm status squircle. The armed state is the store's own: the page used to invent
            // a "Missed" alarm from the clock (any enabled alarm 0–15 minutes back), Phase 43 drops it.
            ZStack {
                let hasUpcoming = nextAlarmTuple != nil

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hasUpcoming ? alarmGold.opacity(0.15) : Color.white.opacity(0.08))
                    .frame(width: 32, height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(hasUpcoming ? alarmGold.opacity(0.30) : Color.white.opacity(0.16), lineWidth: 1)
                    )

                Image(systemName: hasUpcoming ? "alarm.fill" : "alarm")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(hasUpcoming ? alarmGold : Color.white.opacity(0.45))
            }

            // Alarm details / countdown
            VStack(alignment: .leading, spacing: 2) {
                if let (alarm, fireDate) = nextAlarmTuple {
                    HStack(spacing: 4) {
                        Text(verbatim: String(format: "%02d:%02d", alarm.hour, alarm.minute))
                            .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                        Text(verbatim: "• " + formatTimeUntil(fireDate: fireDate))
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundStyle(alarmGold)
                            .lineLimit(1)
                    }

                    Text(verbatim: alarm.label.isEmpty ? "Alarm" : alarm.label)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.70))
                        .lineLimit(1)
                } else {
                    Text("Alarm")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(verbatim: "No Alarm Armed")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.60))
                }
            }
            .frame(minWidth: 55, maxWidth: .infinity, alignment: .leading)

            // Arm a real alarm (the same time-picker + store the calendar panel's alarms tile uses) and
            // toggle the next armed one. No "+20m nap" shortcut and no invented row (Phase 43).
            HStack(spacing: 5) {
                Button { armingAlarm = true } label: {
                    ZStack {
                        Circle()
                            .fill(alarmGold.opacity(0.20))
                            .frame(width: 22, height: 22)
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(alarmGold)
                    }
                }
                .buttonStyle(.plain)
                .help(Text(verbatim: "Arm an alarm"))
                .popover(isPresented: $armingAlarm, arrowEdge: .top) {
                    VStack(spacing: 8) {
                        DatePicker(selection: $alarmDraft, displayedComponents: .hourAndMinute) {
                            Text("Alarm")
                        }
                        .labelsHidden()
                        Button("Add") {
                            let parts = Calendar.current.dateComponents([.hour, .minute], from: alarmDraft)
                            alarmStore.add(hour: parts.hour ?? 7, minute: parts.minute ?? 0)
                            armingAlarm = false
                        }
                    }
                    .padding(12)
                }

                if let (alarm, _) = nextAlarmTuple {
                    Button(action: { alarmStore.setEnabled(!alarm.isEnabled, for: alarm.id) }) {
                        ZStack {
                            Circle()
                                .fill(alarm.isEnabled ? alarmGold.opacity(0.25) : Color.white.opacity(0.18))
                                .frame(width: 22, height: 22)
                            Image(systemName: alarm.isEnabled ? "bell.fill" : "bell.slash.fill")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(alarm.isEnabled ? alarmGold : Color.white.opacity(0.7))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func formatTimeUntil(fireDate: Date) -> String {
        let diff = max(0, Int(fireDate.timeIntervalSince(timelineNow)))
        let hours = diff / 3600
        let minutes = (diff % 3600) / 60
        if hours > 0 {
            return "in \(hours)h \(minutes)m"
        } else {
            return "in \(max(1, minutes))m"
        }
    }
}

// MARK: - Wheel Scroll Vertical Paging Interceptor

struct VerticalWheelScrollNSViewRepresentable: NSViewRepresentable {
    var onStep: (Int) -> Void

    func makeNSView(context: Context) -> VerticalWheelNSView {
        let view = VerticalWheelNSView()
        view.onStep = onStep
        return view
    }

    func updateNSView(_ nsView: VerticalWheelNSView, context: Context) {
        nsView.onStep = onStep
    }
}

final class VerticalWheelNSView: NSView {
    var onStep: ((Int) -> Void)?
    private var scrollState = WidgetPageScrollEngine.State()

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard super.hitTest(point) != nil,
              let event = NSApp.currentEvent,
              event.type == .scrollWheel else { return nil }
        // Let predominantly horizontal swipes fall through to pan an overflowing horizontal dock;
        // own vertical swipes and gesture phase boundaries (.began/.ended/.cancelled).
        let isVerticalOrBoundary = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
            || event.phase.contains(.ended) || event.phase.contains(.cancelled)
        return isVerticalOrBoundary ? self : nil
    }

    override func scrollWheel(with event: NSEvent) {
        let input = WidgetPageScrollInput(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            hasPreciseDeltas: event.hasPreciseScrollingDeltas,
            isMomentum: !event.momentumPhase.isEmpty,
            phase: Self.mapPhase(event),
            timestamp: event.timestamp
        )
        if let step = WidgetPageScrollEngine.consume(input, state: &scrollState) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            onStep?(step)
        }
    }

    private static func mapPhase(_ event: NSEvent) -> WidgetPageScrollPhase {
        guard event.hasPreciseScrollingDeltas else { return .discrete }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) { return .began }
        if event.phase.contains(.ended) { return .ended }
        if event.phase.contains(.cancelled) { return .cancelled }
        if event.phase.contains(.changed) { return .changed }
        return event.momentumPhase.isEmpty ? .discrete : .changed
    }
}

/// Tactile multi-page dot strip: clicking anywhere on the strip cycles to the next page with a
/// spring pulse + alignment haptic, and expands the hit box without inflating widget layout.
struct WidgetPagerDotsStrip: View {
    let pageCount: Int
    let currentPage: Int
    var axis: Axis = .vertical
    var activeColor: Color = .white
    var inactiveColor: Color = Color.white.opacity(0.30)
    var compact: Bool = false
    let onAdvance: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var pulseScale: CGFloat = 1.0

    private var dotSpacing: CGFloat {
        compact ? 2.5 : (axis == .vertical && pageCount > 3 ? 2.2 : 3)
    }

    private var horizontalPadding: CGFloat {
        compact ? 4 : (axis == .vertical ? 4 : 5)
    }

    private var verticalPadding: CGFloat {
        if compact { return 2 }
        if axis == .vertical { return pageCount > 3 ? 1.5 : 4 }
        return 3
    }

    var body: some View {
        Button(action: triggerAdvance) {
            Group {
                if axis == .vertical {
                    VStack(spacing: dotSpacing) { dots }
                } else {
                    HStack(spacing: dotSpacing) { dots }
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                Capsule(style: .continuous)
                    .fill(activeColor.opacity(isHovered ? 0.14 : 0))
            )
            .contentShape(Rectangle().inset(by: -3))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityValue(Text(verbatim: "\(currentPage + 1)/\(max(pageCount, 1))"))
    }

    @ViewBuilder
    private var dots: some View {
        ForEach(0..<max(pageCount, 0), id: \.self) { page in
            let isActive = page == currentPage
            let long: CGFloat = compact ? 6 : 8
            let short: CGFloat = compact ? 2.5 : 3
            Capsule(style: .continuous)
                .fill(isActive ? activeColor : inactiveColor)
                .frame(
                    width: axis == .vertical ? short : (isActive ? long : short),
                    height: axis == .vertical ? (isActive ? long : short) : short
                )
                .scaleEffect(isActive ? pulseScale : 1.0)
                .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: currentPage)
        }
    }

    private func triggerAdvance() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        onAdvance()
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.16, dampingFraction: 0.45)) {
            pulseScale = 1.28
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.65)) {
                pulseScale = 1.0
            }
        }
    }
}
