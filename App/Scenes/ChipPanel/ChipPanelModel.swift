import AppKit
import SwiftUI

// Phase 9-0 — the model behind the floating chip panel: one non-activating panel above the strip
// that hosts either the hover **preview** (window thumbnails) or the right-click **jump list**.

struct ChipPanelWindow: Identifiable, Equatable {
    let id: String               // window id string (what `runtime.activate(windowID:)` takes)
    let cgWindowID: CGWindowID?
    let title: String
    let marker: WindowMenuEntry.Marker
}

struct ChipPanelRecent: Identifiable {
    let url: URL
    var bundleID: String?
    var id: String { url.path }
    var title: String { url.lastPathComponent }
}

struct ChipPanelAction: Identifiable {
    let id: String
    let title: String
    /// Shown instead of `title` while ⌥ is held (Quit → Force Quit), like the native Dock.
    var optionTitle: String?
    var isChecked: Bool?
    var isDestructive = false
    var separatorBefore = false
    /// Grayed section label (an `NSMenuItem` with no action).
    var isHeader = false
    var icon: NSImage?
    /// Receives whether ⌥ was held at the click.
    let handler: (Bool) -> Void
}

struct ChipPanelContent {
    let chipID: String
    let bundleID: String?
    let appName: String
    let icon: NSImage
    /// The windows behind the hovered chip (one for a normal chip, several for a grouped app).
    var ownWindows: [ChipPanelWindow]
    /// Every window of the app — what the preview expands to once the pointer enters the panel.
    var allWindows: [ChipPanelWindow]
    var recents: [ChipPanelRecent]
    var actions: [ChipPanelAction]
    /// False for a bare menu converted from an `NSMenu` (Downloads, Trash, shelf…): no app header row.
    var showsHeader: Bool { !appName.isEmpty }
}

enum ChipPanelMode: Equatable { case preview, menu }

@MainActor
final class ChipPanelModel: ObservableObject {
    @Published var content: ChipPanelContent?
    @Published var mode: ChipPanelMode = .preview
    /// Preview only: show every window of the app instead of just the chip's own.
    @Published var expanded = false
    @Published var thumbnails: [String: NSImage] = [:]
    @Published var screenAccess = WindowThumbnailCapture.isAuthorized
    @Published var optionHeld = false
    @Published var thumbWidth: CGFloat = 180

    var thumbSize: CGSize { CGSize(width: thumbWidth, height: (thumbWidth * 0.62).rounded()) }

    var previewWindows: [ChipPanelWindow] {
        guard let content else { return [] }
        let list = expanded ? content.allWindows : content.ownWindows
        return Array(list.prefix(ChipPanelLayout.maxPreviewCards))
    }

    var plateSize: CGSize {
        guard let content else { return .zero }
        switch mode {
        case .preview:
            let count = (expanded ? content.allWindows : content.ownWindows).count
            return ChipPanelLayout.previewPlateSize(count: count, thumb: thumbSize)
        case .menu:
            return ChipPanelLayout.menuPlateSize(
                windowRows: min(content.allWindows.count, Self.maxMenuWindows),
                recentRows: min(content.recents.count, Self.maxRecents),
                actionRows: content.actions.count,
                actionSeparators: content.actions.enumerated().filter { $0.offset > 0 && $0.element.separatorBefore }.count,
                hasHeader: content.showsHeader)
        }
    }

    static let maxMenuWindows = 8
    static let maxRecents = 5

    // Actions, set by the controller.
    var activateWindow: (String) -> Void = { _ in }
    var closeWindow: (String) -> Void = { _ in }
    var openRecent: (ChipPanelRecent) -> Void = { _ in }
    var runAction: (ChipPanelAction) -> Void = { _ in }
    var requestScreenAccess: () -> Void = {}
}

/// What the strip reports about the window chip under the pointer (independent of the title-bubble style).
struct ChipHoverRequest: Equatable {
    let chipID: String
    /// Screen coordinates (y up) of the chip's visible rect.
    let anchorVisibleRect: CGRect
}


/// Turns any `NSMenu` into the floating panel's rows, so every dock chip's right-click menu can float above
/// the dock instead of covering it. Option-alternate items (Quit / Force Quit) become `optionTitle`.
enum ChipPanelMenuBridge {
    @MainActor
    static func content(from menu: NSMenu) -> ChipPanelContent {
        var actions: [ChipPanelAction] = []
        var pendingSeparator = false
        var counter = 0
        func invoke(_ item: NSMenuItem) {
            if let closure = item as? ClosureMenuItem { closure.handler() }
            else if let action = item.action { NSApp.sendAction(action, to: item.target, from: item) }
        }
        func add(_ items: [NSMenuItem], indent: Bool) {
            for item in items {
                if item.isSeparatorItem { pendingSeparator = true; continue }
                if item.isHidden { continue }
                if item.isAlternate, let last = actions.indices.last {
                    let base = actions[last]
                    let main = base.handler
                    actions[last] = ChipPanelAction(
                        id: base.id, title: base.title, optionTitle: item.title, isChecked: base.isChecked,
                        isDestructive: base.isDestructive, separatorBefore: base.separatorBefore,
                        isHeader: base.isHeader, icon: base.icon
                    ) { option in option ? invoke(item) : main(false) }
                    continue
                }
                counter += 1
                let title = (indent ? "    " : "") + item.title
                if let submenu = item.submenu {
                    actions.append(ChipPanelAction(id: "m\(counter)", title: item.title, separatorBefore: pendingSeparator,
                                                   isHeader: true, handler: { _ in }))
                    pendingSeparator = false
                    add(submenu.items, indent: true)
                    continue
                }
                let isHeader = item.action == nil && !(item is ClosureMenuItem)
                actions.append(ChipPanelAction(
                    id: "m\(counter)", title: title,
                    isChecked: item.state == .off ? nil : true,
                    separatorBefore: pendingSeparator, isHeader: isHeader, icon: item.image
                ) { _ in if item.isEnabled { invoke(item) } })
                pendingSeparator = false
            }
        }
        add(menu.items, indent: false)
        return ChipPanelContent(chipID: "menu", bundleID: nil, appName: "", icon: NSImage(),
                                ownWindows: [], allWindows: [], recents: [], actions: actions)
    }
}
