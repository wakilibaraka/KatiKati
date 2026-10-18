import SwiftUI

/// The Settings window's layout: sidebar on the left, the selected page scrolling on the right.
/// Nothing here is a fixed size; the window is freely resizable and `SettingsLayoutClass` decides
/// what the current size can show (Docs/SETTINGS_REDESIGN_PLAN.md §1).
struct SettingsShell: View {
    @ObservedObject var store: AppSettingsStore
    @ObservedObject var coordinator: SettingsCoordinator
    @ObservedObject var tabState: SettingsTabState
    let onShowWelcomeGuide: () -> Void

    @AppStorage("com.katikati.settings.sidebarCompact") private var forcedCompact = false

    var body: some View {
        GeometryReader { proxy in
            // Stage preview lands in Phase 3; until then the preference is fixed to off.
            let layout = SettingsLayoutClass.resolve(
                windowWidth: proxy.size.width,
                windowHeight: proxy.size.height,
                sidebarForcedIcons: forcedCompact,
                stagePreference: .off
            )
            HStack(spacing: 0) {
                SettingsSidebar(
                    tabState: tabState,
                    isCompact: layout.sidebar == .icons,
                    forcedCompact: $forcedCompact
                )
                Divider()
                let pageWidth = proxy.size.width - (layout.sidebar == .icons
                    ? SettingsMetrics.sidebarCollapsedWidth : SettingsMetrics.sidebarWidth)
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
                        header
                        SettingsPageColumn(
                            store: store,
                            coordinator: coordinator,
                            tabState: tabState,
                            onShowWelcomeGuide: onShowWelcomeGuide
                        )
                    }
                    .padding(.top, 8)
                }
                .environment(\.settingsLiveWindowWidth, pageWidth)
            }
        }
    }

    private var header: some View {
        let tab = tabState.selected
        return HStack(spacing: 12) {
            Image(systemName: tab.symbolName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tab.hueColor.gradient))
            Text(tab.title)
                .font(.system(size: 24, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SettingsMetrics.paneMargin)
    }
}
