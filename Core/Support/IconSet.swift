import Foundation

/// Chip and menu-bar artwork set (`com.katikati.iconSet`, Phase 6 Appearance tab).
///
/// `system` uses macOS Trash artwork; `modern` and `classic` retain the existing presets.
/// Independent of the theme preset: switching one never touches the other key.
enum IconSet: String, CaseIterable, Sendable {
    case system
    case modern
    case classic

    static let `default`: IconSet = .system

    /// Missing or unknown stored value → `system`.
    init(storedValue: String?) {
        self = storedValue.flatMap(IconSet.init(rawValue:)) ?? .default
    }

    /// SF Symbol for the trash chip in `classic`.
    static func classicTrashSymbol(isFull: Bool) -> String {
        isFull ? "trash.fill" : "trash"
    }

    /// SF Symbol for the menu-bar item in `classic`.
    static let classicMenuBarSymbol = "rectangle.split.3x1"
}
