import Foundation

/// 54a — what a click on a chip means. A plain click keeps the long-standing behaviour (activate, or
/// minimise a window that is already in front); the modifiers are the addition: ⌥ hides the app,
/// ⌘ minimises the window. Both together fall back to the plain click rather than guessing.
enum DockClickPolicy {
    enum Action: Equatable, Sendable {
        case toggle
        case hide
        case minimize
    }

    static func action(optionDown: Bool, commandDown: Bool) -> Action {
        if optionDown == commandDown { return .toggle }
        return optionDown ? .hide : .minimize
    }
}
