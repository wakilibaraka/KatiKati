import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The drawer pop (DockPops-style): up to 25 apps, files and folders in the same chrome and cells as
/// the folder popup (`StackPopupChrome` / `FolderGridCell`), in the pop's own order (`PopStore`).
///
/// - An app opens (or comes forward when it runs); its menu can take it out of the drawer, which puts
///   its windows back on the bar (`DrawerStore` stays the placement authority).
/// - A file opens in its default app and drags out as a real file.
/// - A folder is **browsed right inside the pop**: the folder grid replaces the pop's, with a back
///   button that returns to the pop (`FolderGridPopupView.onBackAtRoot`), drill-in below it as usual.
struct PopGridPopupView: View {
    @ObservedObject var popStore: PopStore
    let context: StackPopupContext
    /// Explicit, no default: every panel is its own hosting root (`AGENTS.md` no-default rule).
    let usesLiquidGlass: Bool
    var onClosePopup: () -> Void = {}
    var onContentResize: (CGSize) -> Void = { _ in }
    /// Takes an app out of the drawer (`DrawerStore.remove`); the pop follows through `PopStore.syncApps`.
    /// No default: an omission would leave the menu item silently doing nothing.
    let onRemoveApp: (String) -> Void
    var onPinFolder: ((URL) -> Void)?
    var isFolderPinned: ((URL) -> Bool)?

    /// The folder being browsed inside the pop; nil = the pop's own grid.
    @State private var browsing: URL?

    var body: some View {
        if let browsing {
            FolderGridPopupView(rootURL: browsing,
                                initialEntries: nil,
                                context: context,
                                usesLiquidGlass: usesLiquidGlass,
                                onFileOpened: onClosePopup,
                                onContentResize: onContentResize,
                                onPinFolder: onPinFolder,
                                isFolderPinned: isFolderPinned,
                                onBackAtRoot: { self.browsing = nil })
                .id(browsing)
        } else {
            popGrid
        }
    }

    private var popGrid: some View {
        let items = popStore.items
        let note: String? = items.isEmpty
            ? String(localized: "Drag apps, files or folders onto the Drawer icon")
            : (popStore.isFull ? String(format: String(localized: "The Drawer is full (%d items)"), PopPolicy.capacity) : nil)
        let mode = popStore.viewMode
        // An empty pop is the status line alone, like the empty shelf.
        let layout: StackGridLayout.Result = items.isEmpty
            ? StackGridLayout.Result(columns: StackGridLayout.noteMinColumns, visibleRows: 0, scrolls: false)
            : {
                switch mode {
                case .grid:
                    return StackGridLayout.resolve(cellCount: items.count, limits: context.limits, hasNote: note != nil)
                case .tiles:
                    let rows = min(items.count, StackPlateMetrics.tilesRows)
                    return .init(columns: StackPlateMetrics.tilesColumns, visibleRows: rows, scrolls: items.count > rows)
                case .list:
                    // List rows are 34pt, so the native grid's 128pt row budget says nothing about them.
                    let rows = min(items.count, 8)
                    return .init(columns: 1, visibleRows: rows, scrolls: items.count > rows)
                }
            }()
        return StackPopupChrome(title: String(localized: "Drawer"),
                                note: note,
                                layout: layout,
                                plate: mode == .list ? .list : .stack,
                                usesLiquidGlass: usesLiquidGlass,
                                arrow: context.arrow,
                                onPanelSizeChange: onContentResize,
                                gridAnimation: .easeInOut(duration: DrawerAnimation.duration),
                                gridAnimationKey: items.map(\.id)) {
            ForEach(items) { item in
                let path = item.iconPath
                if mode == .list {
                    PopListRow(iconPath: path,
                               staticIcon: path == nil ? Self.missingAppIcon : nil,
                               label: item.displayName,
                               dragURL: item.kind == .app ? nil : URL(fileURLWithPath: item.reference),
                               contextMenu: { menu(for: item) }) { open(item) }
                } else {
                    FolderGridCell(iconPath: path,
                                   staticIcon: path == nil ? Self.missingAppIcon : nil,
                                   label: item.displayName,
                                   preview: item.kind == .file ? .init(stamp: nil) : nil,
                                   dragURL: item.kind == .app ? nil : URL(fileURLWithPath: item.reference),
                                   contextMenu: { menu(for: item) }) { open(item) }
                }
            }
        }
    }

    private func open(_ item: PopItem) {
        switch item.kind {
        case .app:
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: item.reference)
            if let app = running.first {
                running.forEach { $0.unhide() }
                app.activate(options: [.activateAllWindows])
            } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.reference) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSSound.beep()
                return
            }
            onClosePopup()
        case .folder:
            browsing = URL(fileURLWithPath: item.reference, isDirectory: true)
        case .file:
            NSWorkspace.shared.open(URL(fileURLWithPath: item.reference))
            onClosePopup()
        }
    }

    /// Hand-built `NSMenu` (rule file). Files and folders get the folder popup's menu plus
    /// 「Remove from Drawer」; apps get Open / Show in Finder / Remove from Drawer.
    private func menu(for item: PopItem) -> NSMenu {
        let store = popStore
        switch item.kind {
        case .app:
            let menu = NSMenu()
            let bundleID = item.reference
            menu.addItem(ClosureMenuItem(String(localized: "Open")) { open(item) })
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                menu.addItem(ClosureMenuItem(String(localized: "Show in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    onClosePopup()
                })
            }
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(String(localized: "Remove from Drawer")) { onRemoveApp(bundleID) })
            return menu
        case .file, .folder:
            let url = URL(fileURLWithPath: item.reference, isDirectory: item.kind == .folder)
            let canPin = item.kind == .folder && !(isFolderPinned?(url) ?? true)
            let id = item.id
            return FileItemMenuBuilder.menu(for: .init(
                url: url,
                isDirectory: item.kind == .folder,
                closePopup: onClosePopup,
                pinFolder: canPin ? { onPinFolder?(url) } : nil,
                onTrashed: { store.remove(id) },
                shelfActions: [ClosureMenuItem(String(localized: "Remove from Drawer")) { store.remove(id) }]
            ))
        }
    }

    /// An app whose bundle can no longer be found (uninstalled): a generic app icon, still removable.
    private static let missingAppIcon = NSWorkspace.shared.icon(for: .applicationBundle)
}

/// One row of the pop's List view: the item's icon, then its name — the layout DockPops calls List.
private struct PopListRow: View {
    let iconPath: String?
    let staticIcon: NSImage?
    let label: String
    let dragURL: URL?
    let contextMenu: () -> NSMenu
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dockThemeStyle) private var dockThemeStyle
    private typealias Cell = StackCellMetrics

    var body: some View {
        let row = HStack(spacing: 8) {
            Image(nsImage: iconPath.map { FolderIconResolver.resolve($0) } ?? staticIcon ?? Self.placeholder)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: Cell.list.iconSize, height: Cell.list.iconSize)
            Text(label)
                .font(.system(size: Cell.list.labelSize))
                .foregroundStyle(DockThemeTokens.resolved(for: colorScheme, style: dockThemeStyle).stackPopupText.color)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(width: Cell.list.cellSize.width, height: Cell.list.cellSize.height, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .nativeContextMenu { contextMenu() }
        .help(label)
        if let dragURL {
            row.onDrag { FileDragItemProvider.make(for: dragURL) }
        } else {
            row
        }
    }

    private static let placeholder = NSWorkspace.shared.icon(for: .data)
}
