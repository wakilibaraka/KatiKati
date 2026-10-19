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
            Text("Live Island"),
            note: Text("The shape preview is a demo: the silhouette only, never live activity.")
        ) {
            if !stageVisible {
                NotchPreview(skin: store.notchSkin, isEnabled: store.notchIslandEnabled)
            }
            SettingsToggleRow(
                Text("Dock Island"),
                isOn: Binding(get: { store.dockIslandEnabled }, set: { store.setDockIslandEnabled($0) })
            )
            .help(Text("Shows the Live Island capsule on the dock."))
            SettingsDivider()
            SettingsToggleRow(
                Text("Notch Island"),
                isOn: Binding(get: { store.notchIslandEnabled }, set: { store.setNotchIslandEnabled($0) })
            )
            .help(Text("Shows or hides the Live Island at the top of the screen."))
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
            .help(Text("Choose where Live Island event alerts appear."))
            SettingsDivider()
            SettingsToggleRow(
                Text("System Banners"),
                isOn: Binding(get: { store.liveEventOSBanners }, set: { store.setLiveEventOSBanners($0) })
            )
            .help(Text("Also show Live Island alerts as macOS notifications."))
        }
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
    @AppStorage(NotchOpenAnimation.defaultsKey) private var selected = NotchOpenAnimation.boring.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "Open Animation").font(.system(size: 13))
            HStack(spacing: 8) {
                ForEach(NotchOpenAnimation.allCases) { style in
                    Button { selected = style.rawValue } label: {
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
