import SwiftUI

/// Phase 8b-7 — Settings rows for the Live Island: where it shows (dock capsule, notch) and where its
/// event alerts go. Now one card of shared rows, so the block looks the same on every page it sits
/// on. Titles are whole literals (localization gate stays one-to-one).
struct LiveIslandSettingsBlock: View {
    @ObservedObject var store: AppSettingsStore
    @Environment(\.settingsStageVisible) private var stageVisible

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
                Text("Show Dock Capsule"),
                isOn: Binding(get: { store.dockIslandEnabled }, set: { store.setDockIslandEnabled($0) })
            )
            .help(Text("Shows the widget capsule on the dock."))
            SettingsDivider()
            SettingsToggleRow(
                Text("Show on Notch"),
                isOn: Binding(get: { store.notchIslandEnabled }, set: { store.setNotchIslandEnabled($0) })
            )
            .help(Text("Shows or hides the Dynamic Notch at the top of the screen."))
            SettingsDivider()
            SettingsRow(Text("Notch Style")) {
                Picker("Notch Style", selection: Binding(get: { store.notchSkin }, set: { store.setNotchSkin($0) })) {
                    Text("Full").tag(LiveIslandSkin.boring)
                    Text("Compact").tag(LiveIslandSkin.classic)
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            .help(Text("Full uses a multi-panel layout; Compact uses a simpler player card."))
            SettingsDivider()
            NotchAnimationPicker()
            SettingsDivider()
            SettingsRow(Text("Event Alerts")) {
                Picker("Event Alerts", selection: Binding(get: { store.liveEventRoute }, set: { store.setLiveEventRoute($0) })) {
                    ForEach(LiveEventRoute.allCases, id: \.self) { Self.title(for: $0).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            .help(Text("Choose where Dynamic Notch event alerts appear."))
            SettingsDivider()
            SettingsToggleRow(
                Text("System Banners"),
                isOn: Binding(get: { store.liveEventOSBanners }, set: { store.setLiveEventOSBanners($0) })
            )
            .help(Text("Also show Dynamic Notch alerts as macOS notifications."))
        }
        NotchLayoutCard()
        NotchBehaviorCard()
        NotchPagesCard(store: store)
        NotchActivityCard()
    }

    private static func title(for route: LiveEventRoute) -> Text {
        switch route {
        case .automatic: return Text("Automatic")
        case .notch: return Text("Notch")
        case .dock: return Text("Dock")
        case .both: return Text("Both")
        case .off: return Text("Off")
        }
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
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.3)); open.toggle()
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
    @AppStorage(NotchDisplayChoice.defaultsKey) private var display = NotchDisplayChoice.automatic.rawValue

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
            SettingsRow(Text(verbatim: "Display")) {
                Picker(selection: $display) {
                    Text(verbatim: "Automatic").tag(NotchDisplayChoice.automatic.rawValue)
                    Text(verbatim: "Built-in display").tag(NotchDisplayChoice.builtIn.rawValue)
                    Text(verbatim: "Main display").tag(NotchDisplayChoice.main.rawValue)
                } label: { Text(verbatim: "Display") }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
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
    @AppStorage(NotchRestContent.defaultsKey) private var rest = NotchRestContent.dockChips.rawValue
    @AppStorage(NotchMusicGlow.defaultsKey) private var glow = NotchMusicGlow.default.rawValue
    @AppStorage("com.katikati.notch.trackToast") private var trackToast = true
    @AppStorage("com.katikati.notch.batteryBuddy") private var batteryBuddy = true
    @AppStorage(NotchBehavior.lowBatteryTintKey) private var tintsLow = true
    @AppStorage(NotchBehavior.lowBatteryThresholdKey) private var threshold = NotchBehavior.defaultLowBatteryThreshold

    var body: some View {
        SettingsCard(Text(verbatim: "Notch At Rest")) {
            HStack(spacing: 8) {
                choice(.dockChips, "Storage & battery", "internaldrive")
                choice(.battery, "Battery", "battery.75percent")
                choice(.nothing, "Nothing", "minus")
            }
            .padding(.vertical, 4)
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
            SettingsToggleRow(Text(verbatim: "Turn red when low"), isOn: $tintsLow)
            if tintsLow {
                SettingsDivider()
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: "Low level").font(.system(size: 13))
                        Spacer()
                        Text(verbatim: "\(threshold)%").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(get: { Double(threshold) }, set: { threshold = Int($0.rounded()) }),
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
        let selected = rest == value.rawValue
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

/// 51c: reorder and hide the notch pages. Hiding the last shown page switches the notch off, after a warning.
private struct NotchPagesCard: View {
    @ObservedObject var store: AppSettingsStore
    @AppStorage(NotchPageLayout.defaultsKey) private var raw = ""
    @AppStorage(TeleprompterModel.enabledKey) private var teleprompter = false
    @AppStorage(CameraMirrorService.enabledKey) private var mirror = false
    @AppStorage(NotificationMirrorService.enabledKey) private var notifications = false
    @State private var pendingHide: NotchPage?

    private var layout: NotchPageLayout { NotchPageLayout(raw: raw) }
    /// Every page that exists right now, in the owner's order, hidden ones included.
    private var pages: [NotchPage] {
        layout.order.filter { NotchPage.visible(teleprompter: teleprompter, mirror: mirror, notifications: notifications, layout: NotchPageLayout()).contains($0) }
    }

    var body: some View {
        SettingsCard(Text(verbatim: "Notch Pages")) {
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
