import SwiftUI

/// Desktop Folder Boxes configuration block mounted under Settings › Widgets.
struct DesktopSettingsBlock: View {
    @ObservedObject var store: AppSettingsStore
    @ObservedObject private var manager = DesktopCanvasManager.shared

    @AppStorage(DesktopCanvasConfig.enabledKey) private var enabled = false
    @AppStorage(DesktopCanvasConfig.snapGapKey) private var snapGap = DesktopCanvasConfig.defaultSnapGap
    @AppStorage(DesktopCanvasConfig.edgeMarginKey) private var edgeMargin = DesktopCanvasConfig.defaultEdgeMargin
    @AppStorage(DesktopCanvasConfig.doubleClickDesktopKey) private var doubleClickDesktop = false
    @AppStorage(DesktopCanvasConfig.showOnAllSpacesKey) private var showOnAllSpaces = true

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
        }
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
