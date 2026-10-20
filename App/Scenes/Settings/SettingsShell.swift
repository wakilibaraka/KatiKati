import SwiftUI

/// The Settings window's layout: sidebar on the left, the selected page scrolling on the right.
/// Nothing here is a fixed size; the window is freely resizable and `SettingsLayoutClass` decides
/// what the current size can show (Docs/SETTINGS_REDESIGN_PLAN.md §1).
struct SettingsShell: View {
    @ObservedObject var store: AppSettingsStore
    @ObservedObject var coordinator: SettingsCoordinator
    @ObservedObject var tabState: SettingsTabState
    let onShowWelcomeGuide: () -> Void

    @State private var focusSearch = 0
    @StateObject private var draft = SettingsDraft()
    @State private var confirmRevert = false
    @State private var rowTitles: [String] = []
    @State private var pulseRow: String?
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
                    forcedCompact: $forcedCompact,
                    focusSearch: focusSearch
                )
                Divider()
                let pageWidth = proxy.size.width - (layout.sidebar == .icons
                    ? SettingsMetrics.sidebarCollapsedWidth : SettingsMetrics.sidebarWidth)
                content(layout: layout, pageWidth: pageWidth, size: CGSize(width: pageWidth, height: proxy.size.height))
            }
        }
        .background(keyboardShortcuts)
        .alert(Text("Revert all changes?"), isPresented: $confirmRevert) {
            Button("Revert and Restart", role: .destructive) { draft.revertAndRelaunch() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Settings changed since you opened this window go back to their earlier values. KatiKati restarts to apply them.")
        }
    }

    /// ⌘F focuses the sidebar search; ⌘1…⌘9 jump to the first nine sections.
    private var keyboardShortcuts: some View {
        ZStack {
            Button { forcedCompact = false; focusSearch += 1 } label: { EmptyView() }.keyboardShortcut("f", modifiers: .command)
            ForEach(Array(SettingsTab.allCases.prefix(9).enumerated()), id: \.offset) { index, tab in
                Button { tabState.selected = tab } label: { EmptyView() }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
        }
        .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
    }

    @ViewBuilder
    private func content(layout: SettingsLayoutClass, pageWidth: CGFloat, size: CGSize) -> some View {
        let page = ScrollViewReader { reader in
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
            .environment(\.settingsPulseRow, pulseRow)
            .onPreferenceChange(SettingsRowTitlesKey.self) { rowTitles = $0 }
            // A page that changes the stage layout is a new view, so it sees the query on appear, not as a change.
            .onAppear { scheduleJump(reader) }
            .onChange(of: tabState.findQuery) { _ in scheduleJump(reader) }
        }
        Group { stageLayout(layout: layout, page: page, pageWidth: pageWidth, size: size) }
            .background(SettingsTimeGlow())
    }

    @ViewBuilder
    private func stageLayout<P: View>(layout: SettingsLayoutClass, page: P, pageWidth: CGFloat, size: CGSize) -> some View {
        switch layout.stage {
        case .top:
            let length = SettingsStageSize.length(fraction: stageFraction, available: size.height)
            VStack(spacing: 0) {
                SettingsStage(store: store, expandsNotch: tabState.selected == .notch, tab: tabState.selected).frame(height: length)
                SettingsStageHandle(axis: .horizontal, fraction: $stageFraction, available: size.height, length: length)
                page.environment(\.settingsLiveWindowWidth, pageWidth).environment(\.settingsStageVisible, true)
            }
        case .side:
            let stageWidth = SettingsStageSize.length(fraction: stageFraction, available: size.width)
            HStack(spacing: 0) {
                page.environment(\.settingsLiveWindowWidth, pageWidth - stageWidth).environment(\.settingsStageVisible, true)
                SettingsStageHandle(axis: .vertical, fraction: $stageFraction, available: size.width, length: stageWidth)
                SettingsStage(store: store, expandsNotch: tabState.selected == .notch, tab: tabState.selected).frame(width: stageWidth)
            }
        case .hidden:
            page.environment(\.settingsLiveWindowWidth, pageWidth)
        }
    }

    /// Waits for the new page to lay out so its row titles have been reported.
    private func scheduleJump(_ reader: ScrollViewProxy) {
        guard !tabState.findQuery.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { jumpToFoundRow(reader) }
    }

    /// Scrolls to and pulses the first row whose title matches the query that opened this page.
    private func jumpToFoundRow(_ reader: ScrollViewProxy) {
        let query = tabState.findQuery
        tabState.findQuery = ""
        guard !query.isEmpty, let title = rowTitles.first(where: { $0.localizedCaseInsensitiveContains(query) }) else { return }
        withAnimation(.easeInOut(duration: 0.4)) { reader.scrollTo(title, anchor: .center) }
        pulseRow = title
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if pulseRow == title { pulseRow = nil } }
    }

    private var header: some View {
        let tab = tabState.selected
        return HStack(spacing: 12) {
            Image(systemName: tab.symbolName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tab.hueColor.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.title)
                    .font(.system(size: 24, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                // Resolved in `SettingsTab.subtitle`; drawn verbatim, never re-localized.
                Text(tab.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if !draft.changedKeys.isEmpty {
                Button("Revert Changes") { confirmRevert = true }
                    .help(Text("Undo every change made since Settings opened"))
            }
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

/// What changed in UserDefaults since Settings opened, and a way back. The store has no reload path
/// (85 published properties set up in `init`), so Revert restores the keys and relaunches.
/// shortcut: Data blobs and `com.katikati.settings.` layout keys are skipped, so history stores and
/// window layout survive; per-section Revert needs a key-to-section map, add it when asked for.
@MainActor
final class SettingsDraft: ObservableObject {
    @Published private(set) var changedKeys: [String] = []
    private let baseline: [String: Any]
    private var observer: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        baseline = Self.settingsValues(defaults)
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: defaults, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(defaults) }
        }
    }

    deinit { observer.map(NotificationCenter.default.removeObserver) }

    private static func settingsValues(_ defaults: UserDefaults) -> [String: Any] {
        guard let id = Bundle.main.bundleIdentifier, let domain = defaults.persistentDomain(forName: id) else { return [:] }
        return domain.filter { !($0.value is Data) && !$0.key.hasPrefix("com.katikati.settings.") }
    }

    private func refresh(_ defaults: UserDefaults) {
        let now = Self.settingsValues(defaults)
        let keys = Set(baseline.keys).union(now.keys).filter { key in
            switch (baseline[key] as? NSObject, now[key] as? NSObject) {
            case let (a?, b?): return !a.isEqual(b)
            case (nil, nil): return false
            default: return true
            }
        }.sorted()
        if keys != changedKeys { changedKeys = keys }
    }

    /// Writes the baseline back for every changed key, then relaunches so the store reads it fresh.
    func revertAndRelaunch(defaults: UserDefaults = .standard) {
        for key in changedKeys {
            if let old = baseline[key] { defaults.set(old, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        defaults.synchronize()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", Bundle.main.bundleURL.path]
        try? process.run()
        NSApp.terminate(nil)
    }
}
