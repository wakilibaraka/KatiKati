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
        // An empty pop is the status line alone, like the empty shelf.
        let layout = items.isEmpty
            ? StackGridLayout.Result(columns: StackGridLayout.noteMinColumns, visibleRows: 0, scrolls: false)
            : StackGridLayout.resolve(cellCount: items.count, limits: context.limits, hasNote: note != nil)
        return StackPopupChrome(title: String(localized: "Drawer"),
                                note: note,
                                layout: layout,
                                plate: .stack,
                                usesLiquidGlass: usesLiquidGlass,
                                arrow: context.arrow,
                                onPanelSizeChange: onContentResize,
                                gridAnimation: .easeInOut(duration: DrawerAnimation.duration),
                                gridAnimationKey: items.map(\.id)) {
            ForEach(items) { item in
                let path = item.iconPath
                FolderGridCell(iconPath: path,
                               staticIcon: path == nil ? Self.missingAppIcon : nil,
                               label: item.displayName,
                               preview: item.kind == .file ? .init(stamp: nil) : nil,
                               dragURL: item.kind == .app ? nil : URL(fileURLWithPath: item.reference),
                               contextMenu: { menu(for: item) }) { open(item) }
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
