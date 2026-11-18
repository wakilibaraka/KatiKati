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
    /// Stashes a dropped app in `DrawerStore` so placement and pop stay synced.
    var onAddApp: ((String) -> Void)? = nil
    var onPinFolder: ((URL) -> Void)?
    var isFolderPinned: ((URL) -> Bool)?
    var settingsStore: AppSettingsStore? = nil
    var onOpenSettings: () -> Void = {}

    /// The folder being browsed inside the pop; nil = the pop's own grid.
    @State private var browsing: URL?
    @State private var isDropTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        } else if let settingsStore {
            PopObservedSettingsHost(settingsStore: settingsStore) { store in
                popGrid(settingsStore: store)
            }
        } else {
            popGrid(settingsStore: nil)
        }
    }

    private func popGrid(settingsStore: AppSettingsStore?) -> some View {
        let items = popStore.items
        let drawerWidgets = settingsStore?.surfaceWidgets.attachments(for: .drawer) ?? []
        let extraWidgetHeight = DockWidgetConfigStore.popupSectionExtraHeight(for: drawerWidgets)
        let note: String? = items.isEmpty
            ? String(localized: "Drag apps, files or folders onto the Drawer icon")
            : (popStore.isFull ? String(format: String(localized: "The Drawer is full (%d items)"), PopPolicy.capacity) : nil)
        let mode = popStore.viewMode
        let style: DrawerLayoutStyle = mode == .list ? .list : .grid
        let plate: StackPlateMetrics = mode == .tiles
            ? .stack
            : DrawerLayoutMath.plateMetrics(style: style, labels: items.map(\.displayName))
        let layout: StackGridLayout.Result = mode == .tiles
            ? (items.isEmpty
               ? StackGridLayout.Result(columns: StackGridLayout.noteMinColumns, visibleRows: 0, scrolls: false)
               : .init(columns: StackPlateMetrics.tilesColumns,
                       visibleRows: min(items.count, StackPlateMetrics.tilesRows),
                       scrolls: items.count > min(items.count, StackPlateMetrics.tilesRows)))
            : (items.isEmpty && !drawerWidgets.isEmpty
               ? StackGridLayout.Result(columns: StackGridLayout.noteMinColumns, visibleRows: 0, scrolls: false)
               : DrawerLayoutMath.resolveLayout(itemCount: items.count, style: style, limits: context.limits, hasNote: note != nil))
        let plateContentWidth = plate.plateSize(columns: layout.columns, rows: layout.visibleRows, hasNote: note != nil, scrolls: layout.scrolls).width - 2 * plate.sidePadding
        let deckWidth = max(220, plateContentWidth)

        return StackPopupChrome(title: String(localized: "Drawer"),
                                note: note,
                                layout: layout,
                                plate: plate,
                                usesLiquidGlass: usesLiquidGlass,
                                arrow: context.arrow,
                                onPanelSizeChange: onContentResize,
                                gridAnimation: reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82),
                                gridAnimationKey: items.map(\.id) + [mode.rawValue] + drawerWidgets.map(\.id),
                                headerAccessory: AnyView(
                                    HStack(spacing: 6) {
                                        if let settingsStore {
                                            DockSurfacePinMenuButton(surface: .drawer, settingsStore: settingsStore)
                                        }
                                        DrawerLayoutTogglePill(mode: mode, reduceMotion: reduceMotion) { next in
                                            withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82)) {
                                                popStore.setViewMode(next)
                                            }
                                        }
                                    }
                                ),
                                bottomAccessory: (!drawerWidgets.isEmpty && settingsStore != nil)
                                    ? AnyView(DockSurfacePinnedDeck(
                                        surface: .drawer,
                                        usesLiquidGlass: usesLiquidGlass,
                                        width: deckWidth,
                                        settingsStore: settingsStore!,
                                        onOpenSettings: onOpenSettings
                                    ))
                                    : nil,
                                bottomAccessoryHeight: extraWidgetHeight,
                                bottomAccessoryMinWidth: drawerWidgets.isEmpty ? 0 : deckWidth + 2 * plate.sidePadding,
                                isDropTargeted: isDropTargeted) {
            ForEach(items) { item in
                let path = item.iconPath
                if mode == .list {
                    PopListRow(iconPath: path,
                               staticIcon: path == nil ? Self.missingAppIcon : nil,
                               label: item.displayName,
                               rowWidth: plate.cell.cellSize.width,
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
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { handleDrop($0) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        let pasteboardURLs = StripFileDropDelegate.DragPasteboardInspector.draggedURLs()
        let collector = DropURLCollector(count: providers.count)
        let group = DispatchGroup()
        for (index, provider) in providers.enumerated() {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                collector.set(url, at: index)
                group.leave()
            }
        }
        let store = popStore
        let addApp = onAddApp
        group.notify(queue: .main) {
            let urls = StripDropRouting.committedURLs(
                loaded: collector.urls,
                pasteboard: pasteboardURLs,
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser
            )
            guard !urls.isEmpty else { return }
            AppRuntime.actionQueue.async {
                let payloads: [DrawerItemPayload] = urls.compactMap { url in
                    let isApp = StripFileDropDelegate.DragPasteboardInspector.isApplication(url)
                    let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    let bundleID = isApp ? Bundle(url: url)?.bundleIdentifier : nil
                    return DrawerItemPayload.classify(url: url, isDirectory: isDirectory, isApplication: isApp, bundleID: bundleID)
                }
                DispatchQueue.main.async {
                    let result = DrawerDropTargetPolicy.validateDrop(payloads: payloads, existing: store.items)
                    if !result.accepted.isEmpty {
                        store.add(result.accepted)
                        for item in result.accepted where item.kind == .app {
                            addApp?(item.reference)
                        }
                    }
                    if result.rejectedForCapacity > 0 { NSSound.beep() }
                }
            }
        }
        return true
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
    /// 「Remove from Drawer」; apps get Open / Show in Finder / Copy Path / Remove from Drawer.
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
                menu.addItem(ClosureMenuItem(String(localized: "Copy Path")) {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(url.path, forType: .string)
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

/// Compact iOS/iPadOS-style segmented pill for toggling between Grid and List drawer views.
private struct DrawerLayoutTogglePill: View {
    let mode: PopViewMode
    let reduceMotion: Bool
    let onSelect: (PopViewMode) -> Void

    @Namespace private var pillSpace

    private var activeStyle: DrawerLayoutStyle { mode == .list ? .list : .grid }

    var body: some View {
        HStack(spacing: 2) {
            toggleButton(.grid, symbol: "square.grid.2x2", helpText: String(localized: "Grid view"))
            toggleButton(.list, symbol: "list.bullet", helpText: String(localized: "List view"))
        }
        .padding(2)
        .background(Capsule(style: .continuous).fill(Color.white.opacity(0.08)))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.78), value: activeStyle)
    }

    private func toggleButton(_ style: DrawerLayoutStyle, symbol: String, helpText: String) -> some View {
        let isSelected = activeStyle == style
        return Button {
            onSelect(style == .list ? .list : .grid)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.6))
                .frame(width: 20, height: 18)
                .background {
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.22))
                            .matchedGeometryEffect(id: "drawerLayoutActivePill", in: pillSpace)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(Text(helpText))
    }
}

/// Thread-safe accumulator for asynchronous `NSItemProvider` URL loads.
private final class DropURLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var urls: [URL?]
    init(count: Int) { urls = Array(repeating: nil, count: count) }
    func set(_ url: URL?, at index: Int) {
        lock.lock(); defer { lock.unlock() }
        urls[index] = url
    }
}

/// One row of the pop's List view: the item's icon, then its name — the layout DockPops calls List.
private struct PopListRow: View {
    let iconPath: String?
    let staticIcon: NSImage?
    let label: String
    let rowWidth: CGFloat
    let dragURL: URL?
    let contextMenu: () -> NSMenu
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dockThemeStyle) private var dockThemeStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
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
        .frame(width: rowWidth, height: Cell.list.cellSize.height, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.1 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering in isHovered = hovering }
        .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.78), value: isHovered)
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

private struct PopObservedSettingsHost<Content: View>: View {
    @ObservedObject var settingsStore: AppSettingsStore
    let content: (AppSettingsStore) -> Content

    var body: some View {
        content(settingsStore)
    }
}
