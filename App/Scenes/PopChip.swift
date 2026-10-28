import AppKit
import SwiftUI

/// The drawer pop's dock icon (DockPops-style): a tile with a live 2 × 2 preview of the pop's first
/// items. Sits at the head of the tail zone, left of the pinned folders (Downloads) and the Trash.
/// Click opens the pop (`PopGridPopupView`); anything dropped on it joins the pop (`StripDropRouting
/// .addToPop`), and a window card dragged onto it stashes its app (`PanelCoordinator.dragDropZones`).
/// **Not draggable** (fixed place), like the shelf.
struct PopChip: View {
    @ObservedObject var popStore: PopStore
    let isDropTargeted: Bool
    /// 任务条尺寸档位的缩放系数。**故意不给默认值**——漏传必须是编译错误，见 AGENTS《Taskbar Size Tiers》。
    let scale: CGFloat
    /// 侧边栏上这张卡是**方**的。**故意不给默认值**。
    let railTile: Bool
    /// 悬停效果档位。**故意不给默认值**。
    let hoverStyle: HoverStyle
    let isHovered: Bool
    let onTap: () -> Void
    let onAddFolder: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var quietHoverFeedback: Bool {
        hoverStyle.showsQuietHoverFeedback(isHovering: isHovered)
    }

    private var helpText: String {
        popStore.items.isEmpty
            ? String(localized: "Drawer — drag apps, files or folders here")
            : String(format: String(localized: "Drawer · %d of %d"), popStore.items.count, PopPolicy.capacity)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            tile
            Spacer(minLength: 0)
        }
        .frame(width: ChipPillMetrics.cardWidth * scale,
               height: ChipPillMetrics.cardFrameHeight(scale, onRail: railTile))
        .chipQuietHoverScale(quietHoverFeedback,
                             cardWidth: ChipPillMetrics.cardWidth * scale,
                             scale: scale)
        .scaleEffect(isDropTargeted ? 1.08 : 1)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .floatingContextMenu { buildMenu() }
        .help(helpText)
        .animation(.easeInOut(duration: 0.12), value: isDropTargeted)
    }

    /// An opaque tile drawn at `bareIconVisibleSlot`, like the shelf (a translucent tile vanishes on
    /// dark glass — see `ShelfChip.shelfIcon`), holding up to four mini icons.
    private var tile: some View {
        let art = ChipPillMetrics.bareIconVisibleSlot * scale
        let inset = art * 0.12
        let cell = (art - inset * 3) / 2
        let preview = Array(popStore.items.prefix(4))
        return ZStack {
            RoundedRectangle(cornerRadius: art * 0.215, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.28) : Color(white: 0.93))
            RoundedRectangle(cornerRadius: art * 0.215, style: .continuous)
                .strokeBorder(isDropTargeted ? Color.accentColor : Color.black.opacity(0.12),
                              lineWidth: isDropTargeted ? 2 : 0.5)
            if preview.isEmpty {
                Image(systemName: "square.grid.2x2")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: art * 0.46, height: art * 0.46)
                    .foregroundStyle(Color.secondary)
            } else {
                VStack(spacing: inset) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: inset) {
                            ForEach(0..<2, id: \.self) { column in
                                let index = row * 2 + column
                                if index < preview.count, let path = preview[index].iconPath {
                                    Image(nsImage: FolderIconResolver.resolve(path))
                                        .resizable()
                                        .interpolation(.high)
                                        .frame(width: cell, height: cell)
                                } else {
                                    Color.clear.frame(width: cell, height: cell)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(width: art, height: art)
        // 槽位仍是 40pt，与所有图标卡一致——只有画出来的方块缩到 32.5。
        .frame(width: ChipPillMetrics.bareIconSlot * scale,
               height: ChipPillMetrics.bareIconSlot * scale)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(String(localized: "Open Drawer")) { onTap() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(String(localized: "Add Folder…")) { onAddFolder() })
        return menu
    }
}

extension PopItem {
    /// The file whose icon stands for this item: the app bundle (looked up by bundle id; nil when the
    /// app is gone) or the item's own path.
    var iconPath: String? {
        switch kind {
        case .app: return NSWorkspace.shared.urlForApplication(withBundleIdentifier: reference)?.path
        case .file, .folder: return reference
        }
    }

    var displayName: String {
        switch kind {
        case .app: return AppDisplayNameResolver.displayName(for: reference)
        case .file, .folder: return FileManager.default.displayName(atPath: reference)
        }
    }
}

/// Where the pop chip is on screen, for the coordinator's stash drop zone. The strip writes both halves
/// (its `"strip"`-space chip frame and its own screen rect); the coordinator reads `screenRect` at drag
/// time. A reference box so the strip can update it at frame rate without re-rendering anything.
@MainActor
final class PopChipFrameSink {
    var stripFrame: CGRect = .zero
    var stripRootScreenRect: CGRect = .zero

    /// Same mapping as `DockStripView.popChipTapped`. nil until both halves are known.
    var screenRect: CGRect? {
        guard stripFrame != .zero, stripRootScreenRect != .zero else { return nil }
        return CGRect(x: stripRootScreenRect.minX + stripFrame.minX,
                      y: stripRootScreenRect.maxY - stripFrame.maxY,
                      width: stripFrame.width, height: stripFrame.height)
    }
}
