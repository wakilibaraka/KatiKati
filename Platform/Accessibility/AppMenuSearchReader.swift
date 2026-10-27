import ApplicationServices
import Foundation

/// Port plan #3: walks another app's whole menu bar into `MenuSearchEntry` values for the command bar's
/// `m ` mode. `AppMenuBarReader` (57f) reads only the first level for a chip's menu; this one descends
/// into submenus, bounded by `MenuSearch.maxDepth` / `maxItems`.
///
/// Entries carry title paths, not AX elements: activation walks the path again in the same app and
/// presses what it finds there now, so a menu that changed since the snapshot presses nothing rather
/// than the wrong item.
enum AppMenuSearchReader {
    /// One cold walk. Call it off the main thread: a large app takes a few hundred milliseconds. A slow
    /// app answers each element within the 0.35 s messaging timeout, and the whole walk stops at
    /// `budget`, returning what it has read so far.
    static func entries(pid: pid_t, budget: TimeInterval = 1.5) -> [MenuSearchEntry] {
        guard AXIsProcessTrusted(), let bar = menuBar(pid: pid) else { return [] }
        let deadline = Date().addingTimeInterval(budget)
        var out: [MenuSearchEntry] = []
        for barItem in children(bar) {
            guard let title = text(barItem, kAXTitleAttribute), !title.isEmpty,
                  let menu = children(barItem).first else { continue }
            walk(menu, path: [title], depth: 1, deadline: deadline, into: &out)
            if out.count >= MenuSearch.maxItems || Date() >= deadline { break }
        }
        return out
    }

    /// Re-resolves `path` in the app's menu bar as it is now and presses it. False when the item is gone
    /// or disabled, so the caller can say so instead of guessing.
    @discardableResult
    static func press(path: [String], pid: pid_t) -> Bool {
        guard AXIsProcessTrusted(), !path.isEmpty, let bar = menuBar(pid: pid) else { return false }
        var container = bar
        for (index, title) in path.enumerated() {
            guard let item = children(container).first(where: { text($0, kAXTitleAttribute) == title }) else { return false }
            if index == path.count - 1 {
                guard flag(item, kAXEnabledAttribute) ?? true else { return false }
                return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
            }
            guard let submenu = children(item).first else { return false }
            container = submenu
        }
        return false
    }

    private static func menuBar(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        _ = AXUIElementSetMessagingTimeout(app, 0.35)
        guard let raw = value(app, kAXMenuBarAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(raw, to: AXUIElement.self)
    }

    /// Items with a submenu are containers: their children are listed, the container itself is not
    /// (pressing it only opens the submenu).
    private static func walk(_ menu: AXUIElement, path: [String], depth: Int, deadline: Date,
                             into out: inout [MenuSearchEntry]) {
        for item in children(menu) {
            if out.count >= MenuSearch.maxItems || Date() >= deadline { return }
            guard let title = text(item, kAXTitleAttribute), !title.isEmpty else { continue }
            let itemPath = path + [title]
            if let submenu = children(item).first {
                if depth < MenuSearch.maxDepth { walk(submenu, path: itemPath, depth: depth + 1, deadline: deadline, into: &out) }
                continue
            }
            out.append(MenuSearchEntry(path: itemPath,
                                       commandKey: text(item, kAXMenuItemCmdCharAttribute)?.lowercased(),
                                       modifiers: number(item, kAXMenuItemCmdModifiersAttribute) ?? 0,
                                       isEnabled: flag(item, kAXEnabledAttribute) ?? true))
        }
    }

    // MARK: - AX plumbing (same shape as AppMenuBarReader's)

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        (value(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    private static func text(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    private static func number(_ element: AXUIElement, _ attribute: String) -> Int? {
        (value(element, attribute) as? NSNumber)?.intValue
    }

    private static func flag(_ element: AXUIElement, _ attribute: String) -> Bool? {
        value(element, attribute) as? Bool
    }
}
