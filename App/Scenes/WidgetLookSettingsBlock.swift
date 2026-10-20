import SwiftUI

/// Phase 12 — how the widget panes look (layout, colours, clock, glass, theme) and the style
/// presets that go with them. The dock's own list moved to the Dock Items tab, and the weather
/// rows to the Weather tab (2026-10-20 split).
/// Renders through the shared card/row system (`SettingsCard.swift`, `Docs/SETTINGS.md` rule 2) and
/// gives the page at most three sections (rule 5).
struct WidgetLookSettingsBlock: View {
    @ObservedObject var store: AppSettingsStore

    // Moved here from `SettingsLayoutPane` (2026-10-15): the style presets are appearance, and the
    // pane's extra card made the page four sections. Same keys, same controls.
    // These four came with the weather block (2026-10-15): they are about the widget tiles
    // themselves — the animation they use and whether the notes and stopwatch tiles exist — so they
    // sit with the rest of the appearance rows, not under the weather warning thresholds.
    @AppStorage(WidgetAnimationPreset.storageKey) private var widgetAnimation: WidgetAnimationPreset = .slide
    @AppStorage(WidgetExtraPrefs.showNotesKey) private var showNotes = true
    @AppStorage(WidgetExtraPrefs.showStopwatchKey) private var showStopwatch = true
    @AppStorage(WidgetPanelController.keepBothOpenKey) private var keepBoth = false

    @AppStorage("com.katikati.clock.preset") private var clockPresetRaw: String = ClockPreset.stackedCard.rawValue
    @AppStorage("com.katikati.media.preset") private var mediaPresetRaw: String = NowPlayingPreset.expandedCard.rawValue
    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            SettingsCard(Text("Widget Appearance")) {
                // Menus and switches, two rows per line (`Docs/SETTINGS.md` rule 5): this card was
                // ten rows deep, one narrow control each.
                SettingsRowPair(
                    left: { SettingsRow(Text("Widget Layout")) { CalendarLayoutPicker() } },
                    right: { SettingsRow(Text("Widget Colors")) { CalendarPalettePicker() } }
                )
                SettingsDivider()
                SettingsRowPair(
                    // Not the dock clock's preset (that is "Clock Style" further down): this one is
                    // the clock *tile*'s look. Two rows with one name was a defect, not a style choice.
                    left: { SettingsRow(Text("Clock Tile Style")) { CalendarClockStylePicker() } },
                    right: { SettingsRow(Text("Glass")) { GlassTilesToggle().accessibilityLabel(Text("Glass")) } }
                )
                SettingsDivider()
                SettingsRow(Text("Now Playing Click")) {
                    Picker("Now Playing Click", selection: $store.nowPlayingTapPreset) {
                        ForEach(NowPlayingTapPreset.allCases, id: \.self) { Text($0.displayTitle) }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
                SettingsDivider()
                SettingsRowPair(
                    left: {
                        SettingsRow(Text("Now Playing Theme")) {
                            Picker("Now Playing Theme", selection: $store.nowPlayingTheme) {
                                ForEach(NowPlayingTheme.allCases, id: \.self) { Text($0.displayTitle) }
                            }
                            .labelsHidden().pickerStyle(.menu).fixedSize()
                        }
                    },
                    right: {
                        SettingsPickerRow(Text("Widget Animation"), selection: $widgetAnimation) {
                            Text("Instant").tag(WidgetAnimationPreset.instant)
                            Text("Slide").tag(WidgetAnimationPreset.slide)
                            Text("Spring Pop").tag(WidgetAnimationPreset.springPop)
                        }
                    }
                )
                SettingsDivider()
                SettingsRowPair(
                    left: { SettingsToggleRow(Text("Show Notes Widget"), isOn: $showNotes) },
                    right: { SettingsToggleRow(Text("Show Stopwatch & Countdown"), isOn: $showStopwatch) }
                )
                SettingsDivider()
                SettingsToggleRow(Text("Keep Both Widgets Open"), isOn: $keepBoth)
                SettingsDivider()
                // The group's name with its ⓘ beside it, as a sub-header rather than a row
                // (2026-10-15): it carries no control, and a label spending a whole 41 pt row was
                // 41 pt of a page that has to fit the window. The explanation is unchanged.
                HStack(spacing: 6) {
                    Text("Widget Styles & Presets").font(.subheadline)
                    SettingsInfoButton(text: String(localized: "Switch between custom Phase 32 pods and legacy widget presets. You can also switch styles by right-clicking each widget on the dock."))
                }
                SettingsRowPair(
                    left: {
                        SettingsRow(Text("Clock Style")) {
                            Picker("Clock Style", selection: $clockPresetRaw) {
                                ForEach(ClockPreset.allCases, id: \.rawValue) { preset in
                                    Text(preset.title).tag(preset.rawValue)
                                }
                            }
                            .labelsHidden().pickerStyle(.menu).fixedSize()
                        }
                    },
                    right: {
                        SettingsRow(Text("Now Playing Style")) {
                            Picker("Now Playing Style", selection: $mediaPresetRaw) {
                                ForEach(NowPlayingPreset.allCases, id: \.rawValue) { preset in
                                    Text(preset.title).tag(preset.rawValue)
                                }
                            }
                            .labelsHidden().pickerStyle(.menu).fixedSize()
                        }
                    }
                )
            }
        }
    }
}
