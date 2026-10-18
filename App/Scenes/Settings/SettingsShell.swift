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
    @AppStorage("com.katikati.settings.stage") private var stageRaw = SettingsStagePreference.top.rawValue
    @AppStorage("com.katikati.settings.stageFraction") private var stageFraction = Double(SettingsStageSize.defaultFraction)

    private var stagePreference: SettingsStagePreference { SettingsStagePreference(rawValue: stageRaw) ?? .top }

    var body: some View {
        GeometryReader { proxy in
            let layout = SettingsLayoutClass.resolve(
                windowWidth: proxy.size.width,
                windowHeight: proxy.size.height,
                sidebarForcedIcons: forcedCompact,
                stagePreference: tabState.selected.showsStage ? stagePreference : .off
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
                content(layout: layout, pageWidth: pageWidth, size: CGSize(width: pageWidth, height: proxy.size.height))
            }
        }
    }

    @ViewBuilder
    private func content(layout: SettingsLayoutClass, pageWidth: CGFloat, size: CGSize) -> some View {
        let page = ScrollView(.vertical) {
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
        switch layout.stage {
        case .top:
            let length = SettingsStageSize.length(fraction: stageFraction, available: size.height)
            VStack(spacing: 0) {
                SettingsStage(store: store).frame(height: length)
                SettingsStageHandle(axis: .horizontal, fraction: $stageFraction, available: size.height, length: length)
                page.environment(\.settingsLiveWindowWidth, pageWidth)
            }
        case .side:
            let stageWidth = SettingsStageSize.length(fraction: stageFraction, available: size.width)
            HStack(spacing: 0) {
                page.environment(\.settingsLiveWindowWidth, pageWidth - stageWidth)
                SettingsStageHandle(axis: .vertical, fraction: $stageFraction, available: size.width, length: stageWidth)
                SettingsStage(store: store).frame(width: stageWidth)
            }
        case .hidden:
            page.environment(\.settingsLiveWindowWidth, pageWidth)
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
            if tab.showsStage { stagePicker }
        }
        .padding(.horizontal, SettingsMetrics.paneMargin)
    }

    private var stagePicker: some View {
        Picker(selection: $stageRaw) {
            Image(systemName: "rectangle.topthird.inset.filled").tag(SettingsStagePreference.top.rawValue)
                .accessibilityLabel(Text("Preview on top"))
            Image(systemName: "rectangle.rightthird.inset.filled").tag(SettingsStagePreference.side.rawValue)
                .accessibilityLabel(Text("Preview on the side"))
            Image(systemName: "eye.slash").tag(SettingsStagePreference.off.rawValue)
                .accessibilityLabel(Text("Hide preview"))
        } label: {
            Text("Preview position")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 120)
        .help(Text("Preview position"))
    }
}
