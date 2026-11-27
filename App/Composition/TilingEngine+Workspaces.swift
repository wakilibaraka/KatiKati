import AppKit
import Foundation

/// W-4a: workspace ownership, and what the bar is allowed to see.
///
/// `trees` stays the active workspace's tree, so this file is the only place that has to know a
/// display can hold more than one layout. Nothing here changes an existing call site.
extension TilingEngine {

    /// The snapshot the bar draws: only the active workspace's windows when filtering is on (G-W2).
    /// Filtered by window id, never by bundle id, so an app with a window on each workspace keeps
    /// exactly the card it should. Returns the snapshot untouched when workspaces are off, so the
    /// bar's behaviour before this layer existed is preserved exactly.
    func barSnapshot(from snapshot: DockSnapshot) -> DockSnapshot {
        guard workspacesEnabled, showsOnlyActiveWorkspace else { return snapshot }
        var visible = Set<WindowID>()
        for screen in NSScreen.screens {
            let key = screenKey(for: screen)
            visible.formUnion(workspaceStore.windows(in: activeWorkspace(on: key), on: key))
        }
        // Pinned windows are on every workspace by definition.
        for id in snapshot.windows.keys where isPinned(id) { visible.insert(id) }

        let windows = snapshot.windows.filter { visible.contains($0.key) }
        return DockSnapshot(
            windows: windows,
            orderedWindowIDs: snapshot.orderedWindowIDs.filter { visible.contains($0) }
        )
    }

    func workspaceTree(for workspace: WorkspaceID, on displayKey: String) -> TilingTree {
        // The workspace on screen is the live `trees` entry. `workspaceTrees` only holds the ones
        // that are away, and a switch writes it before the entered workspace's first reconcile, so
        // reading it here reported zero windows for a workspace that was visibly tiled (found live
        // 2026-11-27: `status` said windows=0 over a four-pane layout).
        if workspace == activeWorkspace(on: displayKey), let live = trees[displayKey] { return live }
        return tree(for: workspace, on: displayKey)
    }

    func tree(for workspace: WorkspaceID, on displayKey: String) -> TilingTree {
        if let saved = workspaceTrees[workspace]?[displayKey] { return saved }
        var tree = TilingTree()
        for id in workspaceStore.windows(in: workspace, on: displayKey) { tree.insert(id) }
        return tree
    }

    /// Gives every new window an owner, then parks everything that is not on its display's active
    /// workspace. Runs before the tiling pass so the pass only ever sees one workspace's windows.
    func reconcileWorkspaceOwnership(with snapshot: DockSnapshot, screens: [NSScreen], primaryMaxY: CGFloat) {
        var changed = false
        for id in snapshot.orderedWindowIDs {
            guard let record = snapshot.windows[id] else { continue }
            let key = screenKey(for: resolveScreen(for: record, screens: screens, primaryMaxY: primaryMaxY))
            let active = activeWorkspace(on: key)
            let disposition = workspaceRules.disposition(bundleID: record.bundleIdentifier, title: record.title)
            if disposition == .ignore { ignoredWorkspaceWindows.insert(id) }
            guard workspaceStore.workspace(of: id) == nil else { continue }

            switch disposition {
            case .route(let workspace):
                let bundle = record.bundleIdentifier
                let alreadyRouted = bundle.map { routedBundleIDs.contains($0) } ?? false
                if workspaceRules.routesAllWindows(bundleID: bundle, title: record.title) || !alreadyRouted {
                    enableWorkspace(workspace)
                    workspaceStore.assign(id, to: workspace, on: key)
                    if let bundle { routedBundleIDs.insert(bundle) }
                } else {
                    workspaceStore.assign(id, to: active, on: key)
                }
            case .manage, .float, .pin:
                workspaceStore.assign(id, to: active, on: key)
            case .ignore:
                break
            }
            changed = true
        }
        if changed { persistWorkspaceStore() }

        guard !snapshot.windows.isEmpty else { return }
        for screen in screens {
            let key = screenKey(for: screen)
            let active = activeWorkspace(on: key)
            for id in workspaceStore.windowsOutside(active, on: key) {
                guard !isPinned(id), !ignoredWorkspaceWindows.contains(id) else { continue }
                parkWorkspaceWindow(id, on: screen)
            }
        }
    }

    /// The tiling pass asks this before admitting a window: ignored and untiled windows are never
    /// tiled, and a window owned by another workspace is never tiled on this one.
    func workspaceAllowsTiling(_ record: WindowRecord, on displayKey: String) -> Bool {
        guard workspacesEnabled else { return true }
        if ignoredWorkspaceWindows.contains(record.id) { return false }
        let disposition = workspaceRules.disposition(bundleID: record.bundleIdentifier, title: record.title)
        if disposition == .float || disposition == .pin { return false }
        let active = activeWorkspace(on: displayKey)
        return (workspaceStore.workspace(of: record.id) ?? active) == active
    }
}
