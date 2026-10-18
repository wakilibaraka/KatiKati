import SwiftUI

// The ControlCenter mode of `SettingsLayoutPane`; state lives in the main file.
extension SettingsLayoutPane {
    @ViewBuilder
    var controlCenterSections: some View {
            SettingsCard(Text("Control Center")) {
                // Four segmented rows in a row: two per line (`Docs/SETTINGS.md` rule 5).
                SettingsSegmentedRow(Text("Side"), selection: Binding(
                    get: { EdgeSide(rawValue: controlCenterSideRaw) ?? .right },
                    set: { controlCenterSideRaw = $0.rawValue }
                )) {
                    Text("Left").tag(EdgeSide.left)
                    Text("Right").tag(EdgeSide.right)
                }
            
                SettingsDivider()
                SettingsSegmentedRow(Text("Size"), selection: Binding(
                    get: { store.controlCenterSize },
                    set: { store.setControlCenterSize($0) }
                )) {
                    Text("Small").tag(ControlCenterSize.small)
                    Text("Medium").tag(ControlCenterSize.medium)
                    Text("Large").tag(ControlCenterSize.large)
                }
            
                SettingsDivider()
                SettingsSegmentedRow(Text("Anchor"), selection: Binding(
                    get: { store.controlCenterAnchor },
                    set: { store.setControlCenterAnchor($0) }
                )) {
                    Text("Top").tag(ControlCenterAnchor.top)
                    Text("Center").tag(ControlCenterAnchor.center)
                    Text("Bottom").tag(ControlCenterAnchor.bottom)
                }
            
                SettingsDivider()
                SettingsSegmentedRow(Text("Animation"), selection: Binding(
                    get: { store.controlCenterAnimation },
                    set: { store.setControlCenterAnimation($0) }
                )) {
                    Text("Instant").tag(ControlCenterAnimation.instant)
                    Text("Fade").tag(ControlCenterAnimation.fade)
                    Text("Slide").tag(ControlCenterAnimation.slide)
                }
            
                Text("Widgets").font(.subheadline).padding(.top, 6)
                SettingsGrid(TileKind.controlCenterDefault, id: \.self) { kind in
                    SettingsCheckboxRow(controlCenterWidgetTitle(kind), isOn: Binding(
                        get: { store.controlCenterWidgets.contains(kind) },
                        set: { store.setControlCenterWidget(kind, enabled: $0) }
                    ))
                }
                Text("Quick Settings").font(.subheadline).padding(.top, 6)
                SettingsGrid(QuickToggleID.defaultOrder, id: \.self) { id in
                    SettingsCheckboxRow(id.title, isOn: Binding(
                        get: { store.controlCenterToggles.contains(id) },
                        set: { store.setControlCenterToggle(id, enabled: $0) }
                    ))
                }
            }
    }

    @ViewBuilder
    var notificationSections: some View {
            SettingsCard(Text("Notifications")) {
                // The paragraph this card used to hold is the row's own explanation now (rule 4),
                // and the hand-rolled `Toggle` beside it was the last row on the page not built
                // from the shared set (rule 3) — it read as a bare control with no note beside it.
                SettingsToggleRow(
                    Text("Move Notification Banners"),
                    isOn: Binding(get: { notifMove.isEnabled }, set: { notifMove.setEnabled($0) }),
                    info: String(localized: "KatiKati moves each notification banner to the position you pick with the Accessibility API. Notification Center's private interface changes between macOS updates: when the layout looks unfamiliar, KatiKati leaves notifications alone, and only the first banner of a burst moves. Turning this off restores the macOS default immediately.")
                )
                if notifMove.isEnabled {
                    SettingsDivider()
                    SettingsPickerRow(Text("Position"), selection: Binding(
                        get: { notifMove.slot },
                        set: { notifMove.setSlot($0) }
                    )) {
                        ForEach(NotificationSlot.allCases, id: \.self) { slot in
                            notificationSlotTitle(slot).tag(slot)
                        }
                    }
                }
            }
    }

    func controlCenterWidgetTitle(_ kind: TileKind) -> Text {
        switch kind {
        case .network: return Text("Network")
        case .battery: return Text("Battery")
        case .batteries: return Text("Batteries")
        default: return Text(verbatim: "\(kind)")
        }
    }

    func notificationSlotTitle(_ slot: NotificationSlot) -> Text {
        switch slot {
        case .topLeft: return Text("Top Left")
        case .topCenter: return Text("Top Center")
        case .topRight: return Text("Top Right")
        case .middleLeft: return Text("Middle Left")
        case .middleRight: return Text("Middle Right")
        case .bottomLeft: return Text("Bottom Left")
        case .bottomCenter: return Text("Bottom Center")
        case .bottomRight: return Text("Bottom Right")
        }
    }
}
