import Foundation
import CoreGraphics

/// Trigger activation mode for the radial dial.
enum RadialTriggerMode: String, CaseIterable, Codable, Sendable {
    /// Tap shortcut or mouse combo to toggle open; click a wedge or press Esc/outside to close.
    case tapToggle
    /// Hold shortcut/mouse button down, flick towards sector, and release to execute.
    case holdRelease
    /// Hold a modifier shortcut key, hover a slice, and release the key to execute.
    case hotkeyHold

    var title: String {
        switch self {
        case .tapToggle: return "Tap / Click to Toggle"
        case .holdRelease: return "Hold & Release"
        case .hotkeyHold: return "Hotkey Hold & Release"
        }
    }
}

/// Mouse button and modifier combo presets that can summon the radial dial.
enum RadialMouseTrigger: String, CaseIterable, Codable, Sendable {
    case off
    /// Middle mouse button (button 3 / scroll wheel click).
    case middleClick
    /// Control + Right Click.
    case controlRightClick
    /// Option + Right Click.
    case optionRightClick
    /// Command + Right Click.
    case commandRightClick
    /// Shift + Right Click.
    case shiftRightClick
    /// Option + Middle Click.
    case optionMiddleClick
    /// Extra mouse button 4 (Back).
    case button4
    /// Extra mouse button 5 (Forward).
    case button5

    var title: String {
        switch self {
        case .off: return "Off"
        case .middleClick: return "Middle Click"
        case .controlRightClick: return "Control + Right Click"
        case .optionRightClick: return "Option + Right Click"
        case .commandRightClick: return "Command + Right Click"
        case .shiftRightClick: return "Shift + Right Click"
        case .optionMiddleClick: return "Option + Middle Click"
        case .button4: return "Mouse Button 4"
        case .button5: return "Mouse Button 5"
        }
    }
}

/// Visual theme presets for the radial dial.
enum RadialDialTheme: String, CaseIterable, Codable, Sendable {
    /// Vibrant purple/lilac tinted frosted glass (Blossom reference).
    case lilacGlass
    /// Deep dark obsidian glass with hairline dividers.
    case darkObsidian
    /// Adaptive translucent macOS frosted blur.
    case systemFrosted
    /// High-contrast neon cyan & magenta edge glow.
    case neonCyber

    var title: String {
        switch self {
        case .lilacGlass: return "Lilac Glass"
        case .darkObsidian: return "Dark Obsidian"
        case .systemFrosted: return "System Frosted"
        case .neonCyber: return "Neon Cyber"
        }
    }
}

/// Standard page identifiers in the radial dial.
enum RadialDialPageID: String, CaseIterable, Codable, Sendable {
    case main
    case snapping
    case tools
    case apps
}

/// Trackpad edge gesture presets that can summon the radial dial.
enum RadialTrackpadEdgeTrigger: String, CaseIterable, Codable, Sendable {
    case off
    case leftEdge
    case rightEdge
    case bottomEdge
}

/// Icon definition for a radial wedge.
enum RadialDialIcon: Equatable, Hashable, Codable, Sendable {
    case sfSymbol(String)
    case app(bundleID: String)
    case system(String)
}

/// Action performed when a sector is selected.
enum RadialDialActionType: Equatable, Hashable, Codable, Sendable {
    case snap(SnapPosition)
    case launchApp(bundleID: String, name: String)
    case mediaPlayPause
    case mediaNext
    case mediaPrevious
    case captureArea
    case captureWindow
    case captureOCR
    case openShelf
    case clipboard
    case page(RadialDialPageID)
    case toggleTiling
    case custom(id: String, title: String)
}

/// Recursive slice node supporting flat actions and nested radial sub-menus.
struct RadialSliceNode: Identifiable, Equatable, Codable, Sendable {
    var id: String
    var title: String
    var icon: RadialDialIcon
    var accentHex: String?
    var action: RadialDialActionType
    var children: [RadialSliceNode]?

    var isSubmenu: Bool { !(children?.isEmpty ?? true) }

    init(
        id: String,
        title: String,
        icon: RadialDialIcon,
        accentHex: String? = nil,
        action: RadialDialActionType = .custom(id: "submenu", title: "Submenu"),
        children: [RadialSliceNode]? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.accentHex = accentHex
        self.action = action
        self.children = children
    }
}

/// UserDefaults persistence for customized radial slice trees and trackpad triggers.
enum RadialDialConfigStore {
    static let storageKey = "com.katikati.dial.slices.v1"
    static let trackpadTriggerKey = "com.katikati.dial.trackpadTrigger"

    static func loadNodes(defaults: UserDefaults = .standard) -> [RadialSliceNode] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([RadialSliceNode].self, from: data),
              !decoded.isEmpty else {
            return RadialDialPresets.defaultRootNodes()
        }
        return decoded
    }

    static func saveNodes(_ nodes: [RadialSliceNode], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(nodes) else { return }
        defaults.set(data, forKey: storageKey)
    }

    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }
}

/// A single interactive sector item on the dial.
struct RadialDialItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let icon: RadialDialIcon
    let accentHex: String?
    let hasSubmenu: Bool
    let action: RadialDialActionType

    init(
        id: String,
        title: String,
        icon: RadialDialIcon,
        accentHex: String? = nil,
        hasSubmenu: Bool = false,
        action: RadialDialActionType
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.accentHex = accentHex
        self.hasSubmenu = hasSubmenu
        self.action = action
    }
}

/// A complete ring of sector items plus a center item and page metadata.
struct RadialDialPage: Identifiable, Equatable, Sendable {
    let id: RadialDialPageID
    let title: String
    let centerItem: RadialDialItem?
    let items: [RadialDialItem]
    let outerRingItems: [RadialDialItem]?

    init(
        id: RadialDialPageID,
        title: String,
        centerItem: RadialDialItem? = nil,
        items: [RadialDialItem],
        outerRingItems: [RadialDialItem]? = nil
    ) {
        self.id = id
        self.title = title
        self.centerItem = centerItem
        self.items = items
        self.outerRingItems = outerRingItems
    }
}
