import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Desktop Folder Boxes configuration block mounted under Settings › Widgets.
struct DesktopSettingsBlock: View {
    @ObservedObject var store: AppSettingsStore
    @ObservedObject private var manager = DesktopCanvasManager.shared

    @AppStorage(DesktopCanvasConfig.enabledKey) private var enabled = true
    @AppStorage(DesktopCanvasConfig.snapGapKey) private var snapGap = DesktopCanvasConfig.defaultSnapGap
    @AppStorage(DesktopCanvasConfig.edgeMarginKey) private var edgeMargin = DesktopCanvasConfig.defaultEdgeMargin
    @AppStorage(DesktopCanvasConfig.doubleClickDesktopKey) private var doubleClickDesktop = false
    @AppStorage(DesktopCanvasConfig.showOnAllSpacesKey) private var showOnAllSpaces = true
    @AppStorage(DesktopCanvasConfig.materialStyleKey) private var materialStyleRaw = DesktopBoxMaterialStyle.inheritDock.rawValue
    @AppStorage(DesktopCanvasConfig.panoramaEnabledKey) private var panoramaEnabled = false
    @AppStorage(DesktopCanvasConfig.panoramaImagePathKey) private var panoramaImagePath = ""
    @AppStorage(DesktopCanvasConfig.panoramaOpacityKey) private var panoramaOpacity = DesktopCanvasConfig.defaultPanoramaOpacity
    @AppStorage(DesktopCanvasConfig.panoramaBlurKey) private var panoramaBlur = DesktopCanvasConfig.defaultPanoramaBlur
    @AppStorage(DesktopCanvasConfig.defaultCapsuleModeKey) private var defaultCapsuleModeRaw = "expanded"
    @AppStorage(DesktopCanvasConfig.panoramaScaleModeKey) private var panoramaScaleModeRaw = DesktopPanoramaScaleMode.aspectFill.rawValue

    var body: some View {
        SettingsCard(Text("Desktop Boxes")) {
            SettingsToggleRow(
                Text("Enable Desktop Boxes"),
                isOn: $enabled,
                info: String(localized: "Pin real Finder folders as floating glass boxes on your desktop.")
            )
            .onChange(of: enabled) { _, _ in
                AppDelegate.shared?.syncDesktopCanvasState()
            }

            if enabled, let coordinator = manager.activeCoordinator {
                SettingsDivider()
                DesktopBoxesManageRows(boxStore: coordinator.store, coordinator: coordinator)
            }
        }

        if enabled {
            if let coordinator = manager.activeCoordinator {
                DesktopFeatureWidgetRows(boxStore: coordinator.store, coordinator: coordinator)
            }
            DesktopHowToCard()
            DesktopSearchSettingsCard()
            DesktopPerformanceSettingsCard()

            let duplicated = ShortcutConflicts.duplicated(store.shortcutBindings)
            SettingsCard(Text("Quick Reveal & Shortcuts")) {
                SettingsRow(Text(verbatim: SettingsLayoutPane.shortcutActionName(.desktopQuickReveal))) {
                    ShortcutActionControls(store: store, action: .desktopQuickReveal, duplicated: duplicated)
                }
                SettingsDivider()
                SettingsRow(Text(verbatim: SettingsLayoutPane.shortcutActionName(.desktopToggleHidden))) {
                    ShortcutActionControls(store: store, action: .desktopToggleHidden, duplicated: duplicated)
                }
                SettingsDivider()
                SettingsToggleRow(Text("Double-Click Blank Desktop to Hide Boxes"), isOn: $doubleClickDesktop)
            }

            SettingsCard(Text("Desktop Layout")) {
                SettingsSliderRow(
                    Text("Snap Gap"),
                    value: snapGap,
                    range: DesktopCanvasConfig.snapGapRange,
                    step: 2,
                    valueText: "\(Int(snapGap)) pt"
                ) { snapGap = $0 }
                SettingsDivider()
                SettingsSliderRow(
                    Text("Edge Margin"),
                    value: edgeMargin,
                    range: DesktopCanvasConfig.edgeMarginRange,
                    step: 2,
                    valueText: "\(Int(edgeMargin)) pt"
                ) { edgeMargin = $0 }
                SettingsDivider()
                SettingsToggleRow(Text("Show on All Spaces"), isOn: $showOnAllSpaces)
            }

            SettingsCard(Text("Desktop Appearance & Panorama")) {
                SettingsPickerRow(Text("Default Box Material"), selection: $materialStyleRaw) {
                    Text("Inherit Dock").tag(DesktopBoxMaterialStyle.inheritDock.rawValue)
                    Text("Frosted Glass").tag(DesktopBoxMaterialStyle.frostedGlass.rawValue)
                    Text("Tinted Glass").tag(DesktopBoxMaterialStyle.tintedGlass.rawValue)
                    Text("Solid Card").tag(DesktopBoxMaterialStyle.solidCard.rawValue)
                    Text("Clear").tag(DesktopBoxMaterialStyle.clearMinimal.rawValue)
                }
                SettingsDivider()
                SettingsToggleRow(Text("Panorama Background"), isOn: $panoramaEnabled)
                SettingsDivider()
                SettingsRow(
                    Text("Panorama Image"),
                    note: panoramaImagePath.isEmpty
                        ? nil
                        : Text(verbatim: URL(fileURLWithPath: panoramaImagePath).lastPathComponent)
                ) {
                    HStack(spacing: SettingsMetrics.controlSpacing) {
                        Button("Choose Image…") { pickPanoramaImage() }
                            .buttonStyle(SettingsGelButtonStyle())
                        if !panoramaImagePath.isEmpty {
                            Button("Clear Image") {
                                panoramaImagePath = ""
                                manager.activeCoordinator?.pruneUnusedDesktopAssets()
                            }
                            .buttonStyle(SettingsGelButtonStyle())
                        }
                    }
                }
                SettingsDivider()
                SettingsSegmentedRow(Text("Scale Mode"), selection: $panoramaScaleModeRaw) {
                    Text("Fill").tag(DesktopPanoramaScaleMode.aspectFill.rawValue)
                    Text("Fit").tag(DesktopPanoramaScaleMode.aspectFit.rawValue)
                }
                SettingsDivider()
                SettingsSliderRow(
                    Text("Opacity"),
                    value: panoramaOpacity,
                    range: 0.1...1.0,
                    step: 0.05,
                    valueText: "\(Int((panoramaOpacity * 100).rounded()))%"
                ) { panoramaOpacity = $0 }
                SettingsDivider()
                SettingsSliderRow(
                    Text("Blur"),
                    value: panoramaBlur,
                    range: 0...24,
                    step: 1,
                    valueText: "\(Int(panoramaBlur.rounded())) pt"
                ) { panoramaBlur = $0 }
                SettingsDivider()
                SettingsButtonRow(Text("Apply to All Boxes")) {
                    manager.activeCoordinator?.applyPanoramaToAllBoxes()
                }
                .disabled(
                    !panoramaEnabled
                        || panoramaImagePath.isEmpty
                        || (manager.activeCoordinator?.store.items.isEmpty ?? true)
                )
            }

            if let coordinator = manager.activeCoordinator {
                DesktopDisplaysSettingsCard(boxStore: coordinator.store, coordinator: coordinator)
            }

            SettingsCard(Text("Capsule Mode")) {
                SettingsPickerRow(Text("New Widget Default"), selection: $defaultCapsuleModeRaw) {
                    Text("Full Window").tag("expanded")
                    Text("Floating Capsule").tag("capsule")
                }
                .help(String(localized: "Sets the initial display mode for newly added widgets."))
                if let coordinator = manager.activeCoordinator, !coordinator.store.items.isEmpty {
                    SettingsDivider()
                    SettingsButtonRow(Text("Collapse All to Capsule")) {
                        coordinator.collapseAllToCapsule()
                    }
                    SettingsDivider()
                    SettingsButtonRow(Text("Expand All to Window")) {
                        coordinator.expandAllFromCapsule()
                    }
                }
            }
        }
    }

    private func pickPanoramaImage() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let imported = try? DesktopAssetStore.importImage(from: url, kind: .panorama)
        else { return }
        panoramaImagePath = imported.path
        panoramaEnabled = true
        manager.activeCoordinator?.pruneUnusedDesktopAssets()
    }
}

private struct DesktopBoxesManageRows: View {
    @ObservedObject var boxStore: DesktopBoxStore
    let coordinator: DesktopCanvasCoordinator

    @State private var hasOrganizeUndo = DesktopAutoOrganizeExecutor.loadLastUndoRecord() != nil
    @State private var migrationError: String?

    var body: some View {
        SettingsRow(
            Text("Folder Boxes"),
            note: boxStore.items.isEmpty
                ? Text("Desktop stays clean until you add a folder box.")
                : nil
        ) {
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: SettingsMetrics.controlSpacing) {
                    Button("Add Folder Box…") { coordinator.presentAddFolderBoxPanel() }
                        .buttonStyle(SettingsGelButtonStyle())
                    Button("Create Starter Box") { coordinator.createStarterInboxBox() }
                        .buttonStyle(SettingsGelButtonStyle())
                        .help(Text(verbatim: "~/KatiKati/Inbox"))
                }
                HStack(spacing: SettingsMetrics.controlSpacing) {
                    Button("Create Managed Box") { coordinator.createManagedBox() }
                        .buttonStyle(SettingsGelButtonStyle())
                    Button("Auto-Organize Folder…") {
                        coordinator.presentAutoOrganizeSheet()
                    }
                    .buttonStyle(SettingsGelButtonStyle())
                    if hasOrganizeUndo {
                        Button("Undo Last Organize") {
                            _ = coordinator.undoLastAutoOrganize()
                            hasOrganizeUndo = DesktopAutoOrganizeExecutor.loadLastUndoRecord() != nil
                        }
                        .buttonStyle(SettingsGelButtonStyle())
                    }
                }
            }
        }
        .onAppear {
            hasOrganizeUndo = DesktopAutoOrganizeExecutor.loadLastUndoRecord() != nil
        }

        if let migrationError {
            SettingsDivider()
            Text(verbatim: migrationError)
                .font(.caption)
                .foregroundStyle(.red)
        }

        ForEach(boxStore.items) { item in
            SettingsDivider()
            SettingsRow(
                Text(verbatim: item.title),
                note: item.backingPath.map { Text(verbatim: ($0 as NSString).abbreviatingWithTildeInPath) }
            ) {
                HStack(spacing: 6) {
                    if item.isManagedFolder {
                        Text("Managed")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.quaternary))

                        Button {
                            migrationError = coordinator.exportManagedBox(id: item.id)
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderless)
                        .help(Text("Export to Folder…"))
                        .accessibilityLabel(Text("Export to Folder…"))
                    } else {
                        Button {
                            migrationError = coordinator.convertToManagedBox(id: item.id)
                        } label: {
                            Image(systemName: "internaldrive")
                        }
                        .buttonStyle(.borderless)
                        .help(Text("Convert to Managed Storage"))
                        .accessibilityLabel(Text("Convert to Managed Storage"))
                    }

                    Button {
                        coordinator.setCapsuleMode(
                            item.capsuleMode == .expanded ? .capsule : .expanded,
                            for: item.id
                        )
                    } label: {
                        Image(systemName: item.capsuleMode == .expanded ? "pip.enter" : "pip.exit")
                    }
                    .buttonStyle(.borderless)
                    .help(item.capsuleMode == .expanded ? Text("Collapse to Capsule") : Text("Expand to Window"))
                    .accessibilityLabel(item.capsuleMode == .expanded ? Text("Collapse to Capsule") : Text("Expand to Window"))

                    Button {
                        coordinator.toggleWidgetHidden(id: item.id)
                    } label: {
                        Image(systemName: item.isHidden ? "eye" : "eye.slash")
                    }
                    .buttonStyle(.borderless)
                    .help(item.isHidden ? Text("Show Box") : Text("Hide Box"))
                    .accessibilityLabel(item.isHidden ? Text("Show Box") : Text("Hide Box"))

                    Button {
                        coordinator.revealWidgetInFinder(id: item.id)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help(Text("Show in Finder"))
                    .accessibilityLabel(Text("Show in Finder"))

                    Button(role: .destructive) {
                        coordinator.removeWidget(id: item.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help(Text("Remove Box"))
                    .accessibilityLabel(Text("Remove Box"))
                }
            }
        }
    }
}

/// One on/off toggle per one-instance feature widget; off hides the box, on adds or unhides it.
private struct DesktopFeatureWidgetRows: View {
    @ObservedObject var boxStore: DesktopBoxStore
    let coordinator: DesktopCanvasCoordinator

    private struct Feature { let kind: DesktopWidgetKind; let title: String; let hint: String }

    private var features: [Feature] {
        [
            Feature(kind: .todo, title: String(localized: "To-Do"), hint: String(localized: "To-Do: type a task and press Return, click the circle to finish it and the star to mark it important.")),
            Feature(kind: .quickCapture, title: String(localized: "Quick Capture"), hint: String(localized: "Quick Capture: jot quick notes, or grab text from anywhere on screen with the capture button (OCR).")),
            Feature(kind: .glance, title: String(localized: "Glance"), hint: String(localized: "Glance: today's date with the lunar date, solar term and festivals.")),
            Feature(kind: .weather, title: String(localized: "Weather"), hint: String(localized: "Weather: live conditions, temperature and today's high and low.")),
            Feature(kind: .music, title: String(localized: "Vinyl Music"), hint: String(localized: "Vinyl Music: a spinning record for what is playing, with play, pause and skip.")),
            Feature(kind: .search, title: String(localized: "Search"), hint: String(localized: "Search: one pill for Spotlight files, apps, Settings pages, notes and to-dos, with ⌘/⇧ multi-select and batch actions."))
        ]
    }

    private func isOn(_ kind: DesktopWidgetKind) -> Bool {
        boxStore.items.contains { $0.kind == kind && !$0.isHidden }
    }

    var body: some View {
        SettingsCard(Text("Desktop Widgets")) {
            ForEach(Array(features.enumerated()), id: \.element.kind) { index, feature in
                if index > 0 { SettingsDivider() }
                SettingsToggleRow(
                    Text(verbatim: feature.title),
                    isOn: Binding(
                        get: { isOn(feature.kind) },
                        set: { on in
                            if on {
                                coordinator.addFeatureBox(kind: feature.kind)
                            } else if let item = boxStore.items.first(where: { $0.kind == feature.kind && !$0.isHidden }) {
                                coordinator.toggleWidgetHidden(id: item.id)
                            }
                        }
                    ),
                    info: feature.hint
                )
            }
        }
    }
}

/// Unified desktop search options (Phase 66A–B): result cap and Spotlight exclusion paths.
private struct DesktopSearchSettingsCard: View {
    @AppStorage(DesktopSearchConfig.resultLimitKey)
    private var resultLimit = DesktopSearchConfig.defaultResultLimit
    @AppStorage(DesktopSearchConfig.excludedPathsKey) private var excludedPaths = ""

    var body: some View {
        SettingsCard(Text("Desktop Search")) {
            SettingsStepperRow(
                Text("Result Limit"),
                value: Binding(
                    get: { Double(resultLimit) },
                    set: { resultLimit = DesktopSearchConfig.clampedResultLimit(Int($0)) }
                ),
                in: Double(DesktopSearchConfig.resultLimitRange.lowerBound)...Double(DesktopSearchConfig.resultLimitRange.upperBound),
                step: 10,
                readout: "\(resultLimit)"
            )
            SettingsDivider()
            SettingsEditorRow(
                Text("Excluded Paths"),
                text: $excludedPaths,
                placeholder: Text(verbatim: "~/Library/Caches\n~/Projects/archive"),
                height: 70
            )
            SettingsDivider()
            SettingsButtonRow(Text("Open Search")) {
                DesktopSearchPanelController.shared.present()
            }
        }
    }
}

/// Plain-language usage notes for everything on the Desktop page.
private struct DesktopHowToCard: View {
    var body: some View {
        SettingsCard(Text("How to Use")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Folder boxes: drop files in, drag to reorder, double-click the title to rename, press Space for Quick Look.")
                Text("Capsule mode: collapse any box to a pill from its ellipsis menu; hover to peek, or dock it to a screen edge.")
                Text("Quick Reveal: press the shortcut below to bring every box to the front, Esc to dismiss.")
                Text("Drag a box by its title bar; hold Control to move them all, Option-drag one onto another to group them as tabs.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
