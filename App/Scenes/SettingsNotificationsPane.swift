import SwiftUI

/// The Notifications page: what fires (low battery, charge milestones, plug changes, peripherals), how
/// long the history is kept, that history, and where macOS puts its own banners. The rules are
/// BeteriApp's settings — its low-battery picker and its 80 %/100 % charge points — with one change of
/// behaviour: they fire on a crossing, not on a state, so a battery sitting at 20 % notifies once.
struct SettingsNotificationsPane: View {
    @ObservedObject var store: AppSettingsStore
    @ObservedObject private var center = PowerNotificationCenter.shared
    @ObservedObject private var mirror = NotificationMirrorService.shared
    @AppStorage(NotificationHistoryStore.StorageKey.quietMode) private var quietMode = false
    @AppStorage(NotificationHistoryStore.StorageKey.redactSensitive) private var redactSensitive = true
    @AppStorage(NotificationHistoryStore.StorageKey.sensitiveBundles) private var sensitiveBundles = ""

    var body: some View {
        SettingsCard(
            Text("Battery"),
            note: Text("Alerts fire when a level is crossed, not while it sits there.")
        ) {
            SettingsPickerRow(Text("Low Battery Alert"), selection: Binding(
                get: { center.rules.lowThreshold ?? 0 },
                set: { level in center.updateRules { $0.lowThreshold = level == 0 ? nil : level } }
            )) {
                Text("Off").tag(0)
                ForEach(PowerNotificationRules.lowThresholdChoices, id: \.self) { level in
                    Text(verbatim: "\(level)%").tag(level)
                }
            }

            SettingsDivider()
            // 59f: BeteriApp's fixed steps, all four or none — each still fires once per dip.
            SettingsToggleRow(Text("Alert at 25% and below"), isOn: Binding(
                get: { !center.rules.lowSteps.isEmpty },
                set: { on in center.updateRules { $0.lowSteps = on ? Set(PowerNotificationRules.lowStepChoices) : [] } }
            ))

            SettingsDivider()
            SettingsRow(Text("Charge Milestones")) {
                HStack(spacing: 14) {
                    milestone(80)
                    milestone(100)
                }
            }

            SettingsDivider()
            SettingsToggleRow(Text("Charging & Unplugged"), isOn: Binding(
                get: { center.rules.chargingChanges },
                set: { on in center.updateRules { $0.chargingChanges = on } }
            ))
        }

        SettingsCard(
            Text("Peripherals"),
            note: Text("Arriving, leaving, and a peripheral that falls to 20%.")
        ) {
            SettingsToggleRow(Text("Peripheral Alerts"), isOn: Binding(
                get: { center.rules.peripheralAlerts },
                set: { on in center.updateRules { $0.peripheralAlerts = on } }
            ))
        }

        SettingsCard(Text("Appearance"), note: Text("A system sound plays with every alert when it is on.")) {
            SettingsSegmentedRow(Text("Alert Style"), selection: Binding(
                get: { center.rules.style },
                set: { style in center.updateRules { $0.style = style } }
            )) {
                ForEach(PowerNotificationStyle.allCases, id: \.self) { style in
                    Text(verbatim: style.name).tag(style)
                }
            }

            SettingsDivider()
            SettingsToggleRow(Text("Play a Sound"), isOn: Binding(
                get: { center.rules.soundEnabled },
                set: { on in center.updateRules { $0.soundEnabled = on } }
            ))
        }

        SettingsCard(Text("Notification History")) {
            SettingsSegmentedRow(Text("Retention"), selection: Binding(
                get: { center.rules.retentionHours },
                set: { hours in center.updateRules { $0.retentionHours = hours } }
            )) {
                Text("24 Hours").tag(24)
                Text("7 Days").tag(PowerNotificationRules.retentionChoices[1])
            }

            SettingsDivider()
            if center.history.isEmpty {
                SettingsNote(Text("No Notifications Yet"))
                    .padding(.vertical, SettingsMetrics.rowVerticalPadding)
            } else {
                ForEach(center.history.prefix(30)) { notification in
                    historyRow(notification)
                }
            }

            SettingsDivider()
            SettingsButtonRow(Text("Clear History")) { center.clearHistory() }
                .disabled(center.history.isEmpty)
        }

        SettingsCard(Text("System Notifications")) {
            SettingsSegmentedRow(Text("History Capacity"), selection: Binding(
                get: { mirror.historyStore.maxCapacity },
                set: { mirror.setHistoryCapacity($0) }
            )) {
                ForEach(NotificationHistoryStore.capacityChoices, id: \.self) { count in
                    Text(verbatim: "\(count)").tag(count)
                }
            }

            SettingsDivider()
            SettingsToggleRow(
                Text("Quiet Mode"),
                isOn: $quietMode,
                note: Text("Mutes notification sounds and live alert banners.")
            )

            SettingsDivider()
            SettingsToggleRow(
                Text("Redact Sensitive Apps"),
                isOn: $redactSensitive,
                note: Text("Hides notification titles and bodies from password managers and messaging apps.")
            )
            if redactSensitive {
                SettingsDivider()
                SettingsRow(Text("Extra Redacted Bundles")) {
                    TextField(text: $sensitiveBundles, prompt: Text(verbatim: "com.example.app, org.app")) {
                        EmptyView()
                    }
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                }
            }

            SettingsDivider()
            SettingsRow(Text("Inbox Actions")) {
                HStack(spacing: 8) {
                    Button(String(localized: "Mark All Read")) {
                        mirror.markAllRead()
                    }
                    .buttonStyle(SettingsGelButtonStyle())
                    .disabled(mirror.historyStore.unreadCount == 0)

                    Button(String(localized: "Clear Inbox")) {
                        mirror.clearHistoryStore()
                    }
                    .buttonStyle(SettingsGelButtonStyle())
                    .disabled(mirror.historyStore.entries.isEmpty)
                }
            }
        }

        // Where macOS puts its own banners — the section the Notch page used to carry.
        SettingsCard(Text("Event Alerts")) {
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
        SettingsLayoutPane(store: store, mode: .notifications)
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

    private func milestone(_ level: Int) -> some View {
        Toggle(isOn: Binding(
            get: { center.rules.chargeMilestones.contains(level) },
            set: { on in
                center.updateRules { rules in
                    if on { rules.chargeMilestones.insert(level) } else { rules.chargeMilestones.remove(level) }
                }
            }
        )) {
            Text(verbatim: "\(level)%")
        }
        .toggleStyle(.checkbox)
    }

    private func historyRow(_ notification: PowerNotification) -> some View {
        HStack(spacing: 8) {
            Image(systemName: notification.kind.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(verbatim: notification.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            if let detail = notification.detail {
                Text(verbatim: detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(verbatim: notification.date.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
    }
}
