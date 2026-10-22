import ApplicationServices
import Foundation

/// Reads another app's own "new window / new tab" rows out of its menu bar, so a dock chip's right-click
/// menu can offer what the macOS Dock offers for that app — in the app's own words, with the app's own
/// shortcuts. Accessibility is the only source: macOS does not let one app read another's Dock menu.
///
/// This runs on the right-click path, once per menu, so it is bounded: a 0.35 s messaging timeout means
/// a busy app delays the menu, and an app that never answers simply gets no rows.
enum AppMenuBarReader {
    struct Row {
        let title: String
        let element: AXUIElement
    }

    static func rows(pid: pid_t) -> [Row] {
        guard AXIsProcessTrusted() else { return [] }
        let app = AXUIElementCreateApplication(pid)
        _ = AXUIElementSetMessagingTimeout(app, 0.35)
        guard let raw = value(app, kAXMenuBarAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return [] }
        let bar = unsafeBitCast(raw, to: AXUIElement.self)
        var found: [(AppNewMenuPlan.Entry, AXUIElement)] = []
        for barItem in children(bar) {
            guard let menu = children(barItem).first else { continue }
            for item in children(menu) {
                guard let title = text(item, kAXTitleAttribute), !title.isEmpty else { continue }
                found.append((AppNewMenuPlan.Entry(title: title,
                                                   commandKey: text(item, kAXMenuItemCmdCharAttribute)?.lowercased(),
                                                   modifiers: number(item, kAXMenuItemCmdModifiersAttribute) ?? 0,
                                                   isEnabled: flag(item, kAXEnabledAttribute) ?? true),
                              item))
            }
            if AppNewMenuPlan.items(from: found.map(\.0)).count >= AppNewMenuPlan.limit { break }
        }
        return AppNewMenuPlan.items(from: found.map(\.0)).compactMap { chosen in
            found.first { $0.0 == chosen }.map { Row(title: chosen.title, element: $0.1) }
        }
    }

    /// Runs the app's own menu item — no synthetic keys, so nothing is typed into the wrong window if
    /// focus moved between the read and the click.
    static func press(_ row: Row) {
        AXUIElementPerformAction(row.element, kAXPressAction as CFString)
    }

    // MARK: - AX plumbing

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
