import SwiftUI

/// Phase 8b-7 — Settings rows for the Live Island: where it shows (dock capsule, notch) and where its
/// event alerts go. Now one card of shared rows, so the block looks the same on every page it sits
/// on. Titles are whole literals (localization gate stays one-to-one).
struct LiveIslandSettingsBlock: View {
    @ObservedObject var store: AppSettingsStore

    var body: some View {
        SettingsCard(Text("Live Island")) {
            NotchPreview(skin: store.notchSkin, isEnabled: store.notchIslandEnabled)
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
