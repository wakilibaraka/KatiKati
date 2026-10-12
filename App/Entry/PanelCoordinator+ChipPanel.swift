import AppKit
import SwiftUI

// PanelCoordinator · Phase 9 floating chip panel: wiring + the content builder for the hover
// preview (9c) and the right-click jump list (9b).
extension PanelCoordinator {
    var chipPanel: ChipPanelController {
        if let existing = chipPanelStorage { return existing }
        let controller = ChipPanelController()
        controller.makePanel = { [weak self] in
            guard let self else { return NSPanel() }
            let panel = self.makeFloatingPanel(contentRect: .zero, usesLiquidGlass: self.usesLiquidGlass)
            self.configurePanel(panel, backgroundColor: .clear, appliesLevelOverride: false)
            return panel
        }
        controller.contentFor = { [weak self] id in self?.chipPanelContent(forChipID: id) }
        controller.screenFrameContaining = { point in
            (NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main)?.visibleFrame ?? .zero
        }
        controller.previewEnabled = { [weak self] in self?.settingsStore.chipPreviewEnabled ?? false }
        controller.openDelay = { [weak self] in TimeInterval(self?.settingsStore.chipPreviewDelayMs ?? 350) / 1000 }
        controller.thumbnailWidth = { [weak self] in CGFloat(self?.settingsStore.chipPreviewThumbWidth ?? 180) }
        controller.usesLiquidGlass = { [weak self] in self?.usesLiquidGlass ?? false }
        controller.themeStyle = { [weak self] in self?.settingsStore.themeMaterial ?? .system }
        controller.onWillOpen = { [weak self] in
            guard let self else { return }
            self.onAccessoryWillOpen?(self, .tooltip)
            self.dismissWindowTitleTooltip()
        }
        controller.onPanelShown = { [weak self] panel in self?.pinOverlappingPanelIfNeeded(panel) }
        controller.runActivate = { [weak self] id in self?.runtime.activate(windowID: id) }
        controller.runCloseWindow = { [weak self] id in self?.runtime.close(windowID: id) }
        controller.runOpenRecent = { recent in
            if let bid = recent.bundleID {
                let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid)
                DocumentUsageStore.shared.recordOpen(bundleID: bid, path: recent.url.path)
                AppMenuBuilder.openRecent(recent.url, appURL: appURL)
            } else {
                NSWorkspace.shared.open(recent.url)
            }
        }
        controller.wire()
        chipPanelStorage = controller
        return controller
    }

    /// Strip → panel: the window chip under the pointer (nil = none). Called regardless of the
    /// title-bubble style, so previews work in the default quiet mode too.
    func handleChipHover(_ request: ChipHoverRequest?) {
        NSLog("CHIPDBG hover %@ enabled=%d", request?.chipID ?? "nil", settingsStore.chipPreviewEnabled ? 1 : 0)
        guard settingsStore.chipPreviewEnabled || chipPanelStorage != nil else { return }
        chipPanel.hoverChanged(chipID: request?.chipID, anchor: request?.anchorVisibleRect ?? .zero)
    }

    func handleChipJumpList(chipID: String, anchor: CGRect) {
        chipPanel.openMenu(chipID: chipID, anchor: anchor)
    }

    /// The tooltip bubble steps aside while the chip panel is up.
    var chipPanelIsShowing: Bool { chipPanelStorage?.isVisible == true }

    func chipPanelContent(forChipID chipID: String) -> ChipPanelContent? {
        let snapshot = runtime.snapshot
        let items = StripItem.items(from: snapshot, grouping: settingsStore.chipGroupingPlan)
        NSLog("CHIPDBG content %@ found=%d", chipID, items.contains { $0.id == chipID } ? 1 : 0)
        guard let item = items.first(where: { $0.id == chipID }),
              !item.isAppLevelFallback, let bid = item.bundleIdentifier else { return nil }
        let appName = AppDisplayNameResolver.displayName(for: bid)

        func panelWindow(_ entry: WindowMenuEntry) -> ChipPanelWindow {
            ChipPanelWindow(
                id: entry.actionWindowID,
                cgWindowID: snapshot.windows[WindowID(rawValue: entry.actionWindowID)]?.cgWindowID,
                title: entry.title, marker: entry.marker)
        }
        let all = WindowListMenuPlan.entries(snapshot: snapshot, bundleID: bid, fallbackTitle: appName).map(panelWindow)
        let own: [ChipPanelWindow]
        if item.isAppGroup {
            own = all
        } else if let match = all.first(where: { $0.id == item.actionWindowID }) {
            own = [match]
        } else {
            let marker: WindowMenuEntry.Marker = item.status == WindowStatus.active.rawValue ? .front
                : (item.status == WindowStatus.minimized.rawValue ? .minimized : .none)
            own = [ChipPanelWindow(id: item.actionWindowID, cgWindowID: item.cgWindowID,
                                   title: WindowDisplayTitle.resolve(rawTitle: item.title, fallbackName: appName),
                                   marker: marker)]
        }

        let recentPaths = RecentDocumentsReader.recentDocuments(for: bid, maxCount: 20).map(\.path)
        let ranked = DocumentUsageStore.shared.ranked(bundleID: bid, recentPaths: recentPaths)
        let recents = ranked.prefix(ChipPanelModel.maxRecents).map {
            ChipPanelRecent(url: URL(fileURLWithPath: $0), bundleID: bid)
        }

        return ChipPanelContent(
            chipID: chipID, bundleID: bid, appName: appName,
            icon: AppIconResolver.icon(for: bid),
            ownWindows: own, allWindows: all.isEmpty ? own : all,
            recents: recents,
            actions: chipPanelActions(for: item, bundleID: bid))
    }

    private func chipPanelActions(for item: StripItem, bundleID bid: String) -> [ChipPanelAction] {
        let runtime = self.runtime
        let wid = item.actionWindowID
        var actions: [ChipPanelAction] = []
        actions.append(ChipPanelAction(id: "new", title: String(localized: "New Window")) { _ in
            runtime.newWindow(windowID: wid)
        })
        if item.status == WindowStatus.minimized.rawValue {
            actions.append(ChipPanelAction(id: "restore", title: String(localized: "Restore")) { _ in
                runtime.activate(windowID: wid)
            })
        } else {
            actions.append(ChipPanelAction(id: "minimize", title: String(localized: "Minimize")) { _ in
                runtime.minimize(windowID: wid)
            })
        }
        if item.status == WindowStatus.hidden.rawValue {
            actions.append(ChipPanelAction(id: "show", title: String(localized: "Show")) { _ in
                runtime.activate(windowID: wid)
            })
        } else {
            actions.append(ChipPanelAction(id: "hide", title: String(localized: "Hide App")) { _ in
                runtime.hide(windowID: wid)
            })
        }
        let membership = LauncherMembershipItem.items(
            surface: .strip, bundleID: bid,
            isKept: keptAppStore.contains(bid), isMessaging: messagingStore.contains(bid),
            controller: appMembershipController)
        for (index, descriptor) in membership.enumerated() {
            actions.append(ChipPanelAction(
                id: "member-\(index)", title: descriptor.label, isChecked: descriptor.isChecked,
                separatorBefore: index == 0) { _ in descriptor.action() })
        }
        let members = item.isAppGroup ? [wid] : item.memberWindowIDs
        actions.append(ChipPanelAction(id: "close", title: String(localized: "Close Window"), separatorBefore: true) { _ in
            for id in members { runtime.close(windowID: id) }
        })
        let isSelf = bid == Bundle.main.bundleIdentifier
        actions.append(ChipPanelAction(
            id: "quit", title: String(localized: "Quit App"),
            optionTitle: isSelf ? nil : String(localized: "Force Quit"), isDestructive: true) { option in
            if option, !isSelf {
                NSRunningApplication.runningApplications(withBundleIdentifier: bid).first?.forceTerminate()
            } else {
                runtime.quit(windowID: wid)
            }
        })
        return actions
    }
}
