import AppKit
import SwiftUI

/// Phase 8b-7 — Settings rows for the Live Island: where it shows (dock capsule, notch) and where its
/// event alerts go. Now one card of shared rows, so the block looks the same on every page it sits
/// on. Titles are whole literals (localization gate stays one-to-one).
struct LiveIslandSettingsBlock: View {
    @ObservedObject var store: AppSettingsStore
    @ObservedObject private var timeTravel = SurfaceTimeTravelCoordinator.shared
    @Environment(\.settingsStageVisible) private var stageVisible
    @State private var showPlayground = false

    var body: some View {
        // Rule 8: the preview above the rows is a demo, and it says so. The notch page is not signed
        // off while the Compact skin's own decision is open (`Docs/SETTINGS.md` §4).
        SettingsCard(
            Text("Dynamic Notch"),
            note: Text("The shape preview is a demo: the silhouette only, never live activity.")
        ) {
            if !stageVisible {
                NotchPreview(skin: store.notchSkin, isEnabled: store.notchIslandEnabled)
            }
            SettingsToggleRow(
                Text("Show on Notch"),
                isOn: Binding(get: { store.notchIslandEnabled }, set: { store.setNotchIslandEnabled($0) })
            )
            .help(Text("Shows or hides the Dynamic Notch at the top of the screen."))
            SettingsDivider()
            SettingsRow(Text("Notch Style")) {
                Picker("Notch Style", selection: Binding(get: { store.notchSkin }, set: { store.setNotchSkin($0) })) {
                    Text("Liquid").tag(LiveIslandSkin.liquid)
                    Text("Full").tag(LiveIslandSkin.boring)
                    Text("Compact").tag(LiveIslandSkin.classic)
                    Text("Dynamic Island").tag(LiveIslandSkin.dynamicIsland)
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            .help(Text("Liquid uses metaball physics and detached balls; Full and Compact preserve classic layouts."))
            NotchStylePreviewGallery(
                selected: Binding(get: { store.notchSkin }, set: { store.setNotchSkin($0) }),
                isEnabled: store.notchIslandEnabled
            )
            if store.notchSkin == .boring || store.notchSkin == .classic {
                SettingsDivider()
                NotchAnimationPicker()
            }
            SettingsDivider()
            SettingsToggleRow(
                Text("Focus"),
                isOn: $timeTravel.focusDeferralEnabled
            )
            .help(Text("Focus"))
            SettingsRow(Text("Suggestions")) {
                Button("Reset") {
                    timeTravel.resetSuggestionBackoff()
                }
                .buttonStyle(.bordered)
            }
        }
        if store.notchSkin == .liquid {
            SettingsCard(
                Text("Liquid Notch"),
                note: Text("Optional modules stay off until enabled for zero idle CPU.")
            ) {
                LiquidExtrasSettingsRows()
            }
        }
        if store.notchSkin == .dynamicIsland {
            SettingsCard(Text("Dynamic Island")) {
                SettingsRow(Text("Touch Optimization")) {
                    Picker(
                        "Touch Optimization",
                        selection: Binding(get: { store.islandTouchMode }, set: { store.setIslandTouchMode($0) })
                    ) {
                        Text("Automatic").tag(IslandTouchModeSetting.automatic)
                        Text("Always On").tag(IslandTouchModeSetting.alwaysOn)
                        Text("Off").tag(IslandTouchModeSetting.off)
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
                SettingsDivider()
                SettingsRow(Text("Non-Notch Idle")) {
                    Picker(
                        "Non-Notch Idle",
                        selection: Binding(get: { store.islandNonNotchBehavior }, set: { store.setIslandNonNotchBehavior($0) })
                    ) {
                        Text("Floating Pill").tag(IslandNonNotchIdleBehavior.compactPill)
                        Text("Auto-Hide").tag(IslandNonNotchIdleBehavior.autoHideAtRest)
                        Text("Wide Bar").tag(IslandNonNotchIdleBehavior.wideBarAtRest)
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
                SettingsDivider()
                SettingsToggleRow(
                    Text("OLED Keyline"),
                    isOn: Binding(get: { store.islandKeylineEnabled }, set: { store.setIslandKeylineEnabled($0) })
                )
                SettingsDivider()
                SettingsRow(Text("Island Playground")) {
                    Button(String(localized: "Open Playground")) {
                        showPlayground = true
                    }
                    .buttonStyle(.bordered)
                }
                .sheet(isPresented: $showPlayground) {
                    IslandPlaygroundSheet(store: store)
                }
            }
        }
        NotchBehaviorCard()
        if store.notchSkin == .boring || store.notchSkin == .classic {
            NotchAppearanceCard()
            NotchLayoutCard()
            NotchPagesCard(store: store)
            DroppyCustomizationCard()
            NotchActivityCard()
        }
    }
}

/// NS-2: the notch plate's material. Presets are milled colours, the custom swatch is the owner's own
/// hex, and transparency defaults to 0 % — solid OLED black with no blur pass behind it.
private struct NotchAppearanceCard: View {
    @AppStorage(NotchSurfaceAppearance.StorageKey.preset) private var presetRaw = NotchColorPreset.oledBlack.rawValue
    @AppStorage(NotchSurfaceAppearance.StorageKey.customHex) private var customHex = NotchSurfaceAppearance.defaultCustomHex
    @AppStorage(NotchSurfaceAppearance.StorageKey.transparency) private var transparency = NotchSurfaceAppearance.defaultTransparency

    private var preset: NotchColorPreset { NotchColorPreset(rawValue: presetRaw) ?? .oledBlack }

    private var appearance: NotchSurfaceAppearance {
        NotchSurfaceAppearance(preset: preset, customHex: customHex, transparency: transparency)
    }

    var body: some View {
        SettingsCard(
            Text("Notch Appearance"),
            note: Text("The plate is solid OLED black until you lower its opacity.")
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Color Preset").font(.system(size: 13))
                HStack(spacing: 10) {
                    ForEach(NotchColorPreset.allCases) { swatch($0) }
                    Spacer(minLength: 0)
                }
            }
            .padding(.vertical, 4)
            SettingsDivider()
            SettingsSliderRow(
                Text("Transparency"),
                value: appearance.clampedTransparency * 100,
                range: 0...85,
                step: 1,
                valueText: "\(Int((appearance.clampedTransparency * 100).rounded()))%",
                note: Text("0% keeps the plate solid OLED black; 85% lets the desktop frost through.")
            ) { percent in
                transparency = percent / 100
            }
            SettingsDivider()
            HStack {
                Button("Reset to OLED Black") { reset() }
                    .buttonStyle(SettingsGelButtonStyle())
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder private func swatch(_ option: NotchColorPreset) -> some View {
        if option == .custom {
            ColorPicker("Custom", selection: customColor, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2).padding(-3)
                    .opacity(preset == .custom ? 1 : 0))
                .help(Text("Custom"))
        } else {
            Button { presetRaw = option.rawValue } label: {
                Circle()
                    .fill(option.baseHex.color)
                    .frame(width: 26, height: 26)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                    .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2.5).padding(-3)
                        .opacity(preset == option ? 1 : 0))
            }
            .buttonStyle(.plain)
            .help(Text(verbatim: option.title))
            .accessibilityLabel(Text(verbatim: option.title))
            .accessibilityAddTraits(preset == option ? .isSelected : [])
        }
    }

    /// The custom well writes `#RRGGBB` back into the stored hex, and selects the custom swatch so the
    /// notch immediately wears the picked colour.
    private var customColor: Binding<Color> {
        Binding(
            get: { NotchHexColor.rgba(customHex).color },
            set: { newValue in
                let color = NSColor(newValue).usingColorSpace(.sRGB) ?? .black
                customHex = String(format: "#%02X%02X%02X",
                                   Int((color.redComponent * 255).rounded()),
                                   Int((color.greenComponent * 255).rounded()),
                                   Int((color.blueComponent * 255).rounded()))
                presetRaw = NotchColorPreset.custom.rawValue
            }
        )
    }

    private func reset() {
        presetRaw = NotchColorPreset.oledBlack.rawValue
        customHex = NotchSurfaceAppearance.defaultCustomHex
        transparency = NotchSurfaceAppearance.defaultTransparency
    }
}

/// Pick how the notch opens. Each card loops a miniature notch on that style's real springs, so the
/// illustration is the animation itself. The cards sit under one label so the row stays compact.
private struct NotchAnimationPicker: View {
    @AppStorage(NotchOpenAnimation.defaultsKey) private var stored = NotchOpenAnimation.boring.rawValue
    // The highlight lagged one pick behind the stored value in this pane, so it is local state that the
    // button sets together with the stored value.
    @State private var selected = UserDefaults.standard.string(forKey: NotchOpenAnimation.defaultsKey) ?? NotchOpenAnimation.boring.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "Open Animation").font(.system(size: 13))
            HStack(spacing: 8) {
                ForEach(NotchOpenAnimation.allCases) { style in
                    Button { selected = style.rawValue; stored = style.rawValue } label: {
                        VStack(spacing: 6) {
                            NotchAnimationDemo(style: style)
                            Text(verbatim: style.title).font(.system(size: 11, weight: .semibold))
                            Text(verbatim: style.summary)
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center).lineLimit(2, reservesSpace: true)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(selected == style.rawValue ? 0.1 : 0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: selected == style.rawValue ? 2 : 0))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: "\(style.title): \(style.summary)"))
                    .accessibilityAddTraits(selected == style.rawValue ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct NotchAnimationDemo: View {
    let style: NotchOpenAnimation
    @State private var open = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.settingsStageVisible) private var stageVisible

    var body: some View {
        let spring = open ? style.openSpring : style.closeSpring
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.06))
            UnevenRoundedRectangle(bottomLeadingRadius: open ? 10 : 5, bottomTrailingRadius: open ? 10 : 5, style: .continuous)
                .fill(.black)
                .frame(width: open ? 74 : 40, height: open ? 38 : 9)
                .overlay(alignment: .top) {
                    if open {
                        VStack(spacing: 3) {
                            Capsule().fill(.white.opacity(0.85)).frame(width: 40, height: 4)
                            Capsule().fill(.white.opacity(0.4)).frame(width: 28, height: 3)
                        }
                        .padding(.top, 12)
                        .transition(reveal)
                    }
                }
        }
        .frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .animation(reduceMotion ? nil : .spring(response: spring.response, dampingFraction: spring.dampingRatio), value: open)
        .task(id: stageVisible && !reduceMotion) {
            guard stageVisible, !reduceMotion else {
                open = false
                return
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.3))
                if !Task.isCancelled, NSApp.isActive { open.toggle() }
            }
        }
        .accessibilityHidden(true)
    }

    private var reveal: AnyTransition {
        switch style.reveal {
        case .fade: return .opacity
        case .pour: return .scale(scale: 0.92, anchor: .top).combined(with: .opacity)
        case .drop: return .opacity.combined(with: .offset(y: -6))
        case .pop: return .scale(scale: 0.85, anchor: .top).combined(with: .opacity)
        }
    }
}

/// Opening behavior, timings, haptics and display, after vorssaint-utils' Behavior tab. Copy is verbatim
/// (not localized yet), like the Open Animation picker above.
private struct NotchBehaviorCard: View {
    @AppStorage(NotchOpenMode.defaultsKey) private var mode = NotchOpenMode.hover.rawValue
    @AppStorage(NotchBehavior.hoverDelayKey) private var hoverDelay = NotchBehavior.defaultHoverDelay
    @AppStorage(NotchBehavior.closeDelayKey) private var closeDelay = NotchBehavior.defaultCloseDelay
    @AppStorage(NotchBehavior.hapticKey) private var haptic = true

    var body: some View {
        SettingsCard(Text(verbatim: "Notch Behavior")) {
            SettingsRow(Text(verbatim: "Opening")) {
                Picker(selection: $mode) {
                    Text(verbatim: "Expand on hover").tag(NotchOpenMode.hover.rawValue)
                    Text(verbatim: "Click to open").tag(NotchOpenMode.click.rawValue)
                } label: { Text(verbatim: "Opening") }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            if mode == NotchOpenMode.hover.rawValue {
                SettingsDivider()
                delay("Activation time", "Keep the pointer over the notch for this long to open it.",
                      $hoverDelay, NotchBehavior.hoverDelayRange)
            }
            SettingsDivider()
            delay("Closing time", "Wait this long after the pointer leaves the notch before closing it.",
                  $closeDelay, NotchBehavior.closeDelayRange)
            SettingsDivider()
            SettingsToggleRow(Text(verbatim: "Haptic feedback"), isOn: $haptic)
            SettingsDivider()
            NotchDisplayRows()
        }
    }

    private func delay(_ title: String, _ hint: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: title).font(.system(size: 13))
                Spacer()
                Text(verbatim: String(format: "%.2f s", value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 0.05) { Text(verbatim: title) }.labelsHidden()
            Text(verbatim: hint).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// What the closed island shows at rest, and when the charge turns red (vorssaint-utils' Activity tab,
/// the parts KatiKati has data for; indicators and Lock Screen are not ported).
private struct NotchActivityCard: View {
    @AppStorage(NotchRestContent.defaultsKey) private var rest = NotchRestContent.timeBattery.rawValue
    @AppStorage(NotchMusicGlow.defaultsKey) private var glow = NotchMusicGlow.default.rawValue
    @AppStorage("com.katikati.notch.trackToast") private var trackToast = true
    @AppStorage("com.katikati.notch.batteryBuddy") private var batteryBuddy = true
    @AppStorage(NotchBehavior.musicBatteryKey) private var musicBattery = true
    @AppStorage(NotchBehavior.lowBatteryTintKey) private var tintsLow = true
    // 59b: the same low level the Notifications page edits, not a second one.
    @ObservedObject private var alerts = PowerNotificationCenter.shared

    private var threshold: Int {
        alerts.rules.lowThreshold ?? NotchBehavior.defaultLowBatteryThreshold
    }

    var body: some View {
        SettingsCard(Text(verbatim: "Notch At Rest")) {
            // SD-3b: storage left the resting notch, so its two presets retired; the row stays 3-up and
            // keeps a second line so the card does not reflow into a five-across strip.
            HStack(spacing: 8) {
                choice(.timeBattery, "Time & battery", "clock")
                choice(.battery, "Battery", "battery.75percent")
                choice(.time, "Time", "clock.fill")
            }
            .padding(.vertical, 4)
            HStack(spacing: 8) {
                choice(.nothing, "None", "minus")
            }
            .padding(.bottom, 4)
            SettingsDivider()
            SettingsRow(Text(verbatim: "Music glow")) {
                Picker(selection: $glow) {
                    Text(verbatim: "Halo").tag(NotchMusicGlow.halo.rawValue)
                    Text(verbatim: "Pulse").tag(NotchMusicGlow.pulse.rawValue)
                    Text(verbatim: "Edge line").tag(NotchMusicGlow.edge.rawValue)
                } label: { Text(verbatim: "Music glow") }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            SettingsDivider()
            SettingsToggleRow(Text(verbatim: "New song pill"), isOn: $trackToast)
            SettingsDivider()
            SettingsToggleRow(Text(verbatim: "Low Bluetooth battery pill"), isOn: $batteryBuddy)
            SettingsDivider()
            SettingsToggleRow(Text(verbatim: "Battery during music"), isOn: $musicBattery)
            SettingsDivider()
            SettingsToggleRow(Text(verbatim: "Turn red when low"), isOn: $tintsLow)
            if tintsLow {
                SettingsDivider()
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: "Low level").font(.system(size: 13))
                        Spacer()
                        Text(verbatim: "\(threshold)%").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(get: { Double(threshold) },
                                          set: { level in alerts.updateRules { $0.lowThreshold = Int(level.rounded()) } }),
                           in: Double(NotchBehavior.lowBatteryRange.lowerBound)...Double(NotchBehavior.lowBatteryRange.upperBound),
                           step: 1) { Text(verbatim: "Low level") }.labelsHidden()
                    Text(verbatim: "Shows the charge in red at or below this level while on battery.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func choice(_ value: NotchRestContent, _ title: String, _ symbol: String) -> some View {
        let selected = NotchRestContent.resolved(raw: rest) == value
        return Button { rest = value.rawValue } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 18, weight: .medium))
                Text(verbatim: title).font(.system(size: 11, weight: .semibold))
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(selected ? 0.1 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Open-panel size, translucency and outline (vorssaint-utils' Layout tab, the parts that map onto
/// KatiKati's scaled pages; notch/camera fit and the capsule silhouette are not ported).
private struct NotchLayoutCard: View {
    @AppStorage(NotchSizePreset.defaultsKey) private var preset = NotchSizePreset.standard.rawValue
    @AppStorage(NotchSizePreset.customScaleKey) private var customScale = 1.0
    @AppStorage(NotchSizePreset.outlineKey) private var outline = false
    @AppStorage(NotchSizePreset.translucentKey) private var translucent = false

    var body: some View {
        SettingsCard(Text(verbatim: "Notch Layout")) {
            HStack(spacing: 8) {
                ForEach(NotchSizePreset.allCases, id: \.rawValue) { item in
                    Button { preset = item.rawValue } label: {
                        Text(verbatim: item.rawValue.capitalized)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(preset == item.rawValue ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(preset == item.rawValue ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
            if preset == NotchSizePreset.custom.rawValue {
                SettingsDivider()
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: "Size").font(.system(size: 13))
                        Spacer()
                        Text(verbatim: "\(Int((customScale * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $customScale, in: NotchSizePreset.customScaleRange, step: 0.05) { Text(verbatim: "Size") }
                        .labelsHidden()
                }
                .padding(.vertical, 4)
            }
            SettingsDivider()
            SettingsToggleRow(Text(verbatim: "Translucent background"), isOn: $translucent)
            SettingsDivider()
            SettingsToggleRow(Text(verbatim: "Show outline"), isOn: $outline)
        }
    }
}

/// 51c: reorder, hide, and choose the default opening page of the notch. Hiding the last shown page switches the notch off, after a warning.
private struct NotchPagesCard: View {
    @ObservedObject var store: AppSettingsStore
    @AppStorage(NotchPageLayout.defaultsKey) private var raw = ""
    @AppStorage(TeleprompterModel.enabledKey) private var teleprompter = false
    @AppStorage(CameraMirrorService.enabledKey) private var mirror = true
    @AppStorage(NotchPagingPolicy.pinnedDefaultPageKey) private var pinnedDefaultRaw: Int = -1
    @State private var pendingHide: NotchPage?

    private var layout: NotchPageLayout { NotchPageLayout(raw: raw) }
    /// Every page that exists right now, in the owner's order, hidden ones included.
    private var pages: [NotchPage] {
        layout.order.filter { NotchPage.visible(teleprompter: teleprompter, mirror: mirror, layout: NotchPageLayout()).contains($0) }
    }

    var body: some View {
        SettingsCard(Text(verbatim: "Notch Pages")) {
            HStack {
                Text(verbatim: "Default Opening Page")
                    .font(.subheadline)
                Spacer()
                Picker(selection: $pinnedDefaultRaw) {
                    Text(verbatim: "Auto (Music)").tag(-1)
                    ForEach(pages.filter { !layout.hidden.contains($0) }) { page in
                        Text(verbatim: page.title).tag(page.rawValue)
                    }
                } label: { EmptyView() }
                .labelsHidden()
                .frame(width: 190)
            }
            SettingsDivider()
            List {
                ForEach(pages) { page in
                    HStack {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                        Label { Text(verbatim: page.title) } icon: { Image(systemName: page.symbol) }
                        Spacer()
                        Button { toggle(page) } label: {
                            Image(systemName: layout.hidden.contains(page) ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text(verbatim: (layout.hidden.contains(page) ? "Show " : "Hide ") + page.title))
                    }
                    .opacity(layout.hidden.contains(page) ? 0.45 : 1)
                }
                .onMove { from, to in
                    var moved = pages
                    moved.move(fromOffsets: from, toOffset: to)
                    raw = NotchPageLayout(order: moved + layout.order, hidden: layout.hidden).raw
                }
            }
            .listStyle(.plain)
            .scrollDisabled(true)
            .frame(height: CGFloat(pages.count) * 32 + 8)
            HStack {
                Button {
                    raw = ""
                    teleprompter = false
                    mirror = true
                    pinnedDefaultRaw = -1
                    if !store.notchIslandEnabled { store.setNotchIslandEnabled(true) }
                } label: {
                    Text(verbatim: "Show All & Reset Order")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer()
            }
            if !store.notchIslandEnabled {
                Text(verbatim: "The notch is off. Show a page to bring it back.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(Text(verbatim: "Hide the last page?"), isPresented: Binding(get: { pendingHide != nil }, set: { if !$0 { pendingHide = nil } })) {
            Button(role: .destructive) { if let page = pendingHide { setHidden(page, true); store.setNotchIslandEnabled(false) } } label: {
                Text(verbatim: "Hide and turn the notch off")
            }
        } message: { Text(verbatim: "With every page hidden the notch has nothing to show, so it will be turned off.") }
    }

    private func toggle(_ page: NotchPage) {
        if layout.hidden.contains(page) {
            setHidden(page, false)
            if !store.notchIslandEnabled { store.setNotchIslandEnabled(true) }
        } else if pages.allSatisfy({ $0 == page || layout.hidden.contains($0) }) {
            pendingHide = page
        } else {
            setHidden(page, true)
        }
    }

    private func setHidden(_ page: NotchPage, _ hide: Bool) {
        var next = layout
        if hide { next.hidden.insert(page) } else { next.hidden.remove(page) }
        raw = next.raw
    }
}

/// SLICE DP-2: Droppy glass material, accent theme, DropClip toggle, and shelf widget configuration.
private struct DroppyCustomizationCard: View {
    @AppStorage(DroppyShelfConfigStore.glassKey) private var glassRaw = DroppyGlassMaterial.dynamicGlass.rawValue
    @AppStorage(DroppyShelfConfigStore.accentKey) private var accentRaw = DroppyAccentTheme.oceanBlue.rawValue
    @AppStorage(DroppyShelfConfigStore.orderKey) private var orderRaw = ""
    @AppStorage(DroppyShelfConfigStore.hiddenKey) private var hiddenRaw = DroppyShelfConfigStore.encodeHidden(DroppyShelfConfigStore.defaultHidden)
    @AppStorage(NotchSurfaceAppearance.StorageKey.transparency) private var transparency = NotchSurfaceAppearance.defaultTransparency
    @AppStorage(DropClipPolicy.enabledKey) private var dropClipEnabled = true

    private var glassMaterial: DroppyGlassMaterial { DroppyGlassMaterial(rawValue: glassRaw) ?? .dynamicGlass }
    private var hiddenSet: Set<DroppyShelfWidgetKind> { DroppyShelfConfigStore.decodeHidden(hiddenRaw) }

    var body: some View {
        SettingsCard(
            Text("Droppy & Shelf"),
            note: Text("Configure notch glass material, shelf accent, DropClip pill, and visible shelf widgets.")
        ) {
            SettingsRow(Text("Glass Material")) {
                Picker(selection: Binding(
                    get: { glassMaterial },
                    set: { material in
                        glassRaw = material.rawValue
                        transparency = material.baseTransparency
                    }
                )) {
                    ForEach(DroppyGlassMaterial.allCases) { material in
                        Text(verbatim: material.title).tag(material)
                    }
                } label: { EmptyView() }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            SettingsDivider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Accent Theme").font(.system(size: 13))
                HStack(spacing: 10) {
                    ForEach(DroppyAccentTheme.allCases) { theme in
                        Button { accentRaw = theme.rawValue } label: {
                            Circle()
                                .fill(NotchHexColor.rgba(theme.hex).color)
                                .frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2).padding(-3)
                                    .opacity(accentRaw == theme.rawValue ? 1 : 0))
                        }
                        .buttonStyle(.plain)
                        .help(Text(verbatim: theme.title))
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.vertical, 4)
            SettingsDivider()
            SettingsToggleRow(Text("DropClip Selection Pill"), isOn: $dropClipEnabled)
            SettingsDivider()
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Shelf Widgets").font(.system(size: 13))
                    Spacer()
                    Button {
                        orderRaw = DroppyShelfConfigStore.encodeOrder(DroppyShelfWidgetKind.allCases)
                        hiddenRaw = DroppyShelfConfigStore.encodeHidden(DroppyShelfConfigStore.defaultHidden)
                        glassRaw = DroppyGlassMaterial.dynamicGlass.rawValue
                        accentRaw = DroppyAccentTheme.oceanBlue.rawValue
                    } label: {
                        Text("Reset Shelf")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                ForEach(DroppyShelfWidgetKind.allCases) { kind in
                    SettingsToggleRow(
                        Text(verbatim: kind.title),
                        isOn: Binding(
                            get: { !hiddenSet.contains(kind) },
                            set: { visible in
                                var next = hiddenSet
                                if visible { next.remove(kind) } else { next.insert(kind) }
                                hiddenRaw = DroppyShelfConfigStore.encodeHidden(next)
                            }
                        )
                    )
                }
            }
        }
    }
}

/// Per-display Notch preset: Default (follows global Notch Style), a specific Notch skin
/// (`Liquid`, `Full`, `Compact`, `Dynamic Island`), `Wide bar`, or `Off`.
private struct NotchDisplayRows: View {
    @State private var screens = NSScreen.screens
    @State private var storedDesigns = NotchDesign.stored()
    @State private var storedSkins = NotchDisplaySkin.stored()

    var body: some View {
        ForEach(screens, id: \.displayID) { screen in
            let id = String(screen.displayID ?? 0)
            let uuid = DisplayIdentity.uuidString(for: screen)
            let notch = screen.safeAreaInsets.top > 0
            SettingsRow(Text(verbatim: screen.localizedName)) {
                Picker(selection: Binding(
                    get: { selectionTag(id: id, uuid: uuid, hasHardwareNotch: notch) },
                    set: { applySelection($0, id: id) }
                )) {
                    Text("Default").tag("default")
                    Divider()
                    Text("Liquid").tag("skin.liquid")
                    Text("Full").tag("skin.boring")
                    Text("Compact").tag("skin.classic")
                    Text("Dynamic Island").tag("skin.dynamicIsland")
                    Divider()
                    Text(verbatim: "Wide bar").tag("design.wideBar")
                    Text(verbatim: "Off").tag("design.off")
                } label: { Text(verbatim: screen.localizedName) }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in screens = NSScreen.screens }
    }

    private func selectionTag(id: String, uuid: String?, hasHardwareNotch: Bool) -> String {
        let design = NotchDesign.resolve(display: id, displayUUID: uuid, hasHardwareNotch: hasHardwareNotch, stored: storedDesigns)
        if design == .wideBar { return "design.wideBar" }
        if design == .off { return "design.off" }
        if let uuid, !uuid.isEmpty, let skin = storedSkins[uuid] { return "skin.\(skin.rawValue)" }
        if let skin = storedSkins[id] { return "skin.\(skin.rawValue)" }
        return "default"
    }

    private func applySelection(_ tag: String, id: String) {
        if tag == "design.wideBar" {
            NotchDesign.set(.wideBar, for: id)
            NotchDisplaySkin.set(nil, for: id)
        } else if tag == "design.off" {
            NotchDesign.set(.off, for: id)
            NotchDisplaySkin.set(nil, for: id)
        } else if tag.hasPrefix("skin."), let skin = LiveIslandSkin(rawValue: String(tag.dropFirst(5))) {
            NotchDesign.set(.notch, for: id)
            NotchDisplaySkin.set(skin, for: id)
        } else {
            NotchDesign.set(.notch, for: id)
            NotchDisplaySkin.set(nil, for: id)
        }
        storedDesigns = NotchDesign.stored()
        storedSkins = NotchDisplaySkin.stored()
    }
}

private struct IslandPlaygroundSheet: View {
    @ObservedObject var store: AppSettingsStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var bridge = IslandLiveBridge()
    @State private var simulatedTopology = "m5_oled"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Island Playground")
                    .font(.headline)
                Spacer()
                Button(String(localized: "Close")) {
                    bridge.clearPlayground()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            // Simulated screen backdrop + interactive Dynamic Island stage
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: simulatedTopology == "m5_oled"
                                ? [Color.black, Color(white: 0.08)]
                                : [Color(red: 0.1, green: 0.14, blue: 0.24), Color(red: 0.05, green: 0.06, blue: 0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                IslandSurfaceView(driver: bridge.driver, registry: bridge.registry) {
                    Text(verbatim: "KatiKati Bento Suite")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
            }
            .frame(width: 520, height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 8) {
                Picker(selection: $simulatedTopology) {
                    Text(verbatim: "M5 OLED Touch").tag("m5_oled")
                    Text(verbatim: "M1-M4 Notch").tag("classic_notch")
                    Text(verbatim: "External Display").tag("external")
                } label: {
                    Text(verbatim: "Topology")
                }
                .pickerStyle(.segmented)
                .onChange(of: simulatedTopology) { _, next in
                    applyTopology(next)
                }
            }

            HStack(spacing: 8) {
                Button { bridge.runPlayground(.singleTimer) } label: { Text(verbatim: "Timer") }
                Button { bridge.runPlayground(.splitMusicAndTimer) } label: { Text(verbatim: "Split (Music + Timer)") }
                Button { bridge.runPlayground(.downloadAlert) } label: { Text(verbatim: "Download Alert") }
                Button { bridge.runPlayground(.aiAgentAndCall) } label: { Text(verbatim: "AI Agent + Call") }
                Button { bridge.runPlayground(.etaDelivery) } label: { Text(verbatim: "ETA Template") }
            }
            .buttonStyle(.bordered)

            HStack(spacing: 8) {
                Button { bridge.driver.store.expand() } label: { Text(verbatim: "Expand") }
                Button { bridge.driver.store.collapse() } label: { Text(verbatim: "Collapse") }
                Button { bridge.clearPlayground() } label: { Text(verbatim: "Reset Idle") }
                Spacer()
                Text(verbatim: "Tip: drag down from pill to test 1:1 rubber-banding")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(18)
        .frame(width: 560)
        .onAppear {
            applyTopology(simulatedTopology)
            bridge.runPlayground(.splitMusicAndTimer)
        }
    }

    private func applyTopology(_ id: String) {
        let topology: IslandDisplayTopology
        switch id {
        case "m5_oled":
            topology = IslandDisplayTopology.resolve(
                screenWidth: 1728,
                screenHeight: 1117,
                safeAreaTop: 46,
                auxLeftWidth: 798,
                auxRightWidth: 798,
                menuBarHeight: 46,
                isBuiltinDisplay: true,
                isOLED: true,
                supportsMultiTouch: true
            )
        case "classic_notch":
            topology = IslandDisplayTopology.resolve(
                screenWidth: 1728,
                screenHeight: 1117,
                safeAreaTop: 38,
                auxLeftWidth: 760,
                auxRightWidth: 760,
                menuBarHeight: 38,
                isBuiltinDisplay: true,
                isOLED: false,
                supportsMultiTouch: false
            )
        default:
            topology = IslandDisplayTopology.resolve(
                screenWidth: 2560,
                screenHeight: 1440,
                safeAreaTop: 0,
                auxLeftWidth: nil,
                auxRightWidth: nil,
                menuBarHeight: 24,
                isBuiltinDisplay: false,
                isOLED: false,
                supportsMultiTouch: false
            )
        }
        let touch = topology.isTouchOptimized(setting: store.islandTouchMode)
        bridge.driver.stageWidth = 520
        bridge.driver.keylineSetting = topology.keylineSetting(userEnabled: store.islandKeylineEnabled)
        bridge.driver.updateDisplayTopology(topology, touchEnabled: touch, nonNotchBehavior: store.islandNonNotchBehavior)
    }
}

private struct LiquidExtrasSettingsRows: View {
    @AppStorage(LiquidExtrasKeys.sportsEnabled) private var sportsEnabled = false
    @AppStorage(LiquidExtrasKeys.videoInIslandEnabled) private var videoInIslandEnabled = true
    @AppStorage(LiquidExtrasKeys.lockScreenEnabled) private var lockScreenEnabled = false
    @AppStorage(LiquidExtrasKeys.notificationsEnabled) private var notificationsEnabled = true

    var body: some View {
        LiquidAgentHookToggleRow()
        SettingsDivider()
        SettingsToggleRow(Text("Sports Scores"), isOn: $sportsEnabled)
            .help(Text("Show live ESPN scoreboard balls for followed leagues."))
        SettingsDivider()
        SettingsToggleRow(Text("Video in Island"), isOn: $videoInIslandEnabled)
            .help(Text("Allow mirroring browser video inside the Liquid Notch."))
        SettingsDivider()
        SettingsToggleRow(
            Text("Lock Screen Card"),
            isOn: Binding(
                get: { lockScreenEnabled },
                set: { on in
                    lockScreenEnabled = on
                    if on { LockScreenMusicCardController.shared.start() } else { LockScreenMusicCardController.shared.stop() }
                }
            )
        )
            .help(Text("Show Now Playing on the lock screen with automatic wallpaper backup."))
        SettingsDivider()
        SettingsToggleRow(Text("Notch Notifications"), isOn: $notificationsEnabled)
            .help(Text("Show transient event alerts inside the Liquid Notch."))
    }
}

private struct NotchStylePreviewGallery: View {
    @Binding var selected: LiveIslandSkin
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            ForEach(LiveIslandSkin.allCases, id: \.self) { skin in
                let active = selected == skin
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { selected = skin }
                } label: {
                    VStack(spacing: 6) {
                        thumbnail(for: skin)
                            .frame(height: 36)
                        titleText(for: skin)
                            .font(.system(size: 11, weight: active ? .semibold : .medium))
                            .foregroundStyle(active ? .primary : .secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(active ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(active ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: active ? 1.5 : 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(isEnabled ? 1 : 0.45)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func titleText(for skin: LiveIslandSkin) -> some View {
        switch skin {
        case .liquid: Text("Liquid")
        case .boring: Text("Full")
        case .classic: Text("Compact")
        case .dynamicIsland: Text("Dynamic Island")
        }
    }

    @ViewBuilder
    private func thumbnail(for skin: LiveIslandSkin) -> some View {
        switch skin {
        case .liquid:
            HStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.black)
                        .shadow(color: Color(red: 0.56, green: 0.42, blue: 0.96).opacity(0.55), radius: 4)
                    HStack {
                        RoundedRectangle(cornerRadius: 2).fill(Color.pink).frame(width: 8, height: 8)
                        Spacer()
                        HStack(spacing: 1) {
                            Capsule().fill(Color.pink).frame(width: 1.5, height: 5)
                            Capsule().fill(Color.pink).frame(width: 1.5, height: 9)
                            Capsule().fill(Color.pink).frame(width: 1.5, height: 6)
                        }
                    }
                    .padding(.horizontal, 5)
                }
                .frame(width: 56, height: 18)
                Circle().fill(Color.black)
                    .overlay(Circle().fill(Color.orange).frame(width: 5, height: 5))
                    .frame(width: 14, height: 14)
            }
        case .boring:
            VStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black)
                    .overlay(
                        HStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.22))
                            RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.14))
                        }
                        .padding(4)
                    )
                    .frame(width: 68, height: 28)
            }
        case .classic:
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black)
                .overlay(
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.25)).frame(width: 12, height: 12)
                        RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.16)).frame(height: 6)
                    }
                    .padding(.horizontal, 6)
                )
                .frame(width: 60, height: 22)
        case .dynamicIsland:
            Capsule().fill(Color.black)
                .overlay(Capsule().strokeBorder(.white.opacity(0.32), lineWidth: 1))
                .overlay(
                    HStack {
                        Circle().fill(Color.pink.opacity(0.85)).frame(width: 7, height: 7)
                        Spacer()
                        Circle().fill(Color.green.opacity(0.85)).frame(width: 5, height: 5)
                    }
                    .padding(.horizontal, 6)
                )
                .frame(width: 58, height: 18)
        }
    }
}
