import SwiftUI

/// Phase 8b-7 — Settings rows for the Live Island: where it shows (dock capsule, notch) and where its
/// event alerts go. Plain label-leading / control-trailing rows so the same block sits in both the
/// grouped-form and the macOS 12 layouts. Titles are whole literals (localization gate stays one-to-one).
struct LiveIslandSettingsBlock: View {
    @ObservedObject var store: AppSettingsStore

    var body: some View {
        Text("Live Island").font(.headline)
        NotchPreview(skin: store.notchSkin, isEnabled: store.notchIslandEnabled)
        row("Dock Island", help: Text("Shows the Live Island capsule on the dock.")) {
            Toggle("Dock Island", isOn: Binding(get: { store.dockIslandEnabled }, set: { store.setDockIslandEnabled($0) }))
                .toggleStyle(.switch).labelsHidden().accessibilityLabel("Dock Island")
        }
        row("Notch Island", help: Text("Shows or hides the Live Island at the top of the screen.")) {
            Toggle("Notch Island", isOn: Binding(get: { store.notchIslandEnabled }, set: { store.setNotchIslandEnabled($0) }))
                .toggleStyle(.switch).labelsHidden().accessibilityLabel("Notch Island")
        }
        row("Notch Style", help: Text("Full uses a multi-panel layout; Compact uses a simpler player card.")) {
            Picker("Notch Style", selection: Binding(get: { store.notchSkin }, set: { store.setNotchSkin($0) })) {
                Text("Full").tag(LiveIslandSkin.boring)
                Text("Compact").tag(LiveIslandSkin.classic)
            }
            .labelsHidden().pickerStyle(.menu).fixedSize()
        }
        row("Event Alerts", help: Text("Choose where Live Island event alerts appear.")) {
            Picker("Event Alerts", selection: Binding(get: { store.liveEventRoute }, set: { store.setLiveEventRoute($0) })) {
                ForEach(LiveEventRoute.allCases, id: \.self) { Self.title(for: $0).tag($0) }
            }
            .labelsHidden().pickerStyle(.menu).fixedSize()
        }
        row("System Banners", help: Text("Also show Live Island alerts as macOS notifications.")) {
            Toggle("System Banners", isOn: Binding(get: { store.liveEventOSBanners }, set: { store.setLiveEventOSBanners($0) }))
                .toggleStyle(.switch).labelsHidden().accessibilityLabel("System Banners")
        }
    }

    private func row<C: View>(
        _ title: LocalizedStringKey,
        help: Text,
        @ViewBuilder control: () -> C
    ) -> some View {
        HStack {
            Text(title).help(help)
            Spacer(minLength: 12)
            control()
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
