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
        // Ignored windows are never owned, so the ownership filter above would drop their cards and
        // an app the user told KatiKati to leave alone would vanish from the bar.
        visible.formUnion(ignoredWorkspaceWindows)

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
        // Only windows this session still has a live record for. The store is durable, so a closed
        // window's id survives in it; a tree built from those ids tiled the live windows into the
        // gaps the dead ones left until the next snapshot pruned them.
        for id in workspaceStore.windows(in: workspace, on: displayKey)
        where lastWindows[id]?.cgWindowID != nil {
            tree.insert(id)
        }
        return tree
    }

    /// Gives every new window an owner, then parks everything that is not on its display's active
    /// workspace. Runs before the tiling pass so the pass only ever sees one workspace's windows.
    func reconcileWorkspaceOwnership(with snapshot: DockSnapshot, screens: [NSScreen], primaryMaxY: CGFloat) {
        // Rebuild the ignore set from this snapshot rather than only adding to it: a rule changed
        // from `ignore` to `tile` has to take effect on the next pass, and a closed window must not
        // keep its entry for the rest of the session.
        ignoredWorkspaceWindows.removeAll()
        for record in snapshot.windows.values where
            workspaceRules.disposition(bundleID: record.bundleIdentifier, title: record.title) == .ignore {
            ignoredWorkspaceWindows.insert(record.id)
        }

        var changed = false
        for id in snapshot.orderedWindowIDs {
            guard let record = snapshot.windows[id] else { continue }
            let key = screenKey(for: resolveScreen(for: record, screens: screens, primaryMaxY: primaryMaxY))
            let active = activeWorkspace(on: key)
            let disposition = workspaceRules.disposition(bundleID: record.bundleIdentifier, title: record.title)
            // A window that moved displays belongs to the screen it is on now. Ownership is keyed by
            // display, so a window adopted on the built-in stayed in that display's list after being
            // dragged to the second screen: the second screen's switches then had nothing to park,
            // while the first kept counting (and retiling) a window that was no longer there. It joins
            // the entering display's active workspace rather than dragging a token onto a screen that
            // is not showing it, so moving a window never hides it in a parked workspace (found live
            // 2026-11-27 with four windows tiled on the 4K: ⌃⌥2 parked only the one window that had
            // been adopted there).
            if disposition != .ignore, let adoptedOn = workspaceStore.displayKey(of: id), adoptedOn != key {
                detachWindow(id, fromDisplay: adoptedOn)
                workspaceStore.assign(id, to: active, on: key)
                changed = true
                continue
            }

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

    /// Forgets a window on one display: the live tree and every saved workspace tree for that display.
    /// The ownership record itself is the caller's to rewrite.
    func detachWindow(_ id: WindowID, fromDisplay key: String) {
        if var tree = trees[key] {
            tree.remove(id)
            trees[key] = tree
        }
        for workspace in Array(workspaceTrees.keys) {
            guard var perDisplay = workspaceTrees[workspace], var tree = perDisplay[key] else { continue }
            tree.remove(id)
            perDisplay[key] = tree
            workspaceTrees[workspace] = perDisplay
        }
    }

    /// The tiling pass asks this before admitting a window: ignored and untiled windows are never
    /// tiled, and a window owned by another workspace is never tiled on this one.
    /// A `=tile` rule outranks the built-in float list: the rule promises the window is kept tiled
    /// even where the floating defaults would leave it alone.
    func workspaceRulesForceTile(_ record: WindowRecord) -> Bool {
        guard workspacesEnabled else { return false }
        return workspaceRules.tileOverride(bundleID: record.bundleIdentifier, title: record.title)
    }

    func workspaceAllowsTiling(_ record: WindowRecord, on displayKey: String) -> Bool {
        guard workspacesEnabled else { return true }
        if ignoredWorkspaceWindows.contains(record.id) { return false }
        let disposition = workspaceRules.disposition(bundleID: record.bundleIdentifier, title: record.title)
        if disposition == .float || disposition == .pin { return false }
        let active = activeWorkspace(on: displayKey)
        return (workspaceStore.workspace(of: record.id) ?? active) == active
    }
}
