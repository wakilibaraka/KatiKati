import AppKit
import AVFoundation
import SwiftUI

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
}

struct WelcomeGuideView: View {
    let layout: WelcomeGuideLayoutContext
    let onApply: (WelcomeGuideSelection) -> Void
    let onDismiss: () -> Void

    @State private var selection = WelcomeGuideSelection.recommended
    @State private var step = WelcomeGuideStep.first
    @State private var pickedMode: BarLayoutMode?
    @State private var pickedStyleID: String?
    @State private var pickedTheme: DockThemeStyle?

    /// A short, varied row from the Appearance grid; the full set stays in Settings › Appearance.
    private static let onboardingThemes: [DockThemeStyle] = [
        .auto, .translucent, .titaniumFrost, .deepOcean, .forestMoss, .emberSunset, .cyberpunkGlass,
    ]
    @State private var notchOn: Bool?
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var screenRecordingGranted = CGPreflightScreenCaptureAccess()
    @State private var inputMonitoringGranted = CGPreflightListenEventAccess()
    @State private var microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
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
        case .pickLayout: pickLayoutStep
        case .liveIsland: liveIslandStep
        case .permissions: permissionsStep
        case .dockSettings: dockSettingsStep
        }
    }

    private var currentMode: BarLayoutMode { pickedMode ?? layout.initialMode }

    private var pickLayoutStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Pick a Layout")
                .font(.title2.weight(.semibold))
            Text("Choose how the bar sits at the bottom of your screen. You can change it any time in Settings or from the menu bar.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DockStylePicker(selection: pickedStyleID ?? layout.initialStyleID, inputs: layout.inputs,
                            thumbnailSize: CGSize(width: 74, height: 32)) { style in
                pickedStyleID = style.id
                pickedMode = style.mode
                layout.onPickStyle(style)
            }
            LayoutModeDetail(mode: currentMode)
                .font(.callout)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)
            Text("Theme").font(.headline)
            HStack(spacing: 8) {
                ForEach(Self.onboardingThemes, id: \.token) { theme in
                    let isSelected = theme == (pickedTheme ?? layout.initialTheme)
                    Button {
                        pickedTheme = theme
                        layout.onPickTheme(theme)
                    } label: {
                        ThemeSwatch(style: theme)
                            .frame(width: 52, height: 32)
                            .padding(3)
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
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

    private var liveIslandStep: some View {
        let binding = Binding(get: { notchOn ?? layout.notchEnabled },
                              set: { notchOn = $0; layout.onNotchToggle($0) })
        return VStack(alignment: .leading, spacing: 18) {
            Text("Dynamic Notch")
                .font(.title2.weight(.semibold))
            Toggle("Show the Dynamic Notch", isOn: binding)
            NotchPreview(skin: layout.notchSkin, isEnabled: notchOn ?? layout.notchEnabled)
            Text("You can change this later in Settings › Notch.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Divider()
            HStack(spacing: 8) {
                Spacer()
                Button("Back") { if let previous = step.previous { step = previous } }
                    .fixedSize()
                Button("Continue") { if let next = self.step.next { self.step = next } }
                    .keyboardShortcut(.defaultAction)
                    .fixedSize()
            }
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Permissions")
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
            Spacer(minLength: 0)
            Divider()
            HStack(spacing: 8) {
                Spacer()
                Button("Back") { if let previous = step.previous { step = previous } }
                    .fixedSize()
                Button("Continue") { if let next = self.step.next { self.step = next } }
                    .keyboardShortcut(.defaultAction)
                    .fixedSize()
            }
        }
        .onReceive(permissionTimer) { _ in
            guard step == .permissions else { return }
            accessibilityGranted = AXIsProcessTrusted()
            screenRecordingGranted = CGPreflightScreenCaptureAccess()
            inputMonitoringGranted = CGPreflightListenEventAccess()
            microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        }
    }

    private var dockSettingsStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            // 图标撤走之后，标题得自己撑住这一屏的重心，所以比原来大一号。
            Text("Recommended Dock Settings")
                .font(.title2.weight(.semibold))

            options

            comeBackNote

            // 去掉色块之后，这条线是「建议区 / 行动区」唯一的分界。
            Divider()

            HStack(spacing: 8) {
                // 唯一的闪屏预告。放在手指要点的地方，而不是段落里；**无条件显示**——
                // 随勾选出现/消失会让窗口高度对不上内容（高度只在建窗时量一次）。
                // The note yields, the buttons never do: without `fixedSize()` the HStack
                // squeezes the primary button to "Apply Recommended Set…" even in English
                // (measured 173pt of the 207pt it needs) while the note keeps free space.
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
