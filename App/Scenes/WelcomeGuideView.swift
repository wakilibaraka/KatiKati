import AppKit
import AVFoundation
import CoreLocation
import EventKit
import ServiceManagement
import SwiftUI
import UserNotifications

/// 窗口根视图。
///
/// OB-2：窗口是**固定尺寸**的（`contentSize`），内容自己滚。旧实现靠「建窗时用一次性探针量死
/// 高度、之后永不重量」，那条约束渗进了每一幕——两幕必须一样高、取消勾选只能变淡不能塌、
/// 文案不能随状态变长。固定尺寸把这条约束整个删掉：探针没了，幕可以自由呼吸，跳过的分支
/// 可以真的消失。
struct WelcomeGuideWindowContent: View {
    let layout: WelcomeGuideLayoutContext
    let onApply: (WelcomeGuideSelection) -> Void
    let onDismiss: () -> Void
    /// False on a sandboxed / read-only copy: act 3 simply doesn't offer the system-Dock set.
    var offersNativeDock: Bool = true
    /// Live-check aid: open straight on one act (`DOCK_WELCOME_STEP`).
    var startAt: WelcomeGuideStep? = nil

    var body: some View {
        WelcomeGuideView(layout: layout,
                         onApply: onApply,
                         onDismiss: onDismiss,
                         offersNativeDock: offersNativeDock,
                         startAt: startAt)
            // The stage is `AmbientMesh` — fixed dark navy in **every** appearance. In Light
            // appearance the semantic label colours therefore resolved to black-on-black (the footer's
            // `Back` was the worst case, but body copy and `Skip` suffered too). Declaring the panel
            // dark, exactly as `ChipPanelView` and `StackPopupChrome` do for their plates, is what
            // makes `.primary`/`.secondary`/`.tertiary` the standard light-on-dark label ladder
            // instead of a second guess about what is behind the glass.
            .environment(\.colorScheme, .dark)
            .frame(width: WelcomeGuideView.contentSize.width,
                   height: WelcomeGuideView.contentSize.height)
    }
}

// MARK: - Ambient stage

/// 首秀的底。`MeshGradient` 是 macOS 15 就有的原生网格渐变（部署目标正好是 15，所以不需要
/// 可用性标注），三团模糊光斑在它上面缓慢漂移。
///
/// 漂移用的是**插值动画**（`repeatForever` 的 `easeInOut` 驱动 `scaleEffect` / `offset`），
/// 不是 `TimelineView`：没有逐帧回调、没有 display link、没有 Metal 层要拆。窗口一关，视图
/// 就没了，动画跟着没——这就是「关掉之后 0% 空闲 CPU」最省事的实现方式：不是去管住一个
/// 每帧都跑的循环，而是根本不建那个循环。
///
/// Reduce Motion 下只有一层静态网格。
private struct AmbientMesh: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    private static let points: [SIMD2<Float>] = [
        [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
        [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
        [0.0, 1.0], [0.5, 1.0], [1.0, 1.0],
    ]

    private static let colors: [Color] = [
        Color(red: 0.05, green: 0.06, blue: 0.10),
        Color(red: 0.10, green: 0.17, blue: 0.31),
        Color(red: 0.04, green: 0.05, blue: 0.09),
        Color(red: 0.14, green: 0.23, blue: 0.40),
        Color(red: 0.28, green: 0.21, blue: 0.46),
        Color(red: 0.10, green: 0.15, blue: 0.28),
        Color(red: 0.03, green: 0.04, blue: 0.08),
        Color(red: 0.09, green: 0.13, blue: 0.25),
        Color(red: 0.02, green: 0.03, blue: 0.06),
    ]

    var body: some View {
        ZStack {
            MeshGradient(width: 3, height: 3, points: Self.points, colors: Self.colors)
            bloom(Color(red: 0.32, green: 0.55, blue: 0.99), dx: 215, dy: -125, scale: 1.18, duration: 16)
            bloom(Color(red: 0.63, green: 0.35, blue: 0.97), dx: -235, dy: 145, scale: 1.02, duration: 20)
            bloom(Color(red: 0.20, green: 0.86, blue: 0.78), dx: 125, dy: 195, scale: 0.92, duration: 24)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) { drift = true }
        }
    }

    private func bloom(_ color: Color, dx: CGFloat, dy: CGFloat, scale: CGFloat, duration: Double) -> some View {
        Circle()
            .fill(color.opacity(0.30))
            .frame(width: 320, height: 320)
            .blur(radius: 96)
            .scaleEffect(drift ? scale : 0.74)
            .offset(x: drift ? dx : dx * 0.22, y: drift ? dy : dy * 0.28)
            .animation(reduceMotion ? nil : .easeInOut(duration: duration).repeatForever(autoreverses: true),
                       value: drift)
    }
}

// MARK: - Kinetic type

/// 逐词落地的标题。`phrase` 是**一条**本地化字符串，运行期按空格切词——这样十二种语言的语序
/// 各自正确，而逐词动画不需要为每种语言手工排一遍。品牌名是这条短语的一部分，不用另开 key。
///
/// `.task` 在幕切换时重跑，所以每一幕的第一帧都是从第一个词开始。
private struct KineticWords: View {
    let phrase: String
    var font: Font
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0

    private var words: [String] { phrase.split(separator: " ").map(String.init) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                Text(verbatim: word)
                    .font(font)
                    .opacity(index < shown ? 1 : 0)
                    .blur(radius: index < shown ? 0 : 7)
                    .offset(y: index < shown || reduceMotion ? 0 : 12)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.52, dampingFraction: 0.78),
                   value: shown)
        .task { await play() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: phrase))
    }

    private func play() async {
        shown = 0
        guard !reduceMotion else {
            shown = words.count
            return
        }
        try? await Task.sleep(for: .milliseconds(60))
        for index in 1...max(1, words.count) {
            shown = index
            try? await Task.sleep(for: .milliseconds(150))
        }
    }
}

// MARK: - The guide

/// 首次运行的一次性引导。
///
/// 六幕：首秀 → 你的条 → 观感 → 权限 → 节奏 → 收尾。每一幕只做一个决定，且除了首秀与收尾
/// 之外每一次操作都**当场**写进 store——用户看到的不是插图，是正在被配置的这台机器。
struct WelcomeGuideLayoutContext {
    var initialMode: BarLayoutMode
    var inputs: LayoutThumbnailModel.Inputs
    var initialStyleID: String? = nil
    var onPickStyle: (DockStyle) -> Void = { _ in }
    var initialTheme: DockThemeStyle = .auto
    var onPickTheme: (DockThemeStyle) -> Void = { _ in }
    /// The notch Live Island switch (default on); written to the store as soon as it is flipped.
    var notchEnabled = true
    var onNotchToggle: (Bool) -> Void = { _ in }
    var initialVisibleSections: Set<BarSection> = Set(BarSection.defaultOrder)
    var onToggleSection: (BarSection, Bool) -> Void = { _, _ in }
    var initialWings: DockWingsConfiguration = .default
    var onPickWing: (DockWingPlacement, DockWidgetPresetType) -> Void = { _, _ in }
    var initialPlacement: StripPlacement = .bottom
    var onPickPlacement: (StripPlacement) -> Void = { _ in }
    var initialCitySelection: WeatherLocationSelection = .current
    var searchCities: (String) async -> [SavedCity] = { _ in [] }
    var onAddCity: (SavedCity) -> Void = { _ in }
    var onPickCity: (WeatherLocationSelection) -> Void = { _ in }
    /// Async read of the notification grant, injected by the app. It is a seam rather than a direct
    /// call because `UNUserNotificationCenter.current()` raises an **uncaught**
    /// `NSInternalInconsistencyException` ("bundleProxyForCurrentProcess is nil") in any process
    /// without a bundle proxy — the unit-test runner is one, and hosting the Access act reaches this
    /// code. The default answers "not granted" and touches nothing.
    var notificationsAuthorized: () async -> Bool = { false }
    var aiTrackingEnabled = false
    var onSetAITracking: (Bool) -> Void = { _ in }
    var launcherDoubleTap = false
    var onSetLauncherDoubleTap: (Bool) -> Void = { _ in }
    var clipboardToastEnabled = ClipboardToastDefaults.enabledByDefault
    var onSetClipboardToast: (Bool) -> Void = { _ in }
    var initialAppIconPreset: AppIconPresentationPreset = .appPills
    var onPickAppIconPreset: (AppIconPresentationPreset) -> Void = { _ in }
    var initialTrailingCapsule: DockSlotItem? = .controlCenter
    var onPickTrailingCapsule: (DockSlotItem?) -> Void = { _ in }
}

struct WelcomeGuideView: View {
    let layout: WelcomeGuideLayoutContext
    let onApply: (WelcomeGuideSelection) -> Void
    let onDismiss: () -> Void
    var offersNativeDock: Bool = true
    var startAt: WelcomeGuideStep? = nil

    @State private var selection = WelcomeGuideSelection.recommended
    @State private var step = WelcomeGuideStep.first
    @State private var pickedMode: BarLayoutMode?
    @State private var pickedStyleID: String?
    @State private var pickedPlacement: StripPlacement?
    @State private var pickedAppIconPreset: AppIconPresentationPreset?
    @State private var pickedTrailingCapsule: DockSlotItem??
    @State private var pickedTheme: DockThemeStyle?
    @State private var cityQuery = ""
    @State private var cityResults: [SavedCity] = []
    @State private var pickedCity: WeatherLocationSelection?
    @State private var aiOn: Bool?
    @State private var launcherOn: Bool?
    @State private var toastOn: Bool?
    @State private var notchOn: Bool?
    @State private var visibleSections: Set<BarSection>?
    @State private var wingsConfig: DockWingsConfiguration?
    @State private var practiceTaps = 0
    /// True while the act's content runs past the viewport bottom (only the Access act does), so the
    /// fade + chevron under the footer bar follow the real scroll position rather than the act's name.
    @State private var canScrollFurther = false
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var screenRecordingGranted = CGPreflightScreenCaptureAccess()
    @State private var inputMonitoringGranted = CGPreflightListenEventAccess()
    @State private var microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @State private var calendarGranted = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    @State private var remindersGranted = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    @State private var notificationsGranted = false
    /// Login Item is not a TCC grant: the row registers the app, and macOS may still park it in Login
    /// Items for approval — that case opens the pane instead of pretending the switch is on.
    @State private var loginItemEnabled = SMAppService.mainApp.status == .enabled
    @State private var locationGranted = false
    /// One onboarding pass asks for everything it needs; panels then never prompt mid-task.
    @State private var didRequestAllPermissions = false
    @State private var locationManager = CLLocationManager()
    private static let eventStore = EKEventStore()

    /// 固定尺寸，接近方形。
    ///
    /// **不要把它改回「高度跟着内容走」**：窗口里装的是 `ScrollView`，而 `ScrollView` 的理想尺寸
    /// 是它内容的高度——只要让 hosting view 参与定尺寸，这块方正的板子就会变成一条从上到下的长条。
    /// 内容超出时由 ScrollView 自己滚，窗口形状永远不动。
    static let contentSize = CGSize(width: 720, height: 640)
    /// How much glass a **short** act may keep between its copy and the footer bar, in points.
    ///
    /// The panel is a fixed 640 and the reveal, rhythm and finale hold 250–320 pt of content, so
    /// roughly 280 pt is left over. Top-aligned, that whole leftover pooled between the copy and its
    /// `Continue`/`Apply` button, which made those acts read as unfinished. The acts now claim the
    /// viewport and split the leftover with their own spacers: an uncapped one above, this capped one
    /// below. The cap is what weights the split — the copy drops to sit with its action instead of
    /// floating in the middle, and the remainder goes above the copy as breathing room under the
    /// header. Acts that already overflow are taller than the viewport, so a *minimum* never touches
    /// them and their spacers stay collapsed.
    static let shortActTailGap: CGFloat = 96

    /// How far past the viewport the content must run before the overflow cue appears, in points.
    ///
    /// Not zero: the bar act runs 18–19 pt past the edge, which is its own bottom padding rather than
    /// a clipped row, and dimming its last toggle to advertise that would be noise. The Access act runs
    /// 137 pt past the edge, and that is the case the cue exists for.
    static let overflowCueThreshold: CGFloat = 28

    /// A hosting view that can never resize the window it is placed in.
    ///
    /// Shared by `AppDelegate` and the regression test on purpose: the "stretch" defect is exactly a
    /// missing line here, so the test has to exercise this function rather than re-implement it.
    ///
    /// - `sizingOptions = []`: the content is a `ScrollView`, whose ideal size is its *content*
    ///   height; left alone the panel becomes a full-height strip.
    /// - `safeAreaRegions = []`: `.fullSizeContentView` otherwise adds a ~32 pt top inset, which makes
    ///   the ideal size 720x672. Ignoring the safe area inside SwiftUI inflates the ideal size the
    ///   same way, so it has to be removed at the hosting level.
    static func pinnedHostingView(_ content: WelcomeGuideWindowContent) -> NSHostingView<WelcomeGuideWindowContent> {
        let host = NSHostingView(rootView: content)
        host.sizingOptions = []
        host.safeAreaRegions = []
        host.frame = NSRect(origin: .zero, size: contentSize)
        return host
    }

    /// Pins the panel's **frame** to exactly `contentSize`.
    ///
    /// `contentMinSize`/`contentMaxSize` are the wrong knob and were the live 720x**672** bug: they
    /// constrain the content height, and AppKit then adds the 32 pt titlebar on top of it — the launch
    /// log read frame 720x640 immediately and 720x672 two seconds later. `minSize`/`maxSize` are
    /// frame-based, so the titlebar cannot be stacked on afterwards.
    static func pinPanelWindow(_ window: NSWindow) {
        window.minSize = contentSize
        window.maxSize = contentSize
    }

    /// The window frame for a panel of `frameSize`, centred in `visibleFrame` — the **usable** area,
    /// i.e. menu bar and Dock excluded. Centring in `screen.frame` instead would push the panel up
    /// by half the menu bar and down by half the Dock, which reads as "slightly off" rather than
    /// broken; that is exactly the kind of drift a screenshot is needed to catch.
    ///
    /// Clamped so a panel taller or wider than the usable area still starts on screen instead of
    /// hanging off the top edge where its traffic lights would be unreachable.
    static func centeredFrame(in visibleFrame: CGRect, frameSize: CGSize) -> CGRect {
        guard visibleFrame.width > 0, visibleFrame.height > 0 else {
            return CGRect(origin: .zero, size: frameSize)
        }
        let width = min(frameSize.width, visibleFrame.width)
        let height = min(frameSize.height, visibleFrame.height)
        let x = visibleFrame.midX - width / 2
        let y = visibleFrame.midY - height / 2
        return CGRect(x: max(visibleFrame.minX, min(x, visibleFrame.maxX - width)),
                      y: max(visibleFrame.minY, min(y, visibleFrame.maxY - height)),
                      width: width,
                      height: height)
    }

    private var currentSections: Set<BarSection> { visibleSections ?? layout.initialVisibleSections }
    private var currentWings: DockWingsConfiguration { wingsConfig ?? layout.initialWings }
    /// Every section the act's grid offers, in canonical order. `apps` is structural (the running-app
    /// chips), so it is not a switch. Internal so the regression test walks exactly these switches.
    static let configurableSections: [BarSection] = BarSection.canonicalOrder.filter { $0 != .apps }
    private var currentMode: BarLayoutMode { pickedMode ?? layout.initialMode }
    private var currentTheme: DockThemeStyle { pickedTheme ?? layout.initialTheme }

    var body: some View {
        ZStack {
            AmbientMesh()
            VStack(spacing: 0) {
                header
                GeometryReader { viewport in
                    ScrollView(.vertical) {
                        actBody
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 32)
                            .padding(.top, 6)
                            .padding(.bottom, 26)
                            // A short act still claims the whole viewport, so its spacers can
                            // distribute the leftover glass (see `shortActTailGap`). A taller act is
                            // taller than this, and a minimum cannot shrink it.
                            .frame(minHeight: viewport.size.height, alignment: .top)
                    }
                    // Read from the real scroll geometry rather than from "this act is Access", so the
                    // cue leaves the moment the last row is reached and no act that fits shows it.
                    //
                    // The transform answers the question and the action only stores the answer: no
                    // detour through the main queue, because this action is called from the scroll
                    // transaction rather than from `body`.
                    .onScrollGeometryChange(for: Bool.self) { geometry in
                        geometry.contentSize.height - geometry.containerSize.height
                            - geometry.contentOffset.y > Self.overflowCueThreshold
                    } action: { _, hasMoreBelow in
                        canScrollFurther = hasMoreBelow
                    }
                    .overlay(alignment: .bottom) {
                        // Always laid out and faded in and out: the cue never changes the layout, and
                        // the 0.2 s fade is what turns it soft at the edge.
                        overflowCue
                            .opacity(canScrollFurther ? 1 : 0)
                            .animation(.easeInOut(duration: 0.2), value: canScrollFurther)
                    }
                }
                footer
            }
        }
        // The glass fills the whole window because the hosting view is told it has **no** safe area
        // (`NSHostingView.safeAreaRegions = []` in `AppDelegate`), not because this view ignores one.
        //
        // Two earlier attempts and why they are wrong: hanging the material on the `VStack` left a bare
        // dark titlebar band above the panel; `.ignoresSafeArea()` on the whole stack instead inflated
        // the root's ideal size to 720x**672** (the 32 pt titlebar inset) and clipped the dots and Skip
        // against the top edge. The 672 is the stretch mechanism itself — the live window stayed 640
        // only because `contentMin/MaxSize` pinned it.
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.05)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 0.5
                )
                .allowsHitTesting(false)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear { if let startAt, step != startAt { step = startAt } }
    }

    // MARK: - Chrome

    /// 进度点在**窗口正中**，不是靠左：这扇窗是 `.fullSizeContentView`，左上角归红黄绿三个
    /// 交通灯所有，任何贴左的内容都会压在它们下面。Skip 靠右，同样不与它们相干。
    private var header: some View {
        ZStack {
            HStack(spacing: 6) {
                ForEach(WelcomeGuideStep.allCases, id: \.self) { candidate in
                    Capsule()
                        .fill(candidate == step ? Color.primary : Color.primary.opacity(0.18))
                        .frame(width: candidate == step ? 18 : 6, height: 6)
                        .animation(.spring(response: 0.34, dampingFraction: 0.8), value: step)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(String(localized: "Setup progress")))
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Button(String(localized: "Skip")) { onDismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(".", modifiers: .command)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let previous = step.previous {
                // Not a default-styled push button: over this glass panel AppKit drew its bezel as a
                // near-black slab whose label was just as dark. A glass pill on the panel's own label
                // ladder reads at full contrast, and the fill stays neutral — `Color.primary` at low
                // alpha is white here because the panel declares a dark scheme — so `Continue` keeps
                // the accent weight.
                Button { advance(to: previous) } label: {
                    Text(String(localized: "Back"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.primary.opacity(0.12)))
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.22), lineWidth: 0.5))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
            Spacer(minLength: 0)
            Button(primaryTitle) { primaryAction() }
                .keyboardShortcut(.defaultAction)
                .disabled(offersNativeDock && step == .finale && selection.isEmpty)
                .fixedSize()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    /// The bottom spacer of a **short** act, capped at `shortActTailGap`.
    ///
    /// The cap is the whole point: an uncapped `Spacer` below the copy would cancel the one above and
    /// centre the act. Capped, the spacer underneath asks for at most 96 pt, so the leftover goes to
    /// the spacer above — the copy drops toward its `Continue`/`Apply` action, and the remaining glass
    /// becomes one gap under the header instead of a hole between the copy and its button.
    private var actTail: some View {
        Spacer(minLength: 10).frame(maxHeight: Self.shortActTailGap)
    }

    /// The cue that the Access act continues under the footer bar.
    ///
    /// The half-cut row used to be the only signal that the panel scrolls. This is a soft edge where
    /// the content meets the footer plus a single chevron — both keyed to the scroll geometry, so they
    /// leave as soon as the bottom is reached, and an act that fits (or stops a few points short of
    /// the edge) never shows them.
    private var overflowCue: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.50)], startPoint: .top, endPoint: .bottom)
                .frame(height: 44)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 20, height: 20)
                .background(Circle().fill(.regularMaterial))
                .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .padding(.bottom, 7)
        }
        .frame(maxWidth: .infinity, maxHeight: 44, alignment: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var primaryTitle: String {
        guard step == .finale else { return String(localized: "Continue") }
        return offersNativeDock
            ? String(localized: "Apply Recommended Settings")
            : String(localized: "Start Using KatiKati")
    }

    private func primaryAction() {
        if let next = step.next {
            advance(to: next)
        } else {
            onApply(offersNativeDock ? selection : WelcomeGuideSelection(
                hidesDock: false, usesScaleMinimizeEffect: false, minimizesIntoAppIcon: false))
        }
    }

    private func advance(to next: WelcomeGuideStep) {
        practiceTaps = 0
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { step = next }
    }

    // MARK: - Acts

    @ViewBuilder
    private var actBody: some View {
        Group {
            switch step {
            case .reveal: revealAct
            case .bar: barAct
            case .feel: feelAct
            case .access: accessAct
            case .rhythm: rhythmAct
            case .finale: finaleAct
            }
        }
        .id(step)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .offset(y: 14)),
            removal: .opacity.combined(with: .offset(y: -10))
        ))
    }

    /// Act 1 — the product statement. Writes nothing (pinned by a test).
    private var revealAct: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer(minLength: 26)
            HStack(spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable()
                    .frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
                    )
                KineticWords(phrase: String(localized: "Welcome to KatiKati"),
                             font: .system(size: 40, weight: .semibold, design: .rounded))
            }
            Text(String(localized: "Your Dock, Notch, and Workspace — reimagined."))
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(String(localized: "Six short steps, and everything below is already changing on your Mac as you choose it."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            actTail
        }
    }

    /// Act 2 — the bar's shape. Everything here is live.
    private var barAct: some View {
        VStack(alignment: .leading, spacing: 16) {
            actTitle(String(localized: "Your bar"),
                     subtitle: String(localized: "Pick a look and the screen edge it sits on. You can change both any time in Settings or from the menu bar."))
            DockStylePicker(selection: pickedStyleID ?? layout.initialStyleID,
                            inputs: layout.inputs,
                            thumbnailSize: CGSize(width: 104, height: 46),
                            styles: DockStyle.onboardingCards) { style in
                pickedStyleID = style.id
                pickedMode = style.mode
                layout.onPickStyle(style)
            }
            DockLivePreviewStrip(mode: currentMode,
                                 visibleOrder: BarSection.canonicalOrder.filter {
                                     $0 == .apps || currentSections.contains($0)
                                 },
                                 wings: currentWings)
            LayoutModeDetail(mode: currentMode)
                .font(.callout)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)
            // Chips, not a segmented control: on this dark plate macOS drew the segmented track as a
            // pale glass bar while keeping its labels white — about 2:1, the worst contrast in the
            // panel. These use the same fill/selection language as the section grid just below, so
            // the edge reads as one more choice in this act rather than a system control dropped in.
            HStack(spacing: 6) {
                edgeChip(String(localized: "Bottom"), .bottom)
                edgeChip(String(localized: "Left"), .left)
                edgeChip(String(localized: "Right"), .right)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(String(localized: "Edge")))
            Divider()
            sectionGrid
            HStack(spacing: 12) {
                wingPicker(label: Text(String(localized: "Left Wing")), placement: .leftWing, current: currentWings.left.preset)
                wingPicker(label: Text(String(localized: "Right Wing")), placement: .rightWing, current: currentWings.right.preset)
            }
            Toggle(String(localized: "Show the Dynamic Notch"), isOn: Binding(
                get: { notchOn ?? layout.notchEnabled },
                set: { notchOn = $0; layout.onNotchToggle($0) }
            ))
        }
    }

    /// Act 3 — the finish, plus the one write that touches the system Dock.
    ///
    /// Spacing is 13 here, not the 16 the other dense acts use: naming the four swatches added ~19 pt
    /// of height, which pushed the act — and with it "Want the Dock back?" — past the viewport. The
    /// act is a list of settings rows, so it is the gaps that can absorb that, not the copy.
    private var feelAct: some View {
        VStack(alignment: .leading, spacing: 13) {
            actTitle(String(localized: "Feel"),
                     subtitle: String(localized: "The finish of the bar and of the app icons on it."))
            Text(String(localized: "Theme"))
                .font(.callout.weight(.medium))
            HStack(spacing: 12) {
                ForEach(Self.themeChoices, id: \.token) { style in
                    let isPicked = style == currentTheme
                    Button {
                        pickedTheme = style
                        layout.onPickTheme(style)
                    } label: {
                        // Swatch **and** name, like the Appearance pane's theme cards: four tints
                        // with only the selected one ringed left a sighted user guessing which was
                        // "Aurora Glow". VoiceOver keeps reading the same catalogue name.
                        VStack(spacing: 4) {
                            ThemeSwatch(style: style)
                                .frame(width: 62, height: 42)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(isPicked ? Color.accentColor : Color.primary.opacity(0.12),
                                                      lineWidth: isPicked ? 2 : 1)
                                )
                            Text(verbatim: style.menuTitle)
                                .font(.system(size: 11, weight: isPicked ? .semibold : .regular))
                                .foregroundStyle(isPicked ? Color.primary : Color.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(height: 12)
                        }
                        .frame(width: 88)
                    }
                    .buttonStyle(.plain)
                    // The catalogue's own theme name, never the internal token: this used to be
                    // `Text(verbatim: style.token)`, so VoiceOver read "obsidianDark".
                    .accessibilityLabel(Text(verbatim: style.menuTitle))
                    .accessibilityAddTraits(isPicked ? .isSelected : [])
                }
            }
            Divider()
            HStack(spacing: 8) {
                Text(String(localized: "App Icons"))
                    .font(.callout.weight(.medium))
                Spacer(minLength: 8)
                Picker(String(localized: "App Icons"), selection: Binding(
                    get: { pickedAppIconPreset ?? layout.initialAppIconPreset },
                    set: { picked in
                        pickedAppIconPreset = picked
                        layout.onPickAppIconPreset(picked)
                    }
                )) {
                    ForEach(AppIconPresentationPreset.allCases) { preset in
                        Text(verbatim: preset.localizedTitle).tag(preset)
                    }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            HStack(spacing: 8) {
                Text(String(localized: "Detached Capsule"))
                    .font(.callout.weight(.medium))
                Spacer(minLength: 8)
                Picker(String(localized: "Detached Capsule"), selection: Binding<DockSlotItem?>(
                    get: { pickedTrailingCapsule ?? layout.initialTrailingCapsule },
                    set: { picked in
                        pickedTrailingCapsule = .some(picked)
                        layout.onPickTrailingCapsule(picked)
                    }
                )) {
                    Text(DockSlotItem.controlCenter.title).tag(DockSlotItem?.some(.controlCenter))
                    Text(DockSlotItem.backgroundApps.title).tag(DockSlotItem?.some(.backgroundApps))
                    Text(DockSlotItem.trash.title).tag(DockSlotItem?.some(.trash))
                    Text(DockSlotItem.launcher.title).tag(DockSlotItem?.some(.launcher))
                    Text(DockSlotItem.shelf.title).tag(DockSlotItem?.some(.shelf))
                    Text(String(localized: "Off")).tag(DockSlotItem?.none)
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            VStack(alignment: .leading, spacing: 3) {
                Toggle(String(localized: "AI Tracking"), isOn: Binding(
                    get: { aiOn ?? layout.aiTrackingEnabled },
                    set: { aiOn = $0; layout.onSetAITracking($0) }
                ))
                Text(String(localized: "Off unless you turn it on: it reads window titles on this Mac and spends a little CPU to keep the AI chip current."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if offersNativeDock {
                Divider()
                Text(String(localized: "Recommended Dock Settings"))
                    .font(.headline)
                options
                comeBackNote
            }
        }
    }

    /// Act 4 — one pass, two tiers. Required is only Accessibility; the other nine are genuinely
    /// optional, and saying so is the whole point of the tier split.
    private var accessAct: some View {
        VStack(alignment: .leading, spacing: 12) {
            actTitle(String(localized: "Access"),
                     subtitle: String(localized: "These permissions help KatiKati work properly. You can change them any time in System Settings › Privacy & Security."))
            tierHeader(String(localized: "Required"))
            PermissionRow(title: Text(String(localized: "Accessibility")),
                          note: Text(String(localized: "Shows your open windows as chips and lets you switch to them.")),
                          isGranted: accessibilityGranted,
                          grant: {
                              _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
                          })
            tierHeader(String(localized: "Optional"))
            PermissionRow(title: Text(String(localized: "Screen Recording")),
                          note: Text(String(localized: "Shows live window thumbnails in hover previews. Without it, previews show titles only.")),
                          isGranted: screenRecordingGranted,
                          grant: { _ = CGRequestScreenCaptureAccess(); PermissionRow.openPrivacy("Privacy_ScreenCapture") })
            PermissionRow(title: Text(String(localized: "Input Monitoring")),
                          note: Text(String(localized: "Only for the optional Hyper key. Skip it if you won’t use that.")),
                          isGranted: inputMonitoringGranted,
                          grant: { _ = CGRequestListenEventAccess(); PermissionRow.openPrivacy("Privacy_ListenEvent") })
            PermissionRow(title: Text(String(localized: "Microphone")),
                          note: Text(String(localized: "Only for the voice recorder and the camera mirror. Nothing records until you start one.")),
                          isGranted: microphoneGranted,
                          grant: {
                              AVCaptureDevice.requestAccess(for: .audio) { _ in }
                              PermissionRow.openPrivacy("Privacy_Microphone")
                          })
            PermissionRow(title: Text(String(localized: "Camera")),
                          note: Text(String(localized: "Only for the camera mirror. Nothing turns the camera on until you open it.")),
                          isGranted: cameraGranted,
                          grant: {
                              AVCaptureDevice.requestAccess(for: .video) { _ in }
                              PermissionRow.openPrivacy("Privacy_Camera")
                          })
            PermissionRow(title: Text(String(localized: "Calendar")),
                          note: Text(String(localized: "Shows today’s events in the panel, the notch and the command bar.")),
                          isGranted: calendarGranted,
                          grant: { PermissionRow.openPrivacy("Privacy_Calendars") })
            PermissionRow(title: Text(String(localized: "Reminders")),
                          note: Text(String(localized: "Lists your reminders beside today’s events.")),
                          isGranted: remindersGranted,
                          grant: { PermissionRow.openPrivacy("Privacy_Reminders") })
            PermissionRow(title: Text(String(localized: "Notifications")),
                          note: Text(String(localized: "Delivers alarms and live-event banners while KatiKati is in the background.")),
                          isGranted: notificationsGranted,
                          grant: {
                              if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                                  NSWorkspace.shared.open(url)
                              }
                          })
            PermissionRow(title: Text(String(localized: "Location")),
                          note: Text(String(localized: "Puts the weather widget on your current city instead of the first saved one.")),
                          isGranted: locationGranted,
                          grant: { PermissionRow.openPrivacy("Privacy_LocationServices") })
            Divider()
            cityRow
        }
        // Grants can change in System Settings while this act is up, so they are re-read once a
        // second. As a `task` rather than `Timer.publish(...).autoconnect()`: the loop lives and dies
        // with the act (no guard needed to scope it), and it keeps no Combine publisher on the view.
        .task {
            while !Task.isCancelled {
                refreshGrants()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        // 用户停在这一幕就是同意被问：一次把全部权限问完，之后各处不再弹。
        //
        // `DOCK_WELCOME_NOPROMPTS=1` 把这一幕变成**只读**：不跑那一趟请求，也不画 `Grant` 按钮，
        // 这样一次供截图用的启动不可能弹出任何 TCC 面板（连误点都不会）。行状态仍然来自
        // 不弹窗的探测函数。
        .task {
            guard !DebugSwitch.welcomeGuideNoPrompts.isEnabled() else { return }
            await requestEveryPermissionOnce()
        }
        .environment(\.permissionRowsAreInert, DebugSwitch.welcomeGuideNoPrompts.isEnabled())
    }

    /// Act 5 — the daily rhythm: how it starts, and what opens the launcher.
    private var rhythmAct: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer(minLength: 26)
            actTitle(String(localized: "Daily rhythm"),
                     subtitle: String(localized: "Start with KatiKati at login, and choose what opens the Launcher."))
            PermissionRow(title: Text(String(localized: "Open at Login")),
                          note: Text(String(localized: "Starts KatiKati when you log in to this Mac.")),
                          isGranted: loginItemEnabled,
                          grant: { setLoginItem(enabled: true) })
            Divider()
            Toggle(String(localized: "Double-tap ⌘ opens the Launcher"), isOn: Binding(
                get: { launcherOn ?? layout.launcherDoubleTap },
                set: { launcherOn = $0; layout.onSetLauncherDoubleTap($0) }
            ))
            Toggle(String(localized: "Show a clipboard toast in the Notch"), isOn: Binding(
                get: { toastOn ?? layout.clipboardToastEnabled },
                set: { toastOn = $0; layout.onSetClipboardToast($0) }
            ))
            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Launcher shortcut"))
                        .font(.callout.weight(.medium))
                    Text(String(localized: "Press the chip to see what it does — nothing is recorded."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button {
                    practiceTaps += 1
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "command")
                            .font(.system(size: 11, weight: .semibold))
                        Text(verbatim: (launcherOn ?? layout.launcherDoubleTap) ? "⌘ ⌘" : "⌥ Space")
                            .font(.system(size: 12, weight: .semibold))
                            .monospaced()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(practiceTaps % 2 == 0 ? 0.06 : 0.14))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(practiceTaps % 2 == 0 ? 0.35 : 0.75), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: practiceTaps)
                .accessibilityLabel(Text(String(localized: "Press to test")))
            }
            Text(String(localized: "The Launcher itself lives on the bar’s left button — this is only the keyboard way in."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            actTail
        }
    }

    /// Act 6 — the close.
    private var finaleAct: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer(minLength: 26)
            KineticWords(phrase: String(localized: "You’re all set."),
                         font: .system(size: 38, weight: .semibold, design: .rounded))
            Text(String(localized: "Everything here can be changed later in Settings, or from the menu bar item."))
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if offersNativeDock {
                Text(String(localized: "The screen will flash once when you apply this."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actTail
        }
    }

    // MARK: - Pieces

    private func actTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            KineticWords(phrase: title, font: .system(size: 26, weight: .semibold, design: .rounded))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }

    private func tierHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    /// The four tints the Feel act offers. Not every preset: four fits one row at 88 pt a swatch, and
    /// these are the ones a first run is most likely to want.
    static let themeChoices: [DockThemeStyle] = [.auto, .translucent, .obsidianDark, .auroraGlow]

    /// One edge choice. Selected is the accent fill with a white label — the same weight `Continue`
    /// carries — and unselected is the panel's own translucent plate, so both states clear 4.5:1
    /// against the glass.
    private func edgeChip(_ title: String, _ placement: StripPlacement) -> some View {
        let isPicked = (pickedPlacement ?? layout.initialPlacement) == placement
        return Button {
            pickedPlacement = placement
            layout.onPickPlacement(placement)
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isPicked ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Capsule().fill(isPicked ? Color.accentColor : Color.primary.opacity(0.10)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(isPicked ? 0 : 0.16), lineWidth: 0.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }

    private var sectionGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                  spacing: 8) {
            ForEach(Self.configurableSections, id: \.self) { section in
                let isOn = currentSections.contains(section)
                Button {
                    var next = currentSections
                    if isOn { next.remove(section) } else { next.insert(section) }
                    visibleSections = next
                    layout.onToggleSection(section, !isOn)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: DockLivePreviewStrip.symbol(for: section))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isOn ? (section == .ai ? .cyan : .accentColor) : .secondary)
                        Text(verbatim: WidgetCatalog.localizedTitle(for: section))
                            .font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 11))
                            .foregroundStyle(isOn ? Color.accentColor : Color.secondary.opacity(0.5))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(isOn ? 0.10 : 0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(isOn ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var cityRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Weather"))
                .font(.callout.weight(.semibold))
            Text(String(localized: "Pick the city the weather widget shows. Without one, a fresh bar shows an empty pill."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                TextField(String(localized: "Search for a city"), text: $cityQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { cityResults = await layout.searchCities(cityQuery) } }
                Button(String(localized: "Use Current Location")) {
                    pickedCity = .current
                    layout.onPickCity(.current)
                }
                .fixedSize()
            }
            if !cityResults.isEmpty {
                ForEach(Array(cityResults.prefix(4))) { city in
                    Button {
                        pickedCity = .city(city.id)
                        layout.onAddCity(city)
                        cityQuery = ""
                        cityResults = []
                    } label: {
                        Text(verbatim: city.subtitle.isEmpty ? city.name : "\(city.name) — \(city.subtitle)")
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let pickedCity {
                Label {
                    Text(verbatim: {
                        switch pickedCity {
                        case .current: return String(localized: "Current location")
                        case let .city(id): return cityResults.first { $0.id == id }?.name ?? String(localized: "Saved city")
                        }
                    }())
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .font(.caption)
                .foregroundStyle(.green)
            }
        }
        .padding(.top, 2)
    }

    private func wingPicker(label: Text, placement: DockWingPlacement, current: DockWidgetPresetType) -> some View {
        HStack(spacing: 6) {
            label.font(.callout.weight(.medium))
            Picker(selection: Binding(
                get: { current },
                set: { picked in
                    wingsConfig = currentWings.assigning(picked, to: placement)
                    layout.onPickWing(placement, picked)
                }
            )) {
                ForEach(DockWidgetPresetType.allCases) { preset in
                    Text(verbatim: preset.localizedTitle).tag(preset)
                }
            } label: { EmptyView() }.labelsHidden().pickerStyle(.menu).fixedSize()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(String(localized: "Hide the Dock (auto-hide, and don’t wake it at the bottom edge)"), isOn: $selection.hidesDock)
            Toggle(String(localized: "Use the scale effect when minimizing"), isOn: $selection.usesScaleMinimizeEffect)
            Toggle(String(localized: "Minimize windows into their app icon"), isOn: $selection.minimizesIntoAppIcon)
        }
    }

    /// 后路必须写出来（owner 2026-08-20 明确要求）：这一步会让系统 Dock 彻底不出现，
    /// 不告诉用户怎么唤回来，等于让他觉得自己把 Dock 弄丢了。
    ///
    /// ⚠️ `⌥⌘D` 归 macOS 所有，这里**只能当纯文字写**。钨极全局热键用的是 ⌥⇧⌘D；
    /// 把 ⌥⌘D 注册成 `keyEquivalent` 会把系统的快捷键抢过来（见 AGENTS.md 的热键规则）。
    ///
    /// OB-2：旧实现里这段取消勾选时只能变淡、不能消失，因为窗口高度是建窗时量死的。
    /// 固定尺寸之后这条限制没有了——现在它是真的收起来。
    @ViewBuilder
    private var comeBackNote: some View {
        if selection.hidesDock {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Want the Dock back?"))
                    .font(.callout.weight(.semibold))
                Text(String(localized: "Press ⌥⌘D at any time — that’s macOS’s own shortcut for showing and hiding the Dock. You can also change this later from the KatiKati menu bar item."))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
            }
            .transition(.opacity)
        }
    }

    // MARK: - Permission pass

    /// 串行请求（macOS 一次只显示一个系统面板，并发请求会被直接丢弃）。每一步都先看状态：
    /// 已经决定过的权限不再问，所以重开引导、或在已授权的机器上跑，等于什么都没发生。
    private func requestEveryPermissionOnce() async {
        guard !didRequestAllPermissions else { return }
        didRequestAllPermissions = true
        NSApp.activate(ignoringOtherApps: true)

        func pause(_ nanoseconds: UInt64) async { try? await Task.sleep(nanoseconds: nanoseconds) }

        PermissionBootstrap.trace("begin")
        if !CGPreflightScreenCaptureAccess() {
            PermissionBootstrap.trace("screenRecording: request")
            _ = CGRequestScreenCaptureAccess()
            await pause(900_000_000)
        } else {
            PermissionBootstrap.trace("screenRecording: already granted")
        }
        if !AXIsProcessTrusted() {
            PermissionBootstrap.trace("accessibility: request")
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            await pause(900_000_000)
        } else {
            PermissionBootstrap.trace("accessibility: already granted")
        }
        if !CGPreflightListenEventAccess() {
            PermissionBootstrap.trace("inputMonitoring: request")
            _ = CGRequestListenEventAccess()
            await pause(900_000_000)
        } else {
            PermissionBootstrap.trace("inputMonitoring: already granted")
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            PermissionBootstrap.trace("microphone: request")
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                AVCaptureDevice.requestAccess(for: .audio) { _ in continuation.resume() }
            }
            await pause(600_000_000)
        } else {
            PermissionBootstrap.trace("microphone: already decided")
        }
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            PermissionBootstrap.trace("camera: request")
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                AVCaptureDevice.requestAccess(for: .video) { _ in continuation.resume() }
            }
            await pause(600_000_000)
        } else {
            PermissionBootstrap.trace("camera: already decided")
        }
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                Self.eventStore.requestFullAccessToEvents { _, _ in continuation.resume() }
            }
            await pause(600_000_000)
        }
        if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                Self.eventStore.requestFullAccessToReminders { _, _ in continuation.resume() }
            }
            await pause(600_000_000)
        }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            PermissionBootstrap.trace("notifications: request")
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            await pause(600_000_000)
        } else {
            PermissionBootstrap.trace("notifications: already decided")
        }
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestAlwaysAuthorization()
        }
        // Login Item has no system prompt, so Act 5 offers the row rather than registering behind
        // the owner's back; it is still reported here so the trace covers every item on the list.
        PermissionBootstrap.trace("offer loginItem")
        // Every prompt this app is allowed to raise has now been raised once. Feature code reads
        // this and reports status instead of asking again.
        PermissionBootstrap.markCompleted()
        PermissionBootstrap.trace("completed")
    }

    /// Registering can succeed outright, or macOS parks the app in Login Items for approval. The pane
    /// is where that approval happens, so a pending registration opens it instead of showing a check.
    private func setLoginItem(enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            PermissionBootstrap.trace("loginItem failed: \(error.localizedDescription)")
        }
        if SMAppService.mainApp.status == .requiresApproval,
           let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
        loginItemEnabled = SMAppService.mainApp.status == .enabled
        PermissionBootstrap.trace("loginItem \(loginItemEnabled ? "on" : "off")")
    }

    /// Every row's status, from the non-prompting probes only — nothing here can raise a panel.
    ///
    /// Notifications is the one asynchronous read, so it goes out as its own short task: the once-a-
    /// second poll never blocks on it, and it reads the injected
    /// `WelcomeGuideLayoutContext.notificationsAuthorized` instead of touching UserNotifications.
    private func refreshGrants() {
        accessibilityGranted = AXIsProcessTrusted()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        inputMonitoringGranted = CGPreflightListenEventAccess()
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        calendarGranted = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        remindersGranted = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
        Task {
            let granted = await layout.notificationsAuthorized()
            await MainActor.run { notificationsGranted = granted }
        }
        locationGranted = locationManager.authorizationStatus == .authorizedAlways
    }
}

/// `DOCK_WELCOME_NOPROMPTS` reaches the rows through the environment, not a new parameter: the same
/// `PermissionRow` is drawn by Settings (`PermissionsSettingsBlock`), and that copy must keep its
/// Grant buttons.
private struct PermissionRowsInertKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True only inside the guide's Access act under `DOCK_WELCOME_NOPROMPTS`.
    var permissionRowsAreInert: Bool {
        get { self[PermissionRowsInertKey.self] }
        set { self[PermissionRowsInertKey.self] = newValue }
    }
}

/// One permission: what it is, why it helps, and either a check or a Grant button.
struct PermissionRow: View {
    let title: Text
    let note: Text
    let isGranted: Bool
    let grant: () -> Void

    @Environment(\.permissionRowsAreInert) private var isInert

    /// A denied permission can't re-prompt, so Grant also sends the user to its Privacy pane.
    static func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                title.font(.body.weight(.semibold))
                note.font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if isGranted {
                Label { Text(String(localized: "Granted")) } icon: { Image(systemName: "checkmark.circle.fill") }
                    .foregroundStyle(.green)
                    .fixedSize()
            } else if !isInert {
                Button(String(localized: "Grant"), action: grant).fixedSize()
            }
        }
    }
}
