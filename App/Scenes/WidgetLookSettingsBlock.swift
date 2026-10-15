import SwiftUI

/// Phase 12 — how the dock widgets look (layout, colours, clock, glass, weather, Now Playing).
/// Used to sit on General; same controls, now the top of the Widgets tab.
/// Renders through the shared card/row system (`SettingsCard.swift`, `Docs/SETTINGS.md` rule 2).
struct WidgetLookSettingsBlock: View {
    @ObservedObject var store: AppSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            SettingsCard {
                SettingsRow(Text("Widget Layout")) { CalendarLayoutPicker() }
                SettingsDivider()
                SettingsRow(Text("Widget Colors")) { CalendarPalettePicker() }
                SettingsDivider()
                SettingsRow(Text("Clock Style")) { CalendarClockStylePicker() }
                SettingsDivider()
                SettingsRow(Text("Glass")) { GlassTilesToggle() }
                SettingsDivider()
                SettingsRow(Text("Now Playing Theme")) {
                    Picker("Now Playing Theme", selection: $store.nowPlayingTheme) {
                        ForEach(NowPlayingTheme.allCases, id: \.self) { Text($0.displayTitle) }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
            }
            WeatherSettingsBlock()
        }
    }
}
