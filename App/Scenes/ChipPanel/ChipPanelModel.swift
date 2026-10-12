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
                actionRows: content.actions.count)
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
