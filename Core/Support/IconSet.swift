import Foundation

/// Chip and menu-bar artwork set (`com.katikati.iconSet`, Phase 6 Appearance tab).
///
/// `modern` (default) = the colourful 3D trash art + the drawn menu-bar mark;
/// `classic` = the familiar system SF Symbols. Independent of the theme preset:
/// switching one never touches the other key.
enum IconSet: String, CaseIterable, Sendable {
    case modern
    case classic

    static let `default`: IconSet = .modern

    /// Missing or unknown stored value → `modern`.
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
