import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - MB-6: Menu Bar Creative Hub (Hop 2x2 Box Grid + OnlySwitch Tabs)

/// Width of the Hub's stacked rows, measured from the plain "Window Layouts" button; the borderless
/// `Menu` rows below it need a definite width or they shrink to their own labels.
private struct HubMenuRowWidth: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct MenuBarCreativeHubView: View {
    var onDismiss: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    /// Pointer tip, in points from the panel's leading edge; the controller passes the icon centre.
    var caretX: CGFloat = 190

    static let panelWidth: CGFloat = 380
    static let panelHeight: CGFloat = 560

    @ObservedObject private var engine = QuickToggleEngine.shared
    @ObservedObject private var scheduler = HubScheduleCoordinator.shared
    @StateObject private var status = SystemStatusService()
    @State private var selectedTab: MenuBarHubTab = MenuBarHubTab.visibleTabs().first ?? .switches
    @State private var query = ""
    @State private var boxSlots: [HubActionSlotID] = HubActionSlotID.slots()
    @State private var btAudioDevices: [BluetoothDevice] = []
    @State private var listeningMode: String? = AudioOutputSwitcher.bluetoothListeningMode()
    @State private var brightness: Double? = DisplayBrightness.levelForCursorScreen()
    /// MD-5: external volume, read once per open; nil hides the slider.
    @State private var displayVolume: Double?
    @State private var keyLight: Double? = KeyboardBacklight.isAvailable ? KeyboardBacklight.current() : nil
    @State private var shortcutNames: [String] = []
    @State private var shortcutsLoaded = false
    @State private var evolutions: [EvolutionItem] = EvolutionItem.parse(UserDefaults.standard.data(forKey: EvolutionItem.defaultsKey))
    @State private var showAddEvolution = false
    @State private var evoTitle = ""
    @State private var evoScript = ""
    @State private var evoShell: EvolutionItem.Shell = .sh
    @State private var showAddSchedule = false
    @State private var schedTarget: QuickToggleID = .keepAwake
    @State private var schedDesiredState = true
    @State private var schedIsDaily = false
    @State private var schedMinutes = 30
    @State private var schedTime = Date()
    @State private var surfaceVersion = 0
    /// Tier B: empty (the default) keeps every opt-in module out of the tree entirely.
    @AppStorage(HubModule.storageKey) private var modulesRaw = ""
    @State private var showUninstaller = false
    /// SN-6: saved display arrangements and cached display modes, loaded on open / screen change.
    @State private var arrangements: [DisplayArrangement] = []
    @State private var displayModeTargets: [(id: CGDirectDisplayID, name: String, screen: NSScreen, options: [DisplayModeOption])] = []
    @State private var liveDisplayKeys: Set<String> = []
    /// The two menu rows are `Menu`s, and a borderless `Menu` shrinks to its label's ideal width, which
    /// left "Display Mode" and "Arrangements" floating as small controls instead of rows. The plain
    /// "Window Layouts" button above them fills the column, so its measured width is the width every
    /// row in this list uses.
    @State private var menuRowWidth: CGFloat = 0
    @State private var calendarMonth = Date()
    @AppStorage(HubActionLayout.widthsKey) private var boxWidthsRaw = "half,half,half,half"
    @ObservedObject private var keepAwake = KeepAwakeService.shared
    @AppStorage(HubAppearancePreset.storageKey) private var appearanceRaw = HubAppearancePreset.default.rawValue
    @AppStorage("com.katikati.stayawake.preset") private var awakePresetRaw = 30
    @State private var disk: DiskUsage?
    @State private var lidNeedsAdmin = false

    @Environment(\.dockThemeStyle) private var dockThemeStyle
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: DockThemeTokens { .resolved(for: colorScheme, style: dockThemeStyle) }
    private var palette: SettingsIridescentPalette { .resolve(style: dockThemeStyle, colorScheme: colorScheme) }
    private var ink: Color { theme.labelActive.color }
    private var appearance: HubAppearancePreset { HubAppearancePreset.parse(appearanceRaw) }
    /// Secondary ink comes from the primary ink, never a washed tint, so one preset value raises every
    /// subtitle and caption together.
    private var inkSoft: Color { ink.opacity(appearance.secondaryInk) }
    private var cardFill: Color { Color.primary.opacity((colorScheme == .dark ? 0.08 : 0.05) * appearance.cardScale) }
    private var cardStroke: Color { Color.primary.opacity((colorScheme == .dark ? 0.12 : 0.08) * appearance.cardScale) }
    private var awakePreset: StayAwakePreset { StayAwakePreset(rawValue: awakePresetRaw) ?? .m30 }
    private var tabs: [MenuBarHubTab] { MenuBarHubTab.visibleTabs() }
    private var modules: Set<HubModule> { HubModule.enabled(modulesRaw) }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: HubCaretPlan.height)
            hubBody
        }
        .frame(width: Self.panelWidth, height: Self.panelHeight + HubCaretPlan.height, alignment: .top)
        .background {
            // One plate: the body's backdrop is masked to body + pointer, and one rim strokes the
            // combined outline, so the joint cannot show a material or rim seam.
            ZStack {
                DockPanelBackdrop(theme: theme, cornerRadius: 0,
                                  usesLiquidGlass: DockGlassPresentation.shouldAttemptTaskbarComposite)
                // The finish's scrim: glass keeps a small legibility floor, the solid presets buy contrast.
                Color(colorScheme == .dark ? .black : .white).opacity(appearance.plateScrim)
                palette.primaryAccent.opacity(appearance.accentTint)
            }
                .mask(HubPlateShape(caretCenter: plateCaretX).fill(Color.black))
        }
        .overlay {
            HubPlateShape(caretCenter: plateCaretX)
                .stroke(theme.panelRimStyle, lineWidth: theme.panelRimLineWidth)
        }
        .sheet(isPresented: $showUninstaller) { HubUninstallerSheet() }
        .onAppear {
            engine.refresh(); status.acquire(); boxSlots = HubActionSlotID.slots()
            arrangements = DisplayArrangementStore.load()
            reloadDisplayCache()
            if !tabs.contains(selectedTab), let first = tabs.first { selectedTab = first }
            // MD-5: the external panel's own volume, read once per open (nil hides the slider).
            displayVolume = DisplayBrightness.volumeForCursorScreen()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            reloadDisplayCache()
        }
        .onReceive(NotificationCenter.default.publisher(for: DisplayBrightness.didUpdateNotification)) { _ in
            if let current = DisplayBrightness.levelForCursorScreen() {
                brightness = current
            }
            displayVolume = DisplayBrightness.volumeForCursorScreen()
        }
        .onDisappear { status.release() }
        .onChange(of: selectedTab) { _, _ in query = "" }
        .task {
            await DockDevicesFeed.shared.refreshIfStale(maxAge: 5)
            btAudioDevices = DockDevicesFeed.shared.devices.filter { $0.lowestBattery != nil }
            disk = SystemMonitorSampler.disk()
        }
    }

    private var plateCaretX: CGFloat {
        HubCaretPlan.centerX(iconCenter: caretX, panelWidth: Self.panelWidth)
    }

    private var hubBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerBar
            tabContent
        }
        .padding(12)
        .frame(width: Self.panelWidth, height: Self.panelHeight, alignment: .top)
    }

    private var headerBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                ForEach(tabs) { tab in
                    let active = selectedTab == tab
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.8)) { selectedTab = tab }
                    } label: {
                        Image(systemName: tab.symbolName).font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(active ? Color.white : inkSoft).frame(width: 30, height: 26)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(active ? AnyShapeStyle(palette.pillGradient) : AnyShapeStyle(Color.clear)))
                    }.buttonStyle(.plain)
                }
            }
            .padding(2).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(cardFill))

            Spacer(minLength: 4)

            Menu {
                ForEach(HubAppearancePreset.allCases) { preset in
                    Button { appearanceRaw = preset.rawValue } label: {
                        if preset == appearance { Label(preset.title, systemImage: "checkmark") }
                        else { Text(verbatim: preset.title) }
                    }
                }
            } label: {
                Image(systemName: "circle.lefthalf.filled").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(inkSoft).frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(cardFill))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help(Text("Appearance"))

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape").font(.system(size: 12, weight: .medium)).foregroundStyle(inkSoft)
                    .frame(width: 26, height: 26).background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(cardFill))
            }.buttonStyle(.plain).help(Text("Open Settings…"))
        }
    }

    private var boxWidths: [HubActionWidth] {
        let parsed = boxWidthsRaw.split(separator: ",").compactMap { HubActionWidth(rawValue: String($0)) }
        return (0..<4).map { $0 < parsed.count ? parsed[$0] : .half }
    }

    /// Two half tiles share a row; a full tile takes the whole row. Building rows here (instead of a
    /// LazyVGrid) is what lets one tile span the panel without a second layout pass.
    private var boxRows: [[HubActionRowEntry]] {
        let widths = boxWidths
        var rows: [[HubActionRowEntry]] = []
        var index = 0
        while index < boxSlots.count {
            var row = [HubActionRowEntry(index: index, slot: boxSlots[index])]
            if widths[index] == .half, index + 1 < boxSlots.count, widths[index + 1] == .half {
                row.append(HubActionRowEntry(index: index + 1, slot: boxSlots[index + 1]))
                index += 1
            }
            rows.append(row)
            index += 1
        }
        return rows
    }

    private var actionBoxGrid: some View {
        LazyVStack(spacing: 8) {
            ForEach(Array(boxRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row) { entry in boxTile(slot: entry.slot, index: entry.index) }
                }
            }
        }
    }

    private func boxTile(slot: HubActionSlotID, index: Int) -> some View {
        let on = boxState(slot)
        return Button { performBox(slot) } label: {
            HStack(spacing: 8) {
                Image(systemName: boxSymbol(slot)).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(on ? Color.white : ink).frame(width: 28, height: 28)
                    .background(Circle().fill(on ? AnyShapeStyle(palette.pillGradient) : AnyShapeStyle(cardFill)))
                VStack(alignment: .leading, spacing: 1) {
                    boxTitle(slot).font(.system(size: 12, weight: .semibold)).foregroundStyle(ink).lineLimit(1)
                    Text(on ? String(localized: "On") : String(localized: "Off")).font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(on ? palette.primaryAccent : inkSoft)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? palette.primaryAccent.opacity(0.16) : cardFill))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? palette.primaryAccent.opacity(0.45) : cardStroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.72), value: on)
        .contextMenu {
            Section("Size") {
                Button { setBoxWidth(index, .half) } label: {
                    Label("Half Width", systemImage: boxWidths[index] == .half ? "checkmark" : "rectangle.lefthalf.filled")
                }
                Button { setBoxWidth(index, .full) } label: {
                    Label("Full Width", systemImage: boxWidths[index] == .full ? "checkmark" : "rectangle.fill")
                }
            }
            Button { moveBox(index, by: -1) } label: { Label("Move Left", systemImage: "arrow.left") }
                .disabled(index == 0)
            Button { moveBox(index, by: 1) } label: { Label("Move Right", systemImage: "arrow.right") }
                .disabled(index == boxSlots.count - 1)
            Menu {
                ForEach(HubActionSlotID.allCases) { candidate in
                    Button { replaceBox(index, with: candidate) } label: { boxTitle(candidate) }
                }
            } label: { Text("Replace") }
            Divider()
            Button(role: .destructive) { removeBox(index) } label: { Label("Remove", systemImage: "trash") }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .switches: switchesBody
        case .statusAudio: statusAudioBody
        case .shortcutsEvolutions: shortcutsEvolutionsBody
        case .schedules: schedulesBody
        }
    }

    private var switchesBody: some View {
        let items = HubSwitchCatalog.filter(HubSwitchCatalog.orderedSwitches(), query: query) { switchLabel($0) }
            .filter { !$0.isDuplicated(by: boxSlots) && !Self.isKeepAwake($0) }
        return ScrollView {
            VStack(spacing: 6) {
                // Page one's own actions, not global chrome repeated above every tab.
                actionBoxGrid
                // SN-2: snApp lives in the Hub rather than on a second status item, so the menu bar
                // keeps the one consolidated icon this app settled on.
                snapPickerRow
                displayModeRow
                arrangementRow
                keepAwakeCard
                pageSearchField
                if let buds = btAudioDevices.first, let level = buds.lowestBattery {
                    airPodsPill(device: buds, battery: level)
                }
                ForEach(items) { item in switchRow(item) }
                if modules.contains(.uninstaller) {
                    Button { showUninstaller = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "trash").font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.primaryAccent).frame(width: 18)
                            Text("Uninstaller").font(.system(size: 11.5, weight: .medium)).foregroundStyle(ink)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 9))
                                .foregroundStyle(inkSoft)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(cardFill))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .onPreferenceChange(HubMenuRowWidth.self) { menuRowWidth = $0 }
        }
    }

    /// SN-6: the modes the panel really advertises, HiDPI rows included. Each apply is provisional for
    /// fifteen seconds, so a mode the screen cannot show reverts on its own.
    private var displayModeRow: some View {
        Menu {
            if displayModeTargets.count <= 1, let only = displayModeTargets.first {
                ForEach(only.options) { option in
                    Button(option.label) {
                        DisplayModeSwitcher.shared.apply(option, on: only.screen)
                    }
                }
            } else {
                ForEach(displayModeTargets, id: \.id) { target in
                    Menu {
                        ForEach(target.options) { option in
                            Button(option.label) {
                                DisplayModeSwitcher.shared.apply(option, on: target.screen)
                            }
                        }
                    } label: {
                        Text(verbatim: target.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "display").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.primaryAccent).frame(width: 18)
                Text("Display Mode").font(.system(size: 11.5, weight: .medium)).foregroundStyle(ink)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(inkSoft)
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .frame(width: menuRowWidth > 0 ? menuRowWidth : nil, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(cardFill))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    /// SN-6: where the displays sit, saved and re-applied by display UUID.
    private var arrangementRow: some View {
        Menu {
            Button("Save Current Arrangement") { saveArrangement() }
            if !arrangements.isEmpty {
                Divider()
                ForEach(arrangements) { preset in
                    let complete = DisplayArrangementGeometry.isComplete(preset, liveKeys: liveDisplayKeys)
                    Button(preset.name) { DisplayModeService.applyArrangement(preset) }
                        .disabled(!complete)
                }
                Menu {
                    ForEach(arrangements) { preset in
                        Button(preset.name, role: .destructive) { removeArrangement(preset.id) }
                    }
                } label: {
                    Text("Remove")
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.3.group").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.primaryAccent).frame(width: 18)
                Text("Arrangements").font(.system(size: 11.5, weight: .medium)).foregroundStyle(ink)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(inkSoft)
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .frame(width: menuRowWidth > 0 ? menuRowWidth : nil, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(cardFill))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    private func reloadDisplayCache() {
        let screens = NSScreen.screens
        liveDisplayKeys = Set(screens.compactMap { DisplayIdentity.uuidString(for: $0) })
        displayModeTargets = screens.compactMap { screen in
            guard let id = DisplayModeService.displayID(for: screen) else { return nil }
            let options = DisplayModeCatalog.sorted(DisplayModeService.modes(for: id).map { DisplayModeService.option(for: $0) })
            return (id: id, name: screen.localizedName, screen: screen, options: options)
        }
    }

    private func saveArrangement() {
        guard let preset = DisplayModeService.captureArrangement(named: "Arrangement \(arrangements.count + 1)") else { return }
        arrangements.append(preset)
        DisplayArrangementStore.save(arrangements)
    }

    private func removeArrangement(_ id: UUID) {
        arrangements.removeAll { $0.id == id }
        DisplayArrangementStore.save(arrangements)
    }

    /// Opens the layout grid next to the Hub's own caret, then gets out of its way.
    private var snapPickerRow: some View {
        Button {
            onDismiss()
            DispatchQueue.main.async { SnapPickerController.shared.present() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.split.2x2").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.primaryAccent).frame(width: 18)
                Text("Window Layouts").font(.system(size: 11.5, weight: .medium)).foregroundStyle(ink)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(inkSoft)
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(cardFill))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: HubMenuRowWidth.self, value: proxy.size.width)
        })
    }

    private static func isKeepAwake(_ item: HubSwitchID) -> Bool {
        if case .system(.keepAwake) = item { return true }
        return false
    }

    private var pageSearchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(inkSoft)
            TextField(String(localized: "Search"), text: $query)
                .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(ink)
        }
        .padding(.horizontal, 7).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(cardFill))
    }

    /// Keep Awake grown from a bare toggle into a timer: the chips choose how long a manual hold lasts,
    /// and lid-closed is opt-in next to it (the service still owns the admin prompt and the battery floor).
    private var keepAwakeCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(keepAwake.decision.hold ? palette.primaryAccent : ink)
                    .frame(width: 28, height: 28).background(Circle().fill(cardFill))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Keep Awake").font(.system(size: 12, weight: .semibold)).foregroundStyle(ink)
                    Text(verbatim: keepAwakeStatusLine).font(.system(size: 10, weight: .medium))
                        .foregroundStyle(inkSoft).lineLimit(1)
                }
                Spacer(minLength: 0)
                Toggle(isOn: Binding(get: { keepAwake.manualOn }, set: { on in
                    keepAwake.setManual(on, duration: on ? awakePreset.duration : nil)
                })) { EmptyView() }
                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }
            HStack(spacing: 4) {
                ForEach(StayAwakePreset.allCases, id: \.self) { option in
                    let active = keepAwake.manualOn && option == awakePreset
                    Button {
                        awakePresetRaw = option.rawValue
                        keepAwake.setManual(true, duration: option.duration)
                    } label: {
                        Text(verbatim: option.label)
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundStyle(active ? Color.white : inkSoft)
                            .frame(maxWidth: .infinity, minHeight: 22)
                            .background(Capsule().fill(active ? AnyShapeStyle(palette.pillGradient) : AnyShapeStyle(cardFill)))
                    }.buttonStyle(.plain)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "laptopcomputer").font(.system(size: 11)).foregroundStyle(inkSoft).frame(width: 16)
                Text("Lid closed").font(.system(size: 11, weight: .medium)).foregroundStyle(ink)
                Spacer(minLength: 0)
                Toggle(isOn: Binding(get: { keepAwake.lidClosedEnabled }, set: { on in
                    Task { lidNeedsAdmin = !(await keepAwake.setLidClosed(on)) }
                })) { EmptyView() }
                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                .help(Text("Keep running with the lid shut"))
            }
            if lidNeedsAdmin {
                Text("Admin approval was not given").font(.system(size: 9.5)).foregroundStyle(.orange)
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cardFill))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(cardStroke, lineWidth: 1))
    }

    private var keepAwakeStatusLine: String {
        guard keepAwake.decision.hold else { return String(localized: "Off") }
        if keepAwake.decision.reason == .manual, let end = keepAwake.manualEnd {
            return String(format: String(localized: "Until %@"), end.formatted(date: .omitted, time: .shortened))
        }
        if keepAwake.manualOn { return String(localized: "Until you turn it off") }
        return String(localized: "AI agents")
    }

    private func airPodsPill(device: BluetoothDevice, battery: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: device.symbolName).font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.primaryAccent)
                Text(verbatim: device.name).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(ink).lineLimit(1)
                Spacer()
                Text(verbatim: "\(battery)%").font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(battery <= 20 ? Color.red : ink)
            }
            if AudioOutputSwitcher.canSetBluetoothListeningMode() {
                HStack(spacing: 4) {
                    ForEach(BluetoothListeningMode.allCases) { mode in
                        let active = listeningMode == mode.rawValue
                        Button {
                            if AudioOutputSwitcher.setBluetoothListeningMode(mode.rawValue) { listeningMode = mode.rawValue }
                        } label: {
                            Image(systemName: mode.symbolName).font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(active ? Color.white : inkSoft).frame(maxWidth: .infinity, minHeight: 22)
                                .background(Capsule().fill(active ? AnyShapeStyle(palette.pillGradient) : AnyShapeStyle(cardFill)))
                        }.buttonStyle(.plain).help(Text(verbatim: mode.title))
                    }
                }
            }
        }
        .padding(9).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cardFill))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(cardStroke, lineWidth: 1))
    }

    private func switchRow(_ item: HubSwitchID) -> some View {
        let on = switchState(item)
        return HStack(spacing: 9) {
            Image(systemName: switchSymbol(item)).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(on ? palette.primaryAccent : ink)
                .frame(width: 28, height: 28)
                .background(Circle().fill(cardFill))
            Text(verbatim: switchLabel(item)).font(.system(size: 12, weight: .semibold)).foregroundStyle(ink).lineLimit(1)
            Spacer()
            if case .system(let q) = item, q.isAction {
                Button { engine.perform(q) } label: {
                    Image(systemName: engine.flash == q ? "checkmark" : "play.fill").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ink).padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(cardFill))
                }.buttonStyle(.plain)
            } else {
                Toggle(isOn: Binding(get: { on }, set: { toggleSwitch(item, to: $0) })) { EmptyView() }
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }
        }
        // Same 28 pt glyph well and 7.5 pt inset as the action tiles, so every row is 43 pt tall.
        .padding(.horizontal, 9).padding(.vertical, 7.5)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cardFill))
    }

    private var statusAudioBody: some View {
        let bat = status.status.battery
        let wifi = status.status.wifi
        let vol = status.status.volume
        let outputs = AudioOutputSwitcher.devices(input: false)
        return ScrollView {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    telemetryCard(symbol: bat.symbolName, title: String(localized: "Battery"),
                                  value: bat.level.map { "\($0)%" } ?? "–",
                                  detail: bat.facts.summary ?? (bat.isCharging ? String(localized: "Charging") : String(localized: "On Battery")))
                    telemetryCard(symbol: wifi.symbolName, title: String(localized: "Network"),
                                  value: status.status.wiredEthernetConnected ? String(localized: "Network") : (wifi.ssid ?? (wifi.isConnected ? String(localized: "On") : String(localized: "Offline"))),
                                  detail: wifi.rssi.map { "\($0) dBm" } ?? (wifi.isPoweredOn ? String(localized: "Not Connected") : String(localized: "Wi-Fi Off")))
                }
                storageCard
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Audio Output").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(ink)
                        Spacer()
                        Button { _ = status.toggleMute() } label: {
                            Image(systemName: vol.symbolName).font(.system(size: 11)).foregroundStyle(vol.isMuted ? Color.red : inkSoft)
                        }.buttonStyle(.plain)
                    }
                    ForEach(outputs) { dev in
                        Button { _ = AudioOutputSwitcher.setDefault(dev.id, input: false); surfaceVersion += 1 } label: {
                            HStack(spacing: 6) {
                                Image(systemName: dev.isDefault ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 10.5)).foregroundStyle(dev.isDefault ? palette.primaryAccent : inkSoft)
                                Text(verbatim: dev.name).font(.system(size: 11)).foregroundStyle(ink).lineLimit(1)
                                Spacer()
                            }
                        }.buttonStyle(.plain)
                    }
                    hubSlider(icon: vol.symbolName, label: Text("Volume"), value: Binding(get: { Double(vol.level) }, set: { _ = status.setVolume(Float($0)) }))
                    if modules.contains(.audioMixer) {
                        Divider().overlay(cardStroke)
                        HubAudioMixerSection()
                    }
                }
                .padding(9).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cardFill))
                if brightness != nil || keyLight != nil || displayVolume != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            Image(systemName: "sun.max.fill").font(.system(size: 10.5)).foregroundStyle(palette.primaryAccent)
                            Text("Display & Keyboard").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(ink)
                            Spacer()
                        }
                        if let brightness {
                            hubSlider(icon: "sun.max.fill", label: Text("Brightness"), value: Binding(get: { brightness }, set: { self.brightness = $0; DisplayBrightness.setOnCursorScreen($0) }))
                        }
                        if let displayVolume {
                            hubSlider(icon: "speaker.wave.2.fill", label: Text("Display Volume"), value: Binding(get: { displayVolume }, set: { self.displayVolume = $0; DisplayBrightness.setVolumeOnCursorScreen($0) }))
                        }
                        if let keyLight {
                            hubSlider(icon: "keyboard", label: Text("Keyboard"), value: Binding(get: { keyLight }, set: { self.keyLight = $0; KeyboardBacklight.set($0) }))
                        }
                    }
                    .padding(9).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cardFill))
                }
                if !btAudioDevices.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(btAudioDevices) { dev in
                            HStack(spacing: 6) {
                                Image(systemName: dev.symbolName).font(.system(size: 11)).foregroundStyle(inkSoft).frame(width: 16)
                                Text(verbatim: dev.name).font(.system(size: 11)).foregroundStyle(ink).lineLimit(1)
                                Spacer()
                                if let lvl = dev.lowestBattery {
                                    Text(verbatim: "\(lvl)%").font(.system(size: 10.5, weight: .semibold)).monospacedDigit()
                                        .foregroundStyle(lvl <= 20 ? Color.red : inkSoft)
                                }
                            }
                        }
                    }
                    .padding(9).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cardFill))
                }
                if modules.contains(.agents) { HubAgentCard() }
            }
        }
    }

    private func telemetryCard(symbol: String, title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(palette.primaryAccent)
                Text(verbatim: title).font(.system(size: 10.5, weight: .medium)).foregroundStyle(inkSoft)
            }
            Text(verbatim: value).font(.system(size: 14, weight: .bold)).monospacedDigit().foregroundStyle(ink).lineLimit(1)
            Text(verbatim: detail).font(.system(size: 9.5)).foregroundStyle(inkSoft).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cardFill))
    }

    /// Page two owns the machine's story: battery, network and now the boot volume. One read on
    /// appear, not a poll — the hub never wakes the disk just to keep a percentage honest.
    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "internaldrive.fill").font(.system(size: 10.5)).foregroundStyle(palette.primaryAccent)
                Text("Storage").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(ink)
                Spacer()
                Text(verbatim: disk.map { "\($0.usedPercent)%" } ?? "–")
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(inkSoft)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule().fill(palette.primaryAccent.gradient)
                        .frame(width: proxy.size.width * CGFloat(disk?.usedFraction ?? 0))
                }
            }
            .frame(height: 5)
            HStack(spacing: 4) {
                Text("Used").font(.system(size: 10)).foregroundStyle(inkSoft)
                Text(verbatim: disk?.usedLabel ?? "–").font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(ink)
                Spacer(minLength: 0)
                Text("Available").font(.system(size: 10)).foregroundStyle(inkSoft)
                Text(verbatim: disk?.availableLabel ?? "–").font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(ink)
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cardFill))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(cardStroke, lineWidth: 1))
    }

    /// iPadOS-style level: a 34 pt capsule with a large white knob and the glyph sitting in the fill.
    /// The native slider is kept underneath at near-zero opacity so dragging, keyboard and
    /// Accessibility (AXSlider) behave exactly as before; only the drawing is bolder. The name sits in
    /// a leading column rather than inside the capsule: the fill can be as narrow as the knob, and text
    /// riding on it would change colour as the value moved. This hub has the same two-speaker problem as
    /// the Control Centre panel — system volume in one card, the external panel's own volume in another.
    private func hubSlider(icon: String, label: Text, value: Binding<Double>) -> some View {
        let fraction = min(max(value.wrappedValue, 0), 1)
        return HStack(spacing: 7) {
            label.font(.system(size: 11, weight: .semibold))
                .foregroundStyle(inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 92, alignment: .leading)
                .accessibilityHidden(true)
            GeometryReader { geo in
                let height = geo.size.height
                let knob = height - 8
                let travel = max(0, geo.size.width - knob - 6)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08))
                    // Neutral, like Control Center: the fill is ink, not an accent gradient.
                    Capsule().fill(ink.opacity(colorScheme == .dark ? 0.9 : 0.82))
                        .frame(width: max(height, geo.size.width * fraction))
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(colorScheme == .dark ? Color.black.opacity(0.72) : Color.white)
                        .padding(.leading, 12)
                    Circle().fill(.white)
                        .frame(width: knob, height: knob)
                        .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
                        .offset(x: 3 + travel * fraction)
                    Slider(value: value, in: 0...1)
                        .controlSize(.small)
                        .tint(.clear)
                        .opacity(0.02)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    value.wrappedValue = min(max((drag.location.x - 3) / max(travel, 1), 0), 1)
                })
            }
            .frame(height: 34)
            Text(verbatim: "\(Int((fraction * 100).rounded()))")
                .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                .foregroundStyle(inkSoft).frame(width: 28, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(Text(verbatim: "\(Int((fraction * 100).rounded()))"))
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 0.05 : -0.05
            value.wrappedValue = min(1, max(0, value.wrappedValue + step))
        }
    }

    // MARK: - MB-7: Shortcuts & Evolutions + Schedules

    private var shortcutsEvolutionsBody: some View {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredEvos = q.isEmpty ? evolutions : evolutions.filter { $0.title.localizedCaseInsensitiveContains(q) }
        let filteredSC = q.isEmpty ? shortcutNames : shortcutNames.filter { $0.localizedCaseInsensitiveContains(q) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                pageSearchField
                HStack {
                    Text("Custom").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(ink)
                    Spacer()
                    Button { showAddEvolution.toggle() } label: {
                        Label(String(localized: "Add"), systemImage: "plus").font(.system(size: 10.5, weight: .medium))
                    }.buttonStyle(.plain).foregroundStyle(palette.primaryAccent)
                }
                if showAddEvolution { addEvolutionForm }
                ForEach(filteredEvos) { evo in
                    HStack(spacing: 8) {
                        Image(systemName: evo.symbolName).font(.system(size: 11)).foregroundStyle(palette.primaryAccent).frame(width: 18)
                        Text(verbatim: evo.title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(ink).lineLimit(1)
                        Spacer()
                        Button { Task { _ = await EvolutionRunner.run(evo) } } label: {
                            Text("Run").font(.system(size: 10, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(cardFill))
                        }.buttonStyle(.plain)
                        Button { deleteEvolution(evo.id) } label: {
                            Image(systemName: "trash").font(.system(size: 10)).foregroundStyle(inkSoft)
                        }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(cardFill))
                }

                HStack {
                    Text("Shortcuts").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(ink)
                    Spacer()
                    Button { Task { shortcutNames = await ShortcutsCatalogRunner.listNames() } } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 10.5)).foregroundStyle(inkSoft)
                    }.buttonStyle(.plain).help(Text("Refresh"))
                }.padding(.top, 2)

                if filteredSC.isEmpty {
                    Text("None").font(.system(size: 10.5)).foregroundStyle(inkSoft).padding(.vertical, 4)
                } else {
                    ForEach(filteredSC, id: \.self) { name in
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.fill").font(.system(size: 11)).foregroundStyle(palette.primaryAccent).frame(width: 18)
                            Text(verbatim: name).font(.system(size: 11.5)).foregroundStyle(ink).lineLimit(1)
                            Spacer()
                            Button { Task { _ = await ShortcutsCatalogRunner.runShortcut(named: name) } } label: {
                                Text("Run").font(.system(size: 10, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Capsule().fill(cardFill))
                            }.buttonStyle(.plain)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(cardFill))
                    }
                }
            }
        }
        .task {
            guard !shortcutsLoaded else { return }
            shortcutsLoaded = true
            shortcutNames = await ShortcutsCatalogRunner.listNames()
        }
    }

    private var addEvolutionForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(String(localized: "Name"), text: $evoTitle).textFieldStyle(.roundedBorder).font(.system(size: 11))
            TextField(String(localized: "Command"), text: $evoScript).textFieldStyle(.roundedBorder).font(.system(size: 11))
            HStack {
                Picker(selection: $evoShell) {
                    Text(verbatim: "sh").tag(EvolutionItem.Shell.sh)
                    Text(verbatim: "osascript").tag(EvolutionItem.Shell.appleScript)
                } label: { EmptyView() }.labelsHidden().pickerStyle(.segmented).frame(width: 130)
                Spacer()
                Button("Cancel") { showAddEvolution = false }.font(.system(size: 10.5))
                Button("Save") { saveEvolution() }
                    .font(.system(size: 10.5, weight: .semibold))
                    .disabled(evoTitle.trimmingCharacters(in: .whitespaces).isEmpty || evoScript.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(8).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(cardFill))
    }

    private func saveEvolution() {
        let item = EvolutionItem(title: evoTitle.trimmingCharacters(in: .whitespaces), shell: evoShell, runScript: evoScript)
        evolutions.append(item)
        UserDefaults.standard.set(EvolutionItem.encode(evolutions), forKey: EvolutionItem.defaultsKey)
        evoTitle = ""; evoScript = ""; showAddEvolution = false
    }

    private func deleteEvolution(_ id: UUID) {
        evolutions.removeAll { $0.id == id }
        UserDefaults.standard.set(EvolutionItem.encode(evolutions), forKey: EvolutionItem.defaultsKey)
    }

    private var schedulesBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                pageSearchField
                HStack {
                    Text("Schedule").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(ink)
                    Spacer()
                    Button { showAddSchedule.toggle() } label: {
                        Label(String(localized: "Add"), systemImage: "plus").font(.system(size: 10.5, weight: .medium))
                    }.buttonStyle(.plain).foregroundStyle(palette.primaryAccent)
                }
                if showAddSchedule { addScheduleForm }
                if scheduler.rules.isEmpty {
                    Text("None").font(.system(size: 10.5)).foregroundStyle(inkSoft).padding(.vertical, 4)
                } else {
                    ForEach(scheduler.rules) { rule in scheduleRow(rule) }
                }
                calendarCard
            }
        }
        .onAppear { scheduler.reload() }
    }

    /// A month view under the schedule list. Pure grid from `HubCalendarGrid`; the month names and
    /// weekday letters come from the user's calendar, so no new copy is needed.
    private var calendarCard: some View {
        let calendar = Calendar.current
        let cells = HubCalendarGrid.cells(for: calendarMonth, calendar: calendar)
        let symbols = HubCalendarGrid.weekdaySymbols(calendar)
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(verbatim: formatter.string(from: calendarMonth))
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(ink)
                Spacer()
                monthArrow("chevron.left", delta: -1)
                monthArrow("chevron.right", delta: 1)
            }
            HStack(spacing: 0) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                    Text(verbatim: symbol).font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(inkSoft).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: HubCalendarGrid.columns), spacing: 2) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    calendarDay(cell)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cardFill))
    }

    private func monthArrow(_ symbol: String, delta: Int) -> some View {
        Button {
            guard let next = Calendar.current.date(byAdding: .month, value: delta, to: calendarMonth) else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.85)) { calendarMonth = next }
        } label: {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(inkSoft).frame(width: 22, height: 22)
                .background(Circle().fill(cardFill))
        }.buttonStyle(.plain)
    }

    @ViewBuilder
    private func calendarDay(_ cell: HubCalendarCell) -> some View {
        if let day = cell.day {
            Text(verbatim: "\(day)")
                .font(.system(size: 11, weight: cell.isToday ? .bold : .medium)).monospacedDigit()
                .foregroundStyle(cell.isToday ? Color.white : ink)
                .frame(maxWidth: .infinity, minHeight: 24)
                .background {
                    if cell.isToday {
                        Circle().fill(palette.primaryAccent).frame(width: 24, height: 24)
                    }
                }
        } else {
            Color.clear.frame(height: 24)
        }
    }

    private var addScheduleForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker(selection: $schedTarget) {
                    ForEach(QuickToggleID.allCases.filter { !$0.isAction }, id: \.self) { id in id.title.tag(id) }
                } label: { EmptyView() }.labelsHidden().frame(maxWidth: .infinity)
                Picker(selection: $schedDesiredState) {
                    Text("On").tag(true); Text("Off").tag(false)
                } label: { EmptyView() }.labelsHidden().pickerStyle(.segmented).frame(width: 84)
            }
            HStack {
                Picker(selection: $schedIsDaily) {
                    Text("Timer").tag(false); Text("Daily").tag(true)
                } label: { EmptyView() }.labelsHidden().pickerStyle(.segmented).frame(width: 120)
                Spacer()
                if schedIsDaily {
                    DatePicker(selection: $schedTime, displayedComponents: .hourAndMinute) { EmptyView() }.labelsHidden()
                } else {
                    Stepper(value: $schedMinutes, in: 5...240, step: 5) {
                        Text(verbatim: "\(schedMinutes)m").font(.system(size: 11)).monospacedDigit()
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { showAddSchedule = false }.font(.system(size: 10.5))
                Button("Save") { saveSchedule() }.font(.system(size: 10.5, weight: .semibold))
            }
        }
        .padding(8).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(cardFill))
    }

    private func scheduleRow(_ rule: HubScheduleRule) -> some View {
        let title = HubSwitchID(token: rule.targetToken).map(switchLabel) ?? rule.targetToken
        let kindLabel: String = {
            switch rule.kind {
            case .afterMinutes(let m): return "\(m)m"
            case .daily(let h, let m): return String(format: "%02d:%02d", h, m)
            }
        }()
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "\(title) · \(rule.desiredState ? String(localized: "On") : String(localized: "Off"))")
                    .font(.system(size: 11.5, weight: .medium)).foregroundStyle(ink).lineLimit(1)
                Text(verbatim: kindLabel).font(.system(size: 9.5)).monospacedDigit().foregroundStyle(inkSoft)
            }
            Spacer()
            Toggle(isOn: Binding(get: { rule.isEnabled }, set: { next in
                var list = scheduler.rules
                if let idx = list.firstIndex(where: { $0.id == rule.id }) { list[idx].isEnabled = next }
                scheduler.save(list)
            })) { EmptyView() }.labelsHidden().toggleStyle(.switch).controlSize(.mini)
            Button {
                scheduler.save(scheduler.rules.filter { $0.id != rule.id })
            } label: {
                Image(systemName: "trash").font(.system(size: 10)).foregroundStyle(inkSoft)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(cardFill))
    }

    private func setBoxWidth(_ index: Int, _ width: HubActionWidth) {
        guard boxWidths.indices.contains(index) else { return }
        var widths = boxWidths
        widths[index] = width
        boxWidthsRaw = HubActionLayout.serializeWidths(widths)
    }

    private func replaceBox(_ index: Int, with slot: HubActionSlotID) {
        guard boxSlots.indices.contains(index) else { return }
        var next = boxSlots
        next[index] = slot
        saveBoxes(next)
    }

    private func moveBox(_ index: Int, by delta: Int) {
        let target = index + delta
        guard boxSlots.indices.contains(index), boxSlots.indices.contains(target) else { return }
        var next = boxSlots
        next.swapAt(index, target)
        saveBoxes(next)
    }

    /// Removing keeps four tiles: the gap is filled from the default order with an action that is
    /// not already on the grid, so the panel never shrinks to a ragged row.
    private func removeBox(_ index: Int) {
        guard boxSlots.indices.contains(index) else { return }
        var next = boxSlots
        next.remove(at: index)
        if let filler = (HubActionSlotID.defaultSlots + HubActionSlotID.allCases).first(where: { !next.contains($0) }) {
            next.append(filler)
        }
        saveBoxes(next)
    }

    private func saveBoxes(_ slots: [HubActionSlotID]) {
        let trimmed = Array(slots.prefix(4))
        boxSlots = trimmed
        UserDefaults.standard.set(HubActionSlotID.serialize(trimmed), forKey: HubActionSlotID.defaultsKey)
    }

    private func saveSchedule() {
        let kind: HubScheduleRule.Kind
        if schedIsDaily {
            let c = Calendar.current.dateComponents([.hour, .minute], from: schedTime)
            kind = .daily(hour: c.hour ?? 9, minute: c.minute ?? 0)
        } else {
            kind = .afterMinutes(schedMinutes)
        }
        let rule = HubScheduleRule(targetToken: HubSwitchID.system(schedTarget).token, desiredState: schedDesiredState, kind: kind)
        scheduler.save(scheduler.rules + [rule])
        showAddSchedule = false
    }

    // MARK: - Helpers

    private func boxState(_ slot: HubActionSlotID) -> Bool {
        _ = surfaceVersion
        if slot == .muteOutput { return status.status.volume.isMuted }
        if slot == .notchToggle { return UserDefaults.standard.bool(forKey: "com.katikati.liveIsland.notch") }
        return QuickToggleID(rawValue: slot.rawValue).flatMap { engine.states[$0] } ?? false
    }

    private func performBox(_ slot: HubActionSlotID) {
        if slot == .captureOCR { onDismiss(); BarActionService.run(.ocr); return }
        if slot == .notchToggle {
            let next = !(AppDelegate.shared?.settingsStore.notchIslandEnabled ?? UserDefaults.standard.bool(forKey: "com.katikati.liveIsland.notch"))
            HubScheduleCoordinator.applySurface(.notch, enabled: next)
            surfaceVersion += 1
            return
        }
        if slot == .muteOutput { _ = status.toggleMute(); return }
        if slot == .lockScreen { onDismiss() }
        if let q = QuickToggleID(rawValue: slot.rawValue) { engine.perform(q) }
    }

    private func boxSymbol(_ slot: HubActionSlotID) -> String {
        if slot == .captureOCR { return "text.viewfinder" }
        if slot == .notchToggle { return KatiKatiSurfaceToggle.notch.symbolName }
        return QuickToggleID(rawValue: slot.rawValue)?.symbolName ?? "bolt.fill"
    }

    private func boxTitle(_ slot: HubActionSlotID) -> Text {
        if slot == .captureOCR { return Text("Capture Area") }
        if slot == .notchToggle { return Text("Notch") }
        return QuickToggleID(rawValue: slot.rawValue)?.title ?? Text(verbatim: slot.rawValue)
    }

    private func switchState(_ id: HubSwitchID) -> Bool {
        _ = surfaceVersion
        switch id {
        case .system(let q): return q == .muteOutput ? status.status.volume.isMuted : (engine.states[q] ?? false)
        case .surface(let s):
            let d = UserDefaults.standard
            switch s {
            case .notch: return AppDelegate.shared?.settingsStore.notchIslandEnabled ?? d.bool(forKey: "com.katikati.liveIsland.notch")
            case .desktopBoxes: return DesktopCanvasConfig.isFeatureEnabled()
            case .nowPlaying: return d.object(forKey: MusicSurfaceConfig.enabledKey) as? Bool ?? true
            case .lockScreenCard: return d.bool(forKey: MusicSurfaceConfig.lockScreenCardKey)
            case .metricsBar: return d.bool(forKey: MenuBarStatModel.masterEnabledKey)
            }
        case .shortcut, .evolution: return false
        }
    }

    private func toggleSwitch(_ id: HubSwitchID, to on: Bool) {
        switch id {
        case .system(let q): if q == .muteOutput { _ = status.toggleMute() } else { engine.perform(q) }
        case .surface(let s): HubScheduleCoordinator.applySurface(s, enabled: on); surfaceVersion += 1
        case .shortcut, .evolution: break
        }
    }

    private func switchSymbol(_ id: HubSwitchID) -> String {
        switch id {
        case .system(let q): return q.symbolName
        case .surface(let s): return s.symbolName
        case .shortcut: return "bolt.fill"
        case .evolution: return "terminal"
        }
    }

    private func switchLabel(_ id: HubSwitchID) -> String {
        switch id {
        case .system(let q): return q.localizedLabel
        case .surface(let s):
            switch s {
            case .notch: return String(localized: "Notch")
            case .desktopBoxes: return String(localized: "Desktop")
            case .nowPlaying: return String(localized: "Now Playing")
            case .lockScreenCard: return String(localized: "Lock Screen")
            case .metricsBar: return String(localized: "Menu Bar")
            }
        case .shortcut(let name): return name
        case .evolution(let uuid): return uuid.uuidString
        }
    }
}

// MARK: - MB-9: Agents (opt-in)

/// Title row shared by the opt-in module cards; each card supplies its own trailing accessory.
struct HubModuleCardHeader<Accessory: View>: View {
    let symbol: String
    let title: String
    let accessory: Accessory

    @Environment(\.dockThemeStyle) private var dockThemeStyle
    @Environment(\.colorScheme) private var colorScheme

    init(symbol: String, title: String, @ViewBuilder accessory: () -> Accessory) {
        self.symbol = symbol
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        let theme = DockThemeTokens.resolved(for: colorScheme, style: dockThemeStyle)
        let palette = SettingsIridescentPalette.resolve(style: dockThemeStyle, colorScheme: colorScheme)
        return HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.primaryAccent)
            Text(LocalizedStringKey(title)).font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(theme.labelActive.color)
            Spacer(minLength: 0)
            accessory
        }
    }
}

/// The plate both module cards sit on, so their padding, fill and edge cannot drift apart.
private struct HubModuleCardChrome: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 1))
    }
}

extension View {
    func hubModuleCardChrome() -> some View { modifier(HubModuleCardChrome()) }
}

/// The hub's opt-in agent card: today's spend, the loadout profile, and the approval-hook pause.
/// Created only while the module is on, so the singleton services below exist on the owner's terms.
struct HubAgentCard: View {
    @ObservedObject private var usage = AgentUsageService.shared
    @State private var hooksPaused = !ClaudeApprovalService.shared.isRunning
    @Environment(\.dockThemeStyle) private var dockThemeStyle
    @Environment(\.colorScheme) private var colorScheme

    private var theme: DockThemeTokens { .resolved(for: colorScheme, style: dockThemeStyle) }
    private var inkSoft: Color { theme.labelSubtitle.color }
    private var enabledCount: Int { AgentLoadoutSummary.enabledCount(usage.loadoutItems) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HubModuleCardHeader(symbol: "sparkles", title: "Agents") {
                Text(verbatim: AgentLoadoutSummary.badge(cost: usage.snapshot.todayCost,
                                                         enabled: enabledCount,
                                                         total: usage.loadoutItems.count))
                    .font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(inkSoft)
            }
            Picker(selection: Binding(
                get: { usage.activeProfile },
                set: { usage.applyLoadoutProfile($0) }
            )) {
                ForEach(LoadoutProfile.allCases) { profile in
                    Text(verbatim: profile.title).tag(profile)
                }
            } label: { EmptyView() }
            .labelsHidden().pickerStyle(.menu).controlSize(.small)

            Toggle(isOn: Binding(
                get: { hooksPaused },
                set: { paused in
                    hooksPaused = paused
                    if paused { ClaudeApprovalService.shared.stop() } else { ClaudeApprovalService.shared.start() }
                }
            )) {
                Text("Pause").font(.system(size: 10.5)).foregroundStyle(inkSoft)
            }
            .toggleStyle(.switch).controlSize(.mini)
        }
        .hubModuleCardChrome()
    }
}

// MARK: - MB-10: Audio Mixer (opt-in)

/// Per-app levels. The engine is created with this card and torn down when the tab changes, so the
/// module is off (and silent) the moment its view is gone.
/// Lives inside the Audio Output card: general output level and per-app levels are one audio story.
struct HubAudioMixerSection: View {
    @StateObject private var engine = PerAppAudioEngine()
    @Environment(\.dockThemeStyle) private var dockThemeStyle
    @Environment(\.colorScheme) private var colorScheme

    private var theme: DockThemeTokens { .resolved(for: colorScheme, style: dockThemeStyle) }
    private var palette: SettingsIridescentPalette { .resolve(style: dockThemeStyle, colorScheme: colorScheme) }
    private var ink: Color { theme.labelActive.color }
    private var inkSoft: Color { theme.labelSubtitle.color }

    private var audible: [AppAudioProcess] { engine.processes.filter(\.isRunningOutput) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HubModuleCardHeader(symbol: "slider.horizontal.3", title: "Audio Mixer") {
                Button { engine.refresh() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10)).foregroundStyle(inkSoft)
                }.buttonStyle(.plain).help(Text("Refresh"))
            }
            if engine.unavailable {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
                    Text("Audio route unavailable — allow System Audio Recording.")
                        .font(.system(size: 10.5, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color.orange)
            }
            if audible.isEmpty {
                Text("None").font(.system(size: 10.5)).foregroundStyle(inkSoft).padding(.vertical, 3)
            } else {
                ForEach(Array(audible.prefix(6))) { process in row(process) }
            }
        }
        .padding(.top, 2)
        .onAppear { engine.start() }
        .onDisappear { engine.stop() }
    }

    private func row(_ process: AppAudioProcess) -> some View {
        let failure = engine.failure(for: process)
        return VStack(spacing: 3) {
            HStack(spacing: 6) {
                Text(verbatim: process.name).font(.system(size: 12)).foregroundStyle(ink).lineLimit(1)
                if engine.isRouted(process) {
                    Circle().fill(palette.primaryAccent).frame(width: 5, height: 5)
                }
                Spacer(minLength: 0)
                Text(verbatim: "\(PerAppAudioRules.percent(engine.gain(for: process)))%")
                    .font(.system(size: 9.5)).monospacedDigit().foregroundStyle(inkSoft)
            }
            HStack(spacing: 6) {
                Button { engine.setMuted(!engine.isMuted(process), for: process) } label: {
                    Image(systemName: engine.isMuted(process) ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(engine.isMuted(process) ? Color.red : inkSoft)
                        .frame(width: 16)
                }.buttonStyle(.plain)
                Slider(value: Binding(
                    get: { engine.gain(for: process) },
                    set: { engine.setGain($0, for: process) }
                ), in: 0...1).controlSize(.mini).tint(palette.primaryAccent)
            }
            if let failure {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
                    Text(verbatim: failureText(failure)).font(.system(size: 9.5, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color.orange)
            }
        }
    }

    /// A rejected output layout is not a level problem, so it says so instead of blaming the volume.
    private func failureText(_ failure: PerAppAudioFailure) -> String {
        failure.isLayoutMismatch
            ? String(localized: "Output layout not supported")
            : String(localized: "Volume Unavailable")
    }
}

// MARK: - MB-11: Uninstaller (opt-in)

/// On-demand app removal sheet. Uses the launcher's scan and `AppRemovalPlanner` — the same plan the
/// launcher and Command Bar use — and never hard-deletes: every path goes to the Finder Trash.
struct HubUninstallerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [UninstallerEntry] = []
    @State private var query = ""
    @State private var pending: UninstallerEntry?
    @State private var moved = 0
    @State private var loading = true

    private var visible: [UninstallerEntry] { UninstallerCatalog.filter(entries, query: query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Uninstaller").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Cancel") { dismiss() }.font(.system(size: 11))
            }
            TextField(String(localized: "Search"), text: $query)
                .textFieldStyle(.roundedBorder).font(.system(size: 11))
            if loading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        if visible.isEmpty { Text("None").font(.system(size: 11)).foregroundStyle(.secondary) }
                        ForEach(visible) { entry in appRow(entry) }
                    }
                }
                .frame(minHeight: 180)
            }
            if let pending {
                confirmCard(pending)
            } else if moved > 0 {
                Text(verbatim: "\(moved)").font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 460, height: 520)
        .task {
            entries = await Task.detached(priority: .utility) {
                UninstallerCatalog.entries(from: LauncherIndexer.scanDirectories())
            }.value
            loading = false
        }
    }

    private func appRow(_ entry: UninstallerEntry) -> some View {
        Button { pending = entry } label: {
            HStack(spacing: 8) {
                Image(systemName: "app").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: entry.name).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                    Text(verbatim: entry.bundleID).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("Uninstall…").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func confirmCard(_ entry: UninstallerEntry) -> some View {
        let plan = removalPlan(entry)
        return VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: entry.name).font(.system(size: 11.5, weight: .semibold))
            ForEach(plan.paths.prefix(6), id: \.self) { path in
                Text(verbatim: path).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack {
                Spacer()
                Button("Cancel") { pending = nil }.font(.system(size: 10.5))
                Button("Move to Trash") {
                    let count = AppRemovalService.perform(plan)
                    moved += count
                    entries.removeAll { $0.id == entry.id }
                    pending = nil
                }
                .font(.system(size: 10.5, weight: .semibold))
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    private func removalPlan(_ entry: UninstallerEntry) -> AppRemovalPlan {
        var plan = AppRemovalService.plan(bundleID: entry.bundleID, name: entry.name,
                                          appPath: entry.path, removal: .uninstall)
        let residue = AppRemovalService.plan(bundleID: entry.bundleID, name: entry.name,
                                             appPath: entry.path, removal: .deleteData)
        plan.paths += residue.paths.filter { !plan.paths.contains($0) }
        return plan
    }
}

private struct HubActionRowEntry: Identifiable {
    let index: Int
    let slot: HubActionSlotID
    var id: Int { index }
}

/// Body and pointer as one outline. The panel's backdrop is masked to this path and the rim is
/// stroked from the same path, so the pointer carries the panel's exact material and tint and the
/// joint has no seam line of its own.
private struct HubPlateShape: Shape {
    var cornerRadius: CGFloat = 20
    var caretCenter: CGFloat

    func path(in rect: CGRect) -> Path {
        let caretHeight = HubCaretPlan.height
        let bodyRect = CGRect(x: rect.minX, y: rect.minY + caretHeight,
                              width: rect.width, height: rect.height - caretHeight)
        let body = CGPath(roundedRect: bodyRect, cornerWidth: cornerRadius,
                          cornerHeight: cornerRadius, transform: nil)
        let half = HubCaretPlan.halfWidth
        let cx = min(max(caretCenter, bodyRect.minX + cornerRadius + half),
                     bodyRect.maxX - cornerRadius - half)
        let base = bodyRect.minY + 0.5
        let caret = CGMutablePath()
        caret.move(to: CGPoint(x: cx - half, y: base))
        caret.addQuadCurve(to: CGPoint(x: cx, y: rect.minY),
                           control: CGPoint(x: cx - half * 0.5, y: rect.minY + caretHeight * 0.12))
        caret.addQuadCurve(to: CGPoint(x: cx + half, y: base),
                           control: CGPoint(x: cx + half * 0.5, y: rect.minY + caretHeight * 0.12))
        caret.closeSubpath()
        return Path(body.union(caret))
    }
}
