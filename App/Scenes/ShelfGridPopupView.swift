import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The shelf's popup: the parked files in the same chrome and cells as the folder popup
/// (`StackPopupChrome` / `FolderGridCell`), but with no drill-in, no 「Open in Finder」 tail cell and
/// no directory watcher — the source is `ShelfStore`'s path list (newest first; pruned by the
/// coordinator before the popup shows). Cells drag out as real files; their menu adds
/// 「Remove from Shelf」, and trashing one removes it from the shelf too.
struct ShelfGridPopupView: View {
    @ObservedObject var shelfStore: ShelfStore
    let context: StackPopupContext
    /// Explicit, no default: every panel is its own hosting root (`AGENTS.md` no-default rule).
    let usesLiquidGlass: Bool
    var onClosePopup: () -> Void = {}
    var onContentResize: (CGSize) -> Void = { _ in }
    var onPinFolder: ((URL) -> Void)?
    var isFolderPinned: ((URL) -> Bool)?

    /// Paths picked with ⌘/⇧-click (or by clicking while a selection exists). Drives the action bar.
    @State private var selected = Set<String>()

    var body: some View {
        // File attributes are read once per render in shelf order (the shelf is small; the
        // coordinator pruned it before showing the popup).
        let entries = FolderContentsLoader.entries(forPaths: shelfStore.itemPaths)
        let showIntro = ShelfIntro.shouldShow(introSeen: shelfStore.introSeen, itemCount: entries.count)
        let livePaths = Set(entries.map(\.url.path))
        let picked = selected.intersection(livePaths)
        let selecting = !picked.isEmpty && !showIntro
        // A selection swaps the status line for the action bar (the line is reserved either way).
        let note = showIntro ? nil : (selecting ? " " : Self.note(for: entries))
        // An empty shelf is the status line alone: no row of blank cells under it. The first-use guide is
        // a fixed 4 × 1 block (derived, never measured).
        let layout = showIntro
            ? StackGridLayout.Result(columns: 4, visibleRows: 1, scrolls: false)
            : entries.isEmpty
            ? StackGridLayout.Result(columns: StackGridLayout.noteMinColumns, visibleRows: 0, scrolls: false)
            : StackGridLayout.resolve(cellCount: entries.count, limits: context.limits, hasNote: note != nil)

        StackPopupChrome(title: String(localized: "Shelf"),
                         note: note,
                         layout: layout,
                         plate: .stack,
                         usesLiquidGlass: usesLiquidGlass,
                         arrow: context.arrow,
                         onPanelSizeChange: onContentResize,
                         gridAnimation: .easeInOut(duration: DrawerAnimation.duration),
                         gridAnimationKey: entries.map(\.url.path),
                         intro: showIntro ? AnyView(ShelfIntroView()) : nil,
                         noteAccessory: selecting ? AnyView(selectionBar(for: picked)) : nil) {
            ForEach(entries, id: \.url) { entry in
                let pinned = shelfStore.isPinned(entry.url.path)
                FolderGridCell(iconPath: entry.isAccessible ? entry.url.path : nil,
                               staticIcon: entry.isAccessible ? nil : Self.inaccessibleIcon,
                               label: entry.name,
                               preview: entry.isAccessible && !entry.isDirectory ? .init(stamp: entry.dateModified) : nil,
                               dragURL: entry.isAccessible ? entry.url : nil,
                               contextMenu: { cellMenu(for: entry) }) {
                    // ⌘/⇧-click, or any click while a selection exists, toggles selection. Otherwise the shelf
                    // never drills in: a click opens (a folder opens in Finder).
                    let flags = NSEvent.modifierFlags
                    if selecting || flags.contains(.command) || flags.contains(.shift) {
                        if selected.contains(entry.url.path) { selected.remove(entry.url.path) } else { selected.insert(entry.url.path) }
                    } else {
                        NSWorkspace.shared.open(entry.url)
                        onClosePopup()
                    }
                }
                .overlay {
                    if picked.contains(entry.url.path) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.accentColor, lineWidth: 2)
                            .padding(6)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if picked.contains(entry.url.path) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 14))
                            .foregroundStyle(Color.accentColor).padding(6)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if pinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(.orange).padding(6) }
                }
            }
        }
    }

    /// Action bar for the current selection: count, then Pin / Zip / Compress / Share / AirDrop / Remove.
    private func selectionBar(for picked: Set<String>) -> some View {
        let store = shelfStore
        let urls = store.itemPaths.filter { picked.contains($0) }.map { URL(fileURLWithPath: $0) }
        let allPinned = urls.allSatisfy { store.isPinned($0.path) }
        let compressible = urls.filter(ShelfActions.canCompress)
        let reducible = urls.filter(ShelfActions.isPDF)
        func finish() { selected = [] }
        return HStack(spacing: 4) {
            Text(String(format: String(localized: "%d selected"), urls.count))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            Spacer(minLength: 6)
            barButton("pin\(allPinned ? ".slash" : "")", help: allPinned ? Text("Unpin from Shelf") : Text("Pin to Shelf")) {
                for u in urls where store.isPinned(u.path) == allPinned { store.togglePin(u.path) }
            }
            barButton("doc.zipper", help: Text("Zip")) { ShelfActions.zip(urls, into: store); finish() }
            if !compressible.isEmpty {
                barButton("arrow.down.right.and.arrow.up.left", help: Text("Compress")) { ShelfActions.compress(compressible, into: store); finish() }
            }
            if !reducible.isEmpty {
                barButton("arrow.down.doc", help: Text("Compress")) { ShelfActions.reducePDF(reducible, into: store); finish() }
            }
            barButton("square.and.arrow.up", help: Text("Share…")) { ShelfActions.share(urls); finish() }
            barButton("airplayaudio", help: Text("AirDrop")) { ShelfActions.airDrop(urls); finish() }
            barButton("minus.circle", help: Text("Remove from Shelf")) { for u in urls { store.remove(u.path) }; finish() }
            barButton("xmark", help: Text("Clear Selection")) { finish() }
        }
    }

    private func barButton(_ symbol: String, help: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 26, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private static func note(for entries: [FolderContentsLoader.Entry]) -> String? {
        if entries.isEmpty { return String(localized: "Drag files here to park them") }
        // Kept, not pruned: the file exists but its folder's privacy permission is missing.
        if entries.contains(where: { !$0.isAccessible }) {
            return String(localized: "Some items can’t be accessed. Allow KatiKati to access their folder in your Mac’s privacy settings.")
        }
        return nil
    }

    private static let inaccessibleIcon = NSWorkspace.shared.icon(for: .data)

    /// Dropover-style extras for one shelf item: pin, compress, zip, share.
    private func shelfMenuItems(for url: URL) -> [NSMenuItem] {
        let store = shelfStore
        let path = url.path
        var items: [NSMenuItem] = []
        if store.isPinned(path) {
            items.append(ClosureMenuItem(String(localized: "Unpin from Shelf")) { store.togglePin(path) })
        } else {
            items.append(ClosureMenuItem(String(localized: "Pin to Shelf")) { store.togglePin(path) })
        }
        if ShelfActions.canCompress(url) {
            items.append(ClosureMenuItem(String(localized: "Compress")) { ShelfActions.compress([url], into: store) })
        }
        if ShelfActions.isPDF(url) {
            items.append(ClosureMenuItem(String(localized: "Compress")) { ShelfActions.reducePDF([url], into: store) })
        }
        items.append(ClosureMenuItem(String(localized: "Zip")) { ShelfActions.zip([url], into: store) })
        if store.itemPaths.count > 1 {
            items.append(ClosureMenuItem(String(localized: "Zip Everything on Shelf")) { ShelfActions.zip(store.itemPaths.map { URL(fileURLWithPath: $0) }, into: store) })
        }
        items.append(ClosureMenuItem(String(localized: "Share…")) { ShelfActions.share([url]) })
        items.append(ClosureMenuItem(String(localized: "AirDrop")) { ShelfActions.airDrop([url]) })
        return items
    }

    private func cellMenu(for entry: FolderContentsLoader.Entry) -> NSMenu {
        let canPin = entry.isDirectory && !(isFolderPinned?(entry.url) ?? true)
        let path = entry.url.path
        return FileItemMenuBuilder.menu(for: .init(
            url: entry.url,
            isDirectory: entry.isDirectory,
            closePopup: onClosePopup,
            pinFolder: canPin ? { onPinFolder?(entry.url) } : nil,
            removeFromShelf: { shelfStore.remove(path) },
            onTrashed: { shelfStore.remove(path) },
            shelfActions: shelfMenuItems(for: entry.url)
        ))
    }
}

/// The shelf window's first-use notes. Shown only while the shelf has never held anything
/// (`ShelfIntro.shouldShow`); they never return once a file has been parked.
struct ShelfIntroView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            row("arrow.down.doc.fill", Text("Drag files onto the shelf, or shake a file while dragging to pop up a drop target."))
            row("pin.fill", Text("Pin items to keep them. Clear removes only unpinned items."))
            row("contextualmenu.and.cursorarrow", Text("Right-click an item to Zip, Compress, Share or AirDrop."))
            row("externaldrive.fill", Text("Items stay where they are. Auto-expire and copy storage are in Settings › Shelf."))
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func row(_ symbol: String, _ text: Text) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 18)
            text
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
