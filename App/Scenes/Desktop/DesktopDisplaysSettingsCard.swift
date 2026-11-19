import SwiftUI

/// Settings › Desktop › Displays: per-screen widget list, Identify, Pin Layout, default display,
/// disconnect policy and per-widget EDID binding.
struct DesktopDisplaysSettingsCard: View {
    @ObservedObject var boxStore: DesktopBoxStore
    let coordinator: DesktopCanvasCoordinator

    @AppStorage(DesktopTopologyConfig.defaultDisplayUUIDKey) private var defaultDisplayUUID = ""
    @AppStorage(DesktopTopologyConfig.disconnectActionKey)
    private var disconnectActionRaw = DesktopDisconnectAction.relocate.rawValue
    @AppStorage(DesktopTopologyConfig.disconnectGraceSecondsKey)
    private var graceSeconds = DesktopTopologyConfig.defaultDisconnectGraceSeconds

    @State private var displays: [DesktopConnectedDisplay] = []
    @State private var pinNotice = false
    @State private var moveAllRevision = 0

    var body: some View {
        SettingsCard(Text("Displays")) {
            SettingsRow(
                Text("Default Display"),
                note: Text("New widgets that follow the main display open here.")
            ) {
                Picker(selection: $defaultDisplayUUID) {
                    Text("Automatic").tag("")
                    ForEach(displays) { display in
                        Text(verbatim: display.title).tag(display.uuid)
                    }
                } label: {
                    Text("Default Display")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .disabled(displays.isEmpty)
            }
            .onChange(of: defaultDisplayUUID) { _, newValue in
                coordinator.setDefaultDisplay(newValue.isEmpty ? nil : newValue)
            }

            SettingsDivider()
            SettingsRow(
                Text("Identify Screens"),
                note: Text("Flashes a large number on every display.")
            ) {
                Button("Identify Screens") { coordinator.identifyScreens() }
                    .buttonStyle(SettingsGelButtonStyle())
                    .disabled(displays.isEmpty)
            }

            SettingsDivider()
            SettingsRow(
                Text("Pin Layout"),
                note: pinNotice
                    ? Text("Layout pinned for this arrangement.")
                    : Text("Saves the current widget layout for this display arrangement.")
            ) {
                Button("Pin Layout") {
                    coordinator.pinCurrentLayout()
                    pinNotice = true
                }
                .buttonStyle(SettingsGelButtonStyle())
                .disabled(displays.isEmpty)
            }

            SettingsDivider()
            SettingsPickerRow(Text("Disconnect Action"), selection: $disconnectActionRaw) {
                Text("Relocate Widgets").tag(DesktopDisconnectAction.relocate.rawValue)
                Text("Collapse to Capsules").tag(DesktopDisconnectAction.capsule.rawValue)
            }

            SettingsDivider()
            SettingsSliderRow(
                Text("Grace Period"),
                value: graceSeconds,
                range: DesktopTopologyConfig.disconnectGraceRange,
                step: 1,
                valueText: graceSeconds < 1
                    ? String(localized: "Immediately")
                    : "\(Int(graceSeconds.rounded())) s"
            ) { graceSeconds = $0 }
        }
        .onAppear(perform: refreshDisplays)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            refreshDisplays()
        }
        .onReceive(boxStore.$items) { _ in
            moveAllRevision += 1
        }

        ForEach(Array(displays.enumerated()), id: \.element.id) { index, display in
            displayCard(index: index + 1, display: display)
        }
    }

    private func displayCard(index: Int, display: DesktopConnectedDisplay) -> some View {
        let widgets = widgets(on: display.uuid)
        return SettingsCard(Text(verbatim: "\(index). \(display.title)")) {
            SettingsRow(
                Text("Default Display"),
                note: display.isPrimary ? Text("Main Display") : nil
            ) {
                if defaultDisplayUUID == display.uuid {
                    Text("Default")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Set as Default") {
                        defaultDisplayUUID = display.uuid
                        coordinator.setDefaultDisplay(display.uuid)
                    }
                    .buttonStyle(SettingsGelButtonStyle())
                }
            }

            SettingsDivider()
            SettingsRow(
                Text("Widgets on This Display"),
                note: widgets.isEmpty
                    ? Text("No widgets on this display.")
                    : Text(verbatim: "\(widgets.count) \(String(localized: "widgets"))")

            ) {
                HStack(spacing: SettingsMetrics.controlSpacing) {
                    Button("Move All Widgets Here") {
                        coordinator.moveAllWidgets(toDisplay: display.uuid)
                        moveAllRevision += 1
                    }
                    .buttonStyle(SettingsGelButtonStyle())
                    .disabled(boxStore.items.isEmpty)

                    if coordinator.canUndoMoveAll {
                        Button("Undo Move All") {
                            coordinator.undoMoveAllWidgets()
                            moveAllRevision += 1
                        }
                        .buttonStyle(SettingsGelButtonStyle())
                    }
                }
            }

            ForEach(widgets) { item in
                SettingsDivider()
                SettingsRow(Text(verbatim: item.title)) {
                    Picker(selection: Binding(
                        get: { item.followMainDisplay ? "main" : "display" },
                        set: { coordinator.setDisplayBinding(for: item.id, followMain: $0 == "main") }
                    )) {
                        Text("Follow Main").tag("main")
                        Text("This Display").tag("display")
                    } label: {
                        Text(verbatim: item.title)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
        }
        .id("\(display.uuid)-\(moveAllRevision)")
    }

    private func widgets(on displayUUID: String) -> [DesktopWidgetItem] {
        boxStore.items
            .filter { !$0.isHidden && coordinator.resolvedDisplayUUID(forWidget: $0.id) == displayUUID }
            .sorted { $0.zOrder < $1.zOrder }
    }

    private func refreshDisplays() {
        displays = coordinator.connectedDisplays()
        if !defaultDisplayUUID.isEmpty,
           !displays.contains(where: { $0.uuid == defaultDisplayUUID }) {
            defaultDisplayUUID = ""
        }
    }
}

