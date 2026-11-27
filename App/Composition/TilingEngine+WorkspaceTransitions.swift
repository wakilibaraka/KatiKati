import AppKit
import Foundation

/// W-4b: switching workspaces, and moving a window between them.
///
/// The invariant every function here keeps: a display has one live `trees[key]`, everything else on
/// that display is parked off screen with its recovery frame already written to disk.
extension TilingEngine {

    /// Switches one display to `target`: park what it was showing, reveal what `target` holds.
    func switchWorkspace(_ target: WorkspaceID, on screen: NSScreen? = nil) {
        guard workspacesEnabled, isEnabled else { return }
        guard let screen = screen ?? activeScreen() ?? NSScreen.screens.first else { return }
        let key = screenKey(for: screen)
        let current = activeWorkspace(on: key)
        guard current != target else { return }

        enableWorkspace(target)
        if let focused = trees[key]?.focusedID {
            workspaceStore.setFocus(focused, in: current, on: key)
        }
        workspaceTrees[current, default: [:]][key] = trees[key] ?? tree(for: current, on: key)

        parkWorkspaceWindows(workspaceStore.windows(in: current, on: key), on: screen)
        // Put the entering workspace back on screen before anything forgets where it was. It has to come
        // before the retile: a parked window's snapshot record can still hold the frame it had before it
        // was parked, so the retile believes that window is already in place and skips the write. Doing
        // this after the retile left four parked windows off screen with no record left to restore them,
        // and not doing it at all stranded 13 floated windows the same way (found live 2026-11-27).
        revealParkedWorkspaceWindows(in: target, on: key, screen: screen)

        trees[key] = tree(for: target, on: key)
        setActiveWorkspace(target, on: key)
        persistWorkspaceStore()
        reapplyLayout()
        WorkspaceHUDController.shared.show(
            workspaces: workspaceRegistry.workspaces(on: key),
            active: target,
            on: screen
        )

        if let focus = workspaceStore.focusTarget(in: target, on: key) { focusWindow(focus) }
    }

    /// Steps to the next/previous workspace on the focused display, stopping at either end.
    func stepWorkspace(_ offset: Int) {
        guard workspacesEnabled, let screen = activeScreen() ?? NSScreen.screens.first else { return }
        let key = screenKey(for: screen)
        guard let next = workspaceRegistry.step(from: activeWorkspace(on: key), by: offset, on: key) else { return }
        switchWorkspace(next, on: screen)
    }

    /// Sends the focused window to another workspace without following it (⌃⌥⇧1–0).
    ///
    /// The window's own display decides here, not the pointer: a move parks the window on the screen it
    /// is on, and parking on any other screen is refused by `parkWorkspaceWindow`'s display guard.
    func moveFocusedToWorkspace(_ target: WorkspaceID) {
        guard workspacesEnabled, isEnabled,
              let screen = focusedWindowScreen() ?? activeScreen() ?? NSScreen.screens.first else { return }
        let key = screenKey(for: screen)
        guard let id = trees[key]?.focusedID
            ?? lastSnapshot?.windows.values.first(where: { $0.status == .active })?.id else { return }
        moveWindow(id, to: target, on: screen, follow: false)
    }

    func moveFocusedWorkspace(_ offset: Int) {
        guard workspacesEnabled,
              let screen = focusedWindowScreen() ?? activeScreen() ?? NSScreen.screens.first else { return }
        let key = screenKey(for: screen)
        guard let next = workspaceRegistry.step(from: activeWorkspace(on: key), by: offset, on: key) else { return }
        moveFocusedToWorkspace(next)
    }

    func moveWindow(_ id: WindowID, to target: WorkspaceID, on screen: NSScreen, follow: Bool) {
        let key = screenKey(for: screen)
        let from = workspaceStore.workspace(of: id) ?? activeWorkspace(on: key)
        guard from != target else { return }

        enableWorkspace(target)
        workspaceStore.move(id, to: target, on: key)
        routedBundleIDs.insert(lastWindows[id]?.bundleIdentifier ?? "")

        if var tree = trees[key] {
            tree.remove(id)
            trees[key] = tree
        }
        var targetTree = workspaceTrees[target]?[key] ?? tree(for: target, on: key)
        targetTree.insert(id)
        workspaceTrees[target, default: [:]][key] = targetTree

        if follow {
            switchWorkspace(target, on: screen)
        } else {
            parkWorkspaceWindows([id], on: screen)
            persistWorkspaceStore()
            reapplyLayout()
        }
    }

    /// Raises the workspace's remembered window when a switch lands.
    func focusWindow(_ id: WindowID) {
        guard let record = lastWindows[id], let cg = record.cgWindowID, cg != 0 else { return }
        guard let element = AXElementCache.shared.element(pid: record.pid, cgWindowID: cg)
                ?? axElement(for: record.pid, cgWindowID: cg) else { return }
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        NSRunningApplication(processIdentifier: record.pid)?.activate(options: .activateIgnoringOtherApps)
    }
}
