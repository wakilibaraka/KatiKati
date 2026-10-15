import SwiftUI

/// Phase 12 — how the dock widgets look (layout, colours, clock, glass, weather, Now Playing).
/// Used to sit on General; same controls, now the top of the Widgets tab.
struct WidgetLookSettingsBlock: View {
    @ObservedObject var store: AppSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("Widget Layout") { CalendarLayoutPicker() }
            row("Widget Colors") { CalendarPalettePicker() }
            row("Clock Style") { CalendarClockStylePicker() }
            row("Glass") { GlassTilesToggle() }
            WeatherSettingsBlock()
            row("Now Playing Theme") {
                Picker("Now Playing Theme", selection: $store.nowPlayingTheme) {
                    ForEach(NowPlayingTheme.allCases, id: \.self) { Text($0.displayTitle) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
        }
    }

    private func row<Control: View>(_ title: LocalizedStringKey, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            control()
        }
    }
}
