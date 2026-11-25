import AppKit
import SwiftUI

// The ControlCenter mode of `SettingsLayoutPane`; state lives in the main file.
extension SettingsLayoutPane {
    @ViewBuilder
    var controlCenterSections: some View {
            SettingsCard(Text("Control Center")) {
                // Four segmented rows in a row: two per line (`Docs/SETTINGS.md` rule 5).
                SettingsSegmentedRow(Text("Style"), selection: Binding(
                    get: { store.controlCenterStyle },
                    set: { store.setControlCenterStyle($0) }
                )) {
                    Text("Classic").tag(ControlCenterStyle.classic)
                    Text("iPadOS").tag(ControlCenterStyle.ipad)
                }

                SettingsDivider()
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
                ControlCenterAppearanceSettings()

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
            SettingsCard(Text("Banners")) {
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
                    // PHN-3: the text picker became the 3×3 screen it was describing.
                    NotificationZonePicker(selection: Binding(
                        get: { notifMove.slot },
                        set: { notifMove.setGlobalSlot($0) }
                    ))
                    SettingsDivider()
                    displayRoutingRow
                }
                SettingsDivider()
                bannerStatusNote
            }
    }

    /// PHN-3 — the per-display rule: follow the global zone, take one of the eight, or send this
    /// display's banners to the notch inbox.
    @ViewBuilder
    private var displayRoutingRow: some View {
        if let uuid = notificationDisplayUUID {
            SettingsPickerRow(Text("This Display"), selection: displayRuleBinding(uuid)) {
                Text("Follow Global").tag("global")
                ForEach(NotificationSlot.allCases, id: \.self) { slot in
                    Text(verbatim: NotificationZonePicker.title(for: slot)).tag(slot.rawValue)
                }
                Text("Send to Notch").tag("notch")
            }
        } else {
            SettingsNote(Text("This display has no stable identity, so it follows the global position."))
                .padding(.vertical, SettingsMetrics.rowVerticalPadding)
        }
    }

    private var notificationDisplayUUID: String? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        return DisplayIdentity.uuidString(for: screen)
    }

    private func displayRuleBinding(_ uuid: String) -> Binding<String> {
        Binding(
            get: {
                let target = notifMove.target(forDisplay: uuid)
                if target.routesToNotch { return "notch" }
                if notifMove.rule.perDisplay[uuid] != nil, let slot = target.slot { return slot.rawValue }
                return "global"
            },
            set: { raw in
                switch raw {
                case "global": notifMove.setSlot(nil, forDisplay: uuid)
                case "notch": notifMove.setNotchRouting(true, forDisplay: uuid)
                default: if let slot = NotificationSlot(rawValue: raw) { notifMove.setSlot(slot, forDisplay: uuid) }
                }
            }
        )
    }

    /// Says which failure is in the way instead of letting the switch flip itself back silently.
    @ViewBuilder
    private var bannerStatusNote: some View {
        if !notifMirror.canReadBanners {
            SettingsNote(Text("Accessibility is off, so banners stay where macOS puts them. Grant it in Privacy & Security, then turn the switch back on."))
                .padding(.vertical, SettingsMetrics.rowVerticalPadding)
        } else {
            SettingsNote(Text("Notification Center's layout changes between macOS updates. When it looks unfamiliar, KatiKati leaves banners where they are, and the notch inbox still lists them."))
                .padding(.vertical, SettingsMetrics.rowVerticalPadding)
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

}

/// CC-3/CC-4 — presets, finish and the dedupe switches. `@AppStorage` keeps the choice in the
/// same defaults the panel reads at open, so a change applies on the next open and survives relaunch.
private struct ControlCenterAppearanceSettings: View {
    @AppStorage(ControlCenterPreset.storageKey) private var presetRaw = ControlCenterPreset.default.rawValue
    @AppStorage(ControlCenterGlassStyle.storageKey) private var glassRaw = ControlCenterGlassStyle.default.rawValue
    @AppStorage(ControlCenterDedupeOptions.singleBatteryKey) private var singleBattery = true
    @AppStorage(ControlCenterDedupeOptions.singleNowPlayingKey) private var singleNowPlaying = true
    @AppStorage(ControlCenterDedupeOptions.showNowPlayingAnywayKey) private var showAnyway = false
    @AppStorage(ControlCenterSurfaceMode.storageKey) private var surfaceRaw = ControlCenterSurfaceMode.default.rawValue

    private var preset: ControlCenterPreset { ControlCenterPreset.parse(presetRaw) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Layout").font(.subheadline)
            HStack(spacing: 6) {
                ForEach([ControlCenterPreset.classic, .modular, .bento], id: \.self) { option in
                    Button { presetRaw = option.rawValue } label: {
                        presetLabel(option)
                            .font(.system(size: 11, weight: preset == option ? .semibold : .regular))
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(preset == option ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.045)))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(preset == option ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.09), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            if preset == .custom {
                SettingsNote(Text("Based on your last preset. Choosing one above resets the tiles."))
            }

            SettingsSegmentedRow(Text("Finish"), selection: Binding(
                get: { ControlCenterGlassStyle.parse(glassRaw) },
                set: { glassRaw = $0.rawValue }
            )) {
                Text("Clear").tag(ControlCenterGlassStyle.clear)
                Text("Semi").tag(ControlCenterGlassStyle.semi)
                Text("Tinted").tag(ControlCenterGlassStyle.tinted)
            }

            // The Hub is the other tenant of that icon, so choosing this home is also the moment
            // it becomes unavailable. The note rides on the row itself: this pane is a fixed
            // height, and a note stacked above pushed the way back out of view.
            SettingsSegmentedRow(Text("Home"), selection: Binding(
                get: { ControlCenterSurfaceMode.parse(surfaceRaw) },
                set: { next in
                    guard next != ControlCenterSurfaceMode.parse(surfaceRaw) else { return }
                    surfaceRaw = next.rawValue
                    // One surface at a time: the app layer closes whatever is open (Hub or Control
                    // Centre) so the next click shows the home just chosen and two panels never
                    // stack. A notification keeps this file compilable by the test target.
                    NotificationCenter.default.post(name: .controlCenterSurfaceDidChange, object: nil)
                    // The deck changes job only when this switch is what moved Control Centre to the
                    // menu bar, and the owner hears about it exactly once. Both buttons dismiss; the
                    // second is the way back, so the change is never a trap.
                    let told = UserDefaults.standard.bool(forKey: ControlCenterEdgeRole.promptSeenKey)
                    guard ControlCenterEdgeRole.implied(by: next, hasBeenTold: told).needsPrompt else { return }
                    UserDefaults.standard.set(true, forKey: ControlCenterEdgeRole.promptSeenKey)
                    let alert = NSAlert()
                    alert.messageText = String(localized: "Control Centre is now in the Menu Bar")
                    alert.informativeText = String(localized: "The edge Control Panel now shows Background Apps. Open the Control Centre from the menu bar icon.")
                    alert.addButton(withTitle: String(localized: "Keep in Menu Bar"))
                    let revert = alert.addButton(withTitle: String(localized: "Use Edge Instead"))
                    revert.keyEquivalent = "\u{1b}"
                    NSApp.activate(ignoringOtherApps: true)
                    if alert.runModal() == .alertSecondButtonReturn {
                        surfaceRaw = ControlCenterSurfaceMode.edge.rawValue
                        NotificationCenter.default.post(name: .controlCenterSurfaceDidChange, object: nil)
                    }
                }
            ), note: ControlCenterSurfaceMode.parse(surfaceRaw) == .menuBar
                ? Text("Creative Hub is paused while Control Centre is in the Menu Bar.")
                : nil) {
                Text("Edge").tag(ControlCenterSurfaceMode.edge)
                Text("Menu Bar").tag(ControlCenterSurfaceMode.menuBar)
            }

            SettingsToggleRow(Text("Single Battery"), isOn: $singleBattery,
                              info: String(localized: "Keeps the battery reading in the header pill and hides the duplicate This Mac row."))
            SettingsToggleRow(Text("Single Music"), isOn: $singleNowPlaying,
                              info: String(localized: "Hides the panel's now-playing card while the notch or dock music surface is on."))
            if singleNowPlaying {
                SettingsToggleRow(Text("Show Anyway"), isOn: $showAnyway,
                                  info: String(localized: "Keeps the now-playing card even when another music surface is on."))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .controlCenterSurfaceDidChange)) { _ in
            // The Background Apps deck can undo the home from inside its own footer; Settings is
            // often still open when it does, so the Home row must follow the real preference.
            surfaceRaw = UserDefaults.standard.string(forKey: ControlCenterSurfaceMode.storageKey)
                ?? ControlCenterSurfaceMode.default.rawValue
        }
    }

    @ViewBuilder
    private func presetLabel(_ preset: ControlCenterPreset) -> some View {
        switch preset {
        case .classic: Text("Classic")
        case .modular: Text("Modular")
        case .bento: Text("Bento")
        case .custom: Text("Custom")
        }
    }
}

/// PHN-3 — PingPlace's visual picker: the screen as a 3×3 grid, one click per zone, the dead centre
/// left as a picture of the screen rather than a target.
struct NotificationZonePicker: View {
    @Binding var selection: NotificationSlot

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(NotificationZoneGrid.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, slot in
                        if let slot { zoneCell(slot) } else { deadCentre }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func zoneCell(_ slot: NotificationSlot) -> some View {
        let selected = slot == selection
        return Button { selection = slot } label: {
            Text(verbatim: NotificationZonePicker.title(for: slot))
                .font(.system(size: 10, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.045))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.09),
                                      lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: NotificationZonePicker.title(for: slot)))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .help(Text(verbatim: NotificationZonePicker.title(for: slot)))
    }

    private var deadCentre: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.09), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(maxWidth: .infinity, minHeight: 30)
            // No glyph inside: the tiny “–” read as a broken or disabled cell. A dashed empty slot is
            // enough to say “the screen's centre is never a zone”.
            .accessibilityHidden(true)
    }

    /// The eight zone names — the same keys the picker used before the grid replaced it.
    static func title(for slot: NotificationSlot) -> String {
        switch slot {
        case .topLeft: return String(localized: "Top Left")
        case .topCenter: return String(localized: "Top Center")
        case .topRight: return String(localized: "Top Right")
        case .middleLeft: return String(localized: "Middle Left")
        case .middleRight: return String(localized: "Middle Right")
        case .bottomLeft: return String(localized: "Bottom Left")
        case .bottomCenter: return String(localized: "Bottom Center")
        case .bottomRight: return String(localized: "Bottom Right")
        }
    }
}
