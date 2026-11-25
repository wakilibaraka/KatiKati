import AppKit
import AVFoundation
import CoreLocation
import EventKit
import SwiftUI
import UserNotifications

/// 窗口根视图。和权限引导同一个结构：滚动条平时不出现，窗口高度由内容自然高度决定，
/// 只有被屏幕高度截断时才真的需要滚。
struct WelcomeGuideWindowContent: View {
    let layout: WelcomeGuideLayoutContext
    let onApply: (WelcomeGuideSelection) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ScrollView(.vertical) {
            WelcomeGuideView(layout: layout, onApply: onApply, onDismiss: onDismiss)
        }
        .frame(width: WelcomeGuideView.contentWidth)
        // 58b: an overlay on purpose — the window height is measured once at open, so the intro may not add a row.
        .overlay { WelcomeIntroGlass() }
    }
}

/// 58b: the welcome window's native glass intro. A small lens springs open into the card and dissolves, revealing
/// the first step; a click or the 1.2 s run ends it (keys still reach the step behind it, so Return keeps working).
/// Reduce Motion gets a plain 0.2 s fade instead of motion.
/// No third-party code: a material, a gradient ring and one spring.
struct WelcomeIntroGlass: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var open = false
    @State private var gone = false

    var body: some View {
        if !gone {
            GeometryReader { geo in
                let size = geo.size
                let lens = min(size.width, size.height) * 0.22
                ZStack {
                    RoundedRectangle(cornerRadius: open ? 18 : lens / 2, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: open ? 18 : lens / 2, style: .continuous)
                                .strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.10)],
                                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                                              lineWidth: 1)
                        )
                        .frame(width: open ? size.width : lens, height: open ? size.height : lens)
                        .shadow(color: .black.opacity(open ? 0.04 : 0.28), radius: open ? 6 : 22, y: 5)
                }
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .onTapGesture { end() }
            }
            .accessibilityHidden(true)
            .task { await play() }
        }
    }

    private func play() async {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) { open = true }
            try? await Task.sleep(for: .seconds(0.2))
            end()
            return
        }
        withAnimation(.spring(response: 0.52, dampingFraction: 0.74)) { open = true }
        try? await Task.sleep(for: .seconds(0.8))
        end()
    }

    private func end() {
        guard !gone else { return }
        withAnimation(.easeOut(duration: 0.3)) { gone = true }
    }
}

/// 首次运行的一次性引导：把系统 Dock 让给钨极的三条推荐设置。
///
/// 三条同属「系统 Dock 该怎么配合钨极」这**一件**事，所以放同一屏（owner 2026-08-28 定，
/// 扩展了 2026-08-20「一屏只讲一件事」——那条挡的是把 Dock 和抽屉两个不相干主题塞一起）。
/// 抽屉空状态的可发现性仍然是另一件事，有它自己的待办卡，不塞进来。
///
/// 三条各自可勾：这是在写别人的系统偏好，用户该能只要 Dock 隐藏、不改最小化动画。
///
/// ⚠️ **这一屏的「素」是 owner 2026-08-28 看过实机后一步步定的，不是没做完**：说明性文字
/// （副标题、开头总述、每条勾选下面的灰色注解）一条不留，标题左边的图标去掉，⌥⌘D 那段的
/// 灰底方块也去掉。分区只靠间距和一条分隔线。看到光秃秃的开关别「好心」把图标、色块或注解
/// 补回来。唯一留下的说明是按钮行左侧那句闪屏预告。
/// What the pick-a-layout step needs from the store, passed in so the probe and the live
/// window render the same thing.
struct WelcomeGuideLayoutContext {
    var initialMode: BarLayoutMode
    var inputs: LayoutThumbnailModel.Inputs
    var onPick: (BarLayoutMode) -> Void
    /// Phase 11f: the step offers dock styles and a theme row (theme never rides on a style).
    var initialStyleID: String? = nil
    var onPickStyle: (DockStyle) -> Void = { _ in }
    var initialTheme: DockThemeStyle = .auto
    var onPickTheme: (DockThemeStyle) -> Void = { _ in }
    /// The notch Live Island switch (default on); written to the store as soon as it is flipped.
    var notchEnabled = true
    /// Read-only: which look the step's demo draws. The guide never changes the skin itself.
    var notchSkin: LiveIslandSkin = .boring
    var onNotchToggle: (Bool) -> Void = { _ in }
    var initialVisibleSections: Set<BarSection> = Set(BarSection.defaultOrder)
    var onToggleSection: (BarSection, Bool) -> Void = { _, _ in }
    var initialWings: DockWingsConfiguration = .default
    var onPickWing: (DockWingPlacement, DockWidgetPresetType) -> Void = { _, _ in }
    /// DP-8 step 1: the Bottom / Left / Right edge, written live.
    var initialPlacement: StripPlacement = .bottom
    var onPickPlacement: (StripPlacement) -> Void = { _ in }
    /// DP-8 step 2: the weather city, asked for here so a fresh bar never shows an empty pill.
    var initialCitySelection: WeatherLocationSelection = .current
    var searchCities: (String) async -> [SavedCity] = { _ in [] }
    var onAddCity: (SavedCity) -> Void = { _ in }
    var onPickCity: (WeatherLocationSelection) -> Void = { _ in }
    /// DP-8 step 2: AI Tracking is an explicit opt-in, off by default.
    var aiTrackingEnabled = false
    var onSetAITracking: (Bool) -> Void = { _ in }
    /// DP-8 step 3: the two triggers the guide offers.
    var launcherDoubleTap = false
    var onSetLauncherDoubleTap: (Bool) -> Void = { _ in }
    var clipboardToastEnabled = ClipboardToastDefaults.enabledByDefault
    var onSetClipboardToast: (Bool) -> Void = { _ in }
    /// DO-9: modular App Icon preset & Detached Capsule slot pickers.
    var initialAppIconPreset: AppIconPresentationPreset = .appPills
    var onPickAppIconPreset: (AppIconPresentationPreset) -> Void = { _ in }
    var initialTrailingCapsule: DockSlotItem? = .controlCenter
    var onPickTrailingCapsule: (DockSlotItem?) -> Void = { _ in }
}

struct WelcomeGuideView: View {
    let layout: WelcomeGuideLayoutContext
    let onApply: (WelcomeGuideSelection) -> Void
    let onDismiss: () -> Void

    @State private var selection = WelcomeGuideSelection.recommended
    @State private var step = WelcomeGuideStep.first
    @State private var pickedMode: BarLayoutMode?
    @State private var pickedStyleID: String?
    @State private var pickedPlacement: StripPlacement?
    @State private var pickedAppIconPreset: AppIconPresentationPreset?
    @State private var pickedTrailingCapsule: DockSlotItem??
    @State private var cityQuery = ""
    @State private var cityResults: [SavedCity] = []
    @State private var pickedCity: WeatherLocationSelection?
    @State private var aiOn: Bool?
    @State private var launcherOn: Bool?
    @State private var toastOn: Bool?
    @State private var notchOn: Bool?
    @State private var visibleSections: Set<BarSection>?
    @State private var wingsConfig: DockWingsConfiguration?
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var screenRecordingGranted = CGPreflightScreenCaptureAccess()
    @State private var inputMonitoringGranted = CGPreflightListenEventAccess()
    @State private var microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @State private var calendarGranted = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    @State private var remindersGranted = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    @State private var notificationsGranted = false
    @State private var locationGranted = false
    /// One onboarding pass asks for everything it needs; panels then never prompt mid-task.
    @State private var didRequestAllPermissions = false
    @State private var locationManager = CLLocationManager()
    private static let eventStore = EKEventStore()
    /// Re-reads the four grants once a second, only acted on while the Permissions step is showing.
    private let permissionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// 宽度固定：窗口高度由 `fittingSize` 决定，宽度不能跟着文案长短抖。
    /// 取值和权限引导一致，两扇引导窗口该长得像一家人。
    static let contentWidth: CGFloat = 520

    /// Both steps are always laid out, stacked; only the current one is visible. The window
    /// height is measured once at creation (`AppDelegate.showWelcomeWindow`), so the
    /// stack's height = the taller step and switching steps never changes it.
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(WelcomeGuideStep.allCases, id: \.self) { candidate in
                let isCurrent = candidate == step
                stepView(candidate)
                    .opacity(isCurrent ? 1 : 0)
                    .allowsHitTesting(isCurrent)
                    .accessibilityHidden(!isCurrent)
            }
        }
        .padding(28)
        .frame(width: Self.contentWidth, alignment: .leading)
        .animation(.easeInOut(duration: 0.15), value: step)
    }

    @ViewBuilder
    private func stepView(_ step: WelcomeGuideStep) -> some View {
        switch step {
        case .layout: layoutStep
        case .widgets: widgetsStep
        case .permissions: permissionsStep
        }
    }

    private var currentSections: Set<BarSection> { visibleSections ?? layout.initialVisibleSections }
    private var currentWings: DockWingsConfiguration { wingsConfig ?? layout.initialWings }
    private var configurableSections: [BarSection] { BarSection.canonicalOrder.filter { $0 != .apps } }

    private var currentMode: BarLayoutMode { pickedMode ?? layout.initialMode }

    /// DP-8 step 1: four look cards (Wide preselected) and the edge the bar sits on.
    private var layoutStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Layout & Edge")
                .font(.title2.weight(.semibold))
            Text("Pick a look and the screen edge it sits on. You can change both any time in Settings or from the menu bar.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DockStylePicker(selection: pickedStyleID ?? layout.initialStyleID, inputs: layout.inputs,
                            thumbnailSize: CGSize(width: 74, height: 32),
                            styles: DockStyle.onboardingCards) { style in
                pickedStyleID = style.id
                pickedMode = style.mode
                layout.onPickStyle(style)
            }
            LayoutModeDetail(mode: currentMode)
                .font(.callout)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)
            Picker("Edge", selection: Binding(
                get: { pickedPlacement ?? layout.initialPlacement },
                set: { pickedPlacement = $0; layout.onPickPlacement($0) }
            )) {
                Text("Bottom").tag(StripPlacement.bottom)
                Text("Left").tag(StripPlacement.left)
                Text("Right").tag(StripPlacement.right)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            HStack(spacing: 8) {
                Text("App Icons")
                    .font(.callout.weight(.medium))
                Spacer(minLength: 8)
                Picker("App Icons", selection: Binding(
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
            Divider()
            HStack(spacing: 8) {
                Spacer()
                Button("Continue") { if let next = self.step.next { self.step = next } }
                    .keyboardShortcut(.defaultAction)
                    .fixedSize()
            }
        }
    }

    /// DP-8 step 2: widgets, wings, the weather city, the AI opt-in and the Dynamic Notch row.
    private var widgetsStep: some View {
        let activeOrder = BarSection.canonicalOrder.filter { $0 == .apps || currentSections.contains($0) }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Widgets & Wings")
                .font(.title2.weight(.semibold))
            DockLivePreviewStrip(mode: currentMode, visibleOrder: activeOrder, wings: currentWings)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(configurableSections, id: \.self) { section in
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
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(isOn ? 0.08 : 0.03)))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(isOn ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
            HStack(spacing: 12) {
                wingPicker(label: Text("Left Wing"), placement: .leftWing, current: currentWings.left.preset)
                wingPicker(label: Text("Right Wing"), placement: .rightWing, current: currentWings.right.preset)
            }
            HStack(spacing: 8) {
                Text("Detached Capsule")
                    .font(.callout.weight(.medium))
                Spacer(minLength: 8)
                Picker("Detached Capsule", selection: Binding<DockSlotItem?>(
                    get: { pickedTrailingCapsule ?? layout.initialTrailingCapsule },
                    set: { picked in
                        pickedTrailingCapsule = picked
                        layout.onPickTrailingCapsule(picked)
                    }
                )) {
                    Text(DockSlotItem.controlCenter.title).tag(DockSlotItem?.some(.controlCenter))
                    Text(DockSlotItem.backgroundApps.title).tag(DockSlotItem?.some(.backgroundApps))
                    Text(DockSlotItem.trash.title).tag(DockSlotItem?.some(.trash))
                    Text(DockSlotItem.launcher.title).tag(DockSlotItem?.some(.launcher))
                    Text(DockSlotItem.shelf.title).tag(DockSlotItem?.some(.shelf))
                    Text("Off").tag(DockSlotItem?.none)
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            Divider()
            // The city is asked for here: a fresh bar used to show an empty "Add City" pill.
            VStack(alignment: .leading, spacing: 6) {
                Text("Weather").font(.callout.weight(.semibold))
                HStack(spacing: 8) {
                    TextField("Search for a city", text: $cityQuery)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { cityResults = await layout.searchCities(cityQuery) } }
                    Button("Use Current Location") {
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
            }
            Divider()
            VStack(alignment: .leading, spacing: 3) {
                Toggle("AI Tracking", isOn: Binding(
                    get: { aiOn ?? layout.aiTrackingEnabled },
                    set: { aiOn = $0; layout.onSetAITracking($0) }
                ))
                Text("Off unless you turn it on: it reads window titles on this Mac and spends a little CPU to keep the AI chip current.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle("Show the Dynamic Notch", isOn: Binding(
                get: { notchOn ?? layout.notchEnabled },
                set: { notchOn = $0; layout.onNotchToggle($0) }
            ))
            Spacer(minLength: 0)
            Divider()
            HStack(spacing: 8) {
                Spacer()
                Button("Back") { if let previous = step.previous { step = previous } }.fixedSize()
                Button("Continue") { if let next = self.step.next { self.step = next } }.keyboardShortcut(.defaultAction).fixedSize()
            }
        }
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

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Permissions & Triggers")
                .font(.title2.weight(.semibold))
            Text("These permissions help KatiKati work properly. You can change them any time in System Settings › Privacy & Security.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            PermissionRow(title: Text("Accessibility"),
                          note: Text("Shows your open windows as chips and lets you switch to them."),
                          isGranted: accessibilityGranted,
                          grant: {
                              _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
                          })
            PermissionRow(title: Text("Screen Recording"),
                          note: Text("Shows live window thumbnails in hover previews. Without it, previews show titles only."),
                          isGranted: screenRecordingGranted,
                          grant: { _ = CGRequestScreenCaptureAccess(); PermissionRow.openPrivacy("Privacy_ScreenCapture") })
            PermissionRow(title: Text("Input Monitoring"),
                          note: Text("Only for the optional Hyper key. Skip it if you won’t use that."),
                          isGranted: inputMonitoringGranted,
                          grant: { _ = CGRequestListenEventAccess(); PermissionRow.openPrivacy("Privacy_ListenEvent") })
            // 58a: the fourth grant. Both the recorder and the camera mirror ask for it, and without it macOS
            // answers with silence rather than an error, so the step has to name it.
            PermissionRow(title: Text("Microphone"),
                          note: Text("Only for the voice recorder and the camera mirror. Nothing records until you start one."),
                          isGranted: microphoneGranted,
                          grant: {
                              AVCaptureDevice.requestAccess(for: .audio) { _ in }
                              PermissionRow.openPrivacy("Privacy_Microphone")
                          })
            // 2026-11-25: the camera is the last grant that used to appear from a panel rather than
            // here (opening the camera mirror). It joins the one pass, so it is asked once.
            PermissionRow(title: Text("Camera"),
                          note: Text("Only for the camera mirror. Nothing turns the camera on until you open it."),
                          isGranted: cameraGranted,
                          grant: {
                              AVCaptureDevice.requestAccess(for: .video) { _ in }
                              PermissionRow.openPrivacy("Privacy_Camera")
                          })
            // 58c: the four grants that used to pop up later, from whichever panel happened to need
            // them first (calendar on the panel, location on the weather chip, notifications on the
            // first alarm). They are asked here, once, so the appearance is predictable.
            PermissionRow(title: Text("Calendar"),
                          note: Text("Shows today’s events in the panel, the notch and the command bar."),
                          isGranted: calendarGranted,
                          grant: { PermissionRow.openPrivacy("Privacy_Calendars") })
            PermissionRow(title: Text("Reminders"),
                          note: Text("Lists your reminders beside today’s events."),
                          isGranted: remindersGranted,
                          grant: { PermissionRow.openPrivacy("Privacy_Reminders") })
            PermissionRow(title: Text("Notifications"),
                          note: Text("Delivers alarms and live-event banners while KatiKati is in the background."),
                          isGranted: notificationsGranted,
                          grant: {
                              if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                                  NSWorkspace.shared.open(url)
                              }
                          })
            PermissionRow(title: Text("Location"),
                          note: Text("Puts the weather widget on your current city instead of the first saved one."),
                          isGranted: locationGranted,
                          grant: { PermissionRow.openPrivacy("Privacy_LocationServices") })
            Divider()
            // DP-8: the two triggers the guide offers, both live.
            Toggle("Double-tap ⌘ opens the Launcher", isOn: Binding(
                get: { launcherOn ?? layout.launcherDoubleTap },
                set: { launcherOn = $0; layout.onSetLauncherDoubleTap($0) }
            ))
            Toggle("Show a clipboard toast in the Notch", isOn: Binding(
                get: { toastOn ?? layout.clipboardToastEnabled },
                set: { toastOn = $0; layout.onSetClipboardToast($0) }
            ))
            Divider()
            Text("Recommended Dock Settings")
                .font(.headline)
            options
            comeBackNote
            Spacer(minLength: 0)
            Divider()
            HStack(spacing: 8) {
                Text("The screen will flash once when you apply this.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Back") { if let previous = step.previous { step = previous } }
                    .fixedSize()
                Button("Not Now") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                    .fixedSize()
                Button("Apply Recommended Settings") { onApply(selection) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection.isEmpty)
                    .fixedSize()
            }
        }
        .onReceive(permissionTimer) { _ in
            guard step == .permissions else { return }
            accessibilityGranted = AXIsProcessTrusted()
            screenRecordingGranted = CGPreflightScreenCaptureAccess()
            inputMonitoringGranted = CGPreflightListenEventAccess()
            microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            refreshCalendarGrants()
            refreshNotificationsGranted()
            locationGranted = locationManager.authorizationStatus == .authorizedAlways
        }
        // 用户停在「Permissions」这一屏就是同意被问：一次把全部权限问完，之后各处不再弹。
        .task(id: step) {
            guard step == .permissions else { return }
            await requestEveryPermissionOnce()
        }
    }

    /// 串行请求（macOS 一次只显示一个系统面板，并发请求会被直接丢弃）。每一步都先看状态：
    /// 已经决定过的权限不再问，所以重开引导、或在已授权的机器上跑，等于什么都没发生。
    private func requestEveryPermissionOnce() async {
        guard !didRequestAllPermissions else { return }
        didRequestAllPermissions = true
        NSApp.activate(ignoringOtherApps: true)

        func pause(_ nanoseconds: UInt64) async { try? await Task.sleep(nanoseconds: nanoseconds) }

        if !AXIsProcessTrusted() {
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            await pause(900_000_000)
        }
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
            await pause(900_000_000)
        }
        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
            await pause(900_000_000)
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                AVCaptureDevice.requestAccess(for: .audio) { _ in continuation.resume() }
            }
            await pause(600_000_000)
        }
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                AVCaptureDevice.requestAccess(for: .video) { _ in continuation.resume() }
            }
            await pause(600_000_000)
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
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            await pause(600_000_000)
        }
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestAlwaysAuthorization()
        }
        refreshCalendarGrants()
        refreshNotificationsGranted()
        cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        locationGranted = locationManager.authorizationStatus == .authorizedAlways
        // Every prompt this app is allowed to raise has now been raised once. Feature code reads
        // this and reports status instead of asking again.
        PermissionBootstrap.markCompleted()
    }

    private func refreshCalendarGrants() {
        calendarGranted = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        remindersGranted = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    /// 通知状态只能异步读；每秒一次的轮询里发一个短任务，不阻塞主线程。
    private func refreshNotificationsGranted() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run { notificationsGranted = settings.authorizationStatus == .authorized }
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Hide the Dock (auto-hide, and don’t wake it at the bottom edge)", isOn: $selection.hidesDock)
            Toggle("Use the scale effect when minimizing", isOn: $selection.usesScaleMinimizeEffect)
            Toggle("Minimize windows into their app icon", isOn: $selection.minimizesIntoAppIcon)
        }
    }

    /// 后路必须写出来（owner 2026-08-20 明确要求）：这一步会让系统 Dock 彻底不出现，
    /// 不告诉用户怎么唤回来，等于让他觉得自己把 Dock 弄丢了。
    ///
    /// ⚠️ 取消勾选「隐藏系统 Dock」时**只变淡，不隐藏**：窗口高度是建窗时用一次性探针量死的
    /// （`AppDelegate.showWelcomeWindow`），之后永不重量，任何随勾选增删的视图都会让高度对不上。
    ///
    /// ⚠️ `⌥⌘D` 归 macOS 所有，这里**只能当纯文字写**。钨极全局热键用的是 ⌥⇧⌘D；
    /// 把 ⌥⌘D 注册成 `keyEquivalent` 会把系统的快捷键抢过来（见 AGENTS.md 的热键规则）。
    private var comeBackNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Want the Dock back?")
                .font(.callout.weight(.semibold))
            Text("Press ⌥⌘D at any time — that’s macOS’s own shortcut for showing and hiding the Dock. You can also change this later from the KatiKati menu bar item.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
        }
        .opacity(selection.hidesDock ? 1 : 0.4)
    }
}

/// One permission: what it is, why it helps, and either a check or a Grant button.
struct PermissionRow: View {
    let title: Text
    let note: Text
    let isGranted: Bool
    let grant: () -> Void

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
                Label { Text("Granted") } icon: { Image(systemName: "checkmark.circle.fill") }
                    .foregroundStyle(.green)
                    .fixedSize()
            } else {
                Button("Grant", action: grant).fixedSize()
            }
        }
    }
}
