import AppKit
import QuickLookThumbnailing
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
    var settingsStore: AppSettingsStore? = nil
    var onOpenSettings: () -> Void = {}

    /// Paths picked with ⌘/⇧-click (or by clicking while a selection exists). Drives the action bar.
    @State private var selected = Set<String>()
    @AppStorage(ShelfPolicy.presentationStyleKey) private var styleRaw = ShelfPresentationStyle.floatingCardStack.rawValue
    @AppStorage(ShelfPolicy.showTextExcerptKey) private var showTextExcerpt = true
    @State private var showActionsBar = false
    @State private var isDropTargeted = false
    @State private var hoveredPath: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var presentationStyle: ShelfPresentationStyle {
        ShelfPresentationStyle(rawValue: styleRaw) ?? .floatingCardStack
    }

    var body: some View {
        Group {
            if presentationStyle == .floatingCardStack {
                floatingCardStackView
            } else if let settingsStore {
                ShelfObservedSettingsHost(settingsStore: settingsStore) { store in
                    shelfContent(settingsStore: store)
                }
            } else {
                shelfContent(settingsStore: nil)
            }
        }
        .onDrop(of: [.fileURL, .plainText, .url], isTargeted: $isDropTargeted) { providers in
            handleIncomingDrop(providers)
        }
    }

    private func shelfContent(settingsStore: AppSettingsStore?) -> some View {
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

        return StackPopupChrome(title: String(localized: "Shelf"),
                         note: note,
                         layout: layout,
                         plate: .stack,
                         usesLiquidGlass: usesLiquidGlass,
                         arrow: context.arrow,
                         onPanelSizeChange: onContentResize,
                         gridAnimation: .easeInOut(duration: DrawerAnimation.duration),
                         gridAnimationKey: entries.map(\.url.path),
                         intro: showIntro ? AnyView(ShelfIntroView()) : nil,
                         noteAccessory: selecting ? AnyView(selectionBar(for: picked)) : nil,
                         headerAccessory: AnyView(styleToggleButton),
                         isDropTargeted: isDropTargeted) {
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
        let reducibleImages = urls.filter(ShelfActions.isImage)
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
            if !reducibleImages.isEmpty {
                barButton("arrow.down.circle", help: Text("Reduce Image")) { ShelfActions.reduceImage(reducibleImages, into: store); finish() }
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
        if ShelfActions.isImage(url) {
            items.append(ClosureMenuItem(String(localized: "Reduce Image")) { ShelfActions.reduceImage([url], into: store) })
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

private struct ShelfObservedSettingsHost<Content: View>: View {
    @ObservedObject var settingsStore: AppSettingsStore
    let content: (AppSettingsStore) -> Content

    var body: some View {
        content(settingsStore)
    }
}

// MARK: - SLICE SF-2: Floating Card Stack & Inline Transform Bar

extension ShelfGridPopupView {
    private var styleToggleButton: some View {
        Button {
            styleRaw = presentationStyle == .floatingCardStack
                ? ShelfPresentationStyle.compactFileTray.rawValue
                : ShelfPresentationStyle.floatingCardStack.rawValue
        } label: {
            Image(systemName: presentationStyle == .floatingCardStack ? "square.grid.2x2.fill" : "rectangle.stack.fill")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.88))
                .frame(width: 24, height: 22).background(Capsule(style: .continuous).fill(Color.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .help(presentationStyle == .floatingCardStack ? Text("Compact Tray Grid") : Text("Floating Card Stack"))
    }

    private var floatingCardStackView: some View {
        let entries = FolderContentsLoader.entries(forPaths: shelfStore.itemPaths)
        let showIntro = ShelfIntro.shouldShow(introSeen: shelfStore.introSeen, itemCount: entries.count)
        let picked = selected.intersection(Set(entries.map(\.url.path)))
        let activeURLs = picked.isEmpty ? entries.map(\.url) : entries.filter { picked.contains($0.url.path) }.map(\.url)
        let visibleCount = min(entries.count, 3)
        let cardsHeight: CGFloat = showIntro ? 184 : (entries.isEmpty ? 104 : CGFloat(visibleCount) * 124 + CGFloat(max(0, visibleCount - 1)) * 10 + 14)
        let totalSize = CGSize(width: 308, height: 52 + (showActionsBar && !entries.isEmpty ? 36 : 0) + cardsHeight + 16)

        return VStack(spacing: 8) {
            browseHeaderPill(entries: entries, activeURLs: activeURLs)
            if showActionsBar && !entries.isEmpty {
                floatingTransformBar(urls: activeURLs).transition(.opacity.combined(with: .move(edge: .top)))
            }
            if showIntro {
                ShelfIntroView().padding(14).frame(width: 282, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.10).opacity(0.9)))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1))
                    .shadow(color: .black.opacity(0.28), radius: 12, y: 6)
            } else if entries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white.opacity(isDropTargeted ? 1 : 0.78))
                    Text("Drop files, links, or text here").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.84))
                }
                .frame(width: 282, height: 96)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.11).opacity(0.68))))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(isDropTargeted ? Color.accentColor : .white.opacity(0.22), lineWidth: isDropTargeted ? 2 : 1))
                .shadow(color: .black.opacity(0.24), radius: 10, y: 5)
            } else {
                ScrollView(.vertical, showsIndicators: entries.count > 3) {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(entries.enumerated()), id: \.element.url) { idx, entry in cardRow(entry: entry, index: idx, picked: picked) }
                    }.padding(.vertical, 6).padding(.horizontal, 12)
                }.frame(width: 306, height: cardsHeight)
            }
        }
        .padding(.vertical, 8).frame(width: totalSize.width, height: totalSize.height, alignment: .top)
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: showActionsBar)
        .onAppear { onContentResize(totalSize) }
        .onChange(of: totalSize) { _, newSize in onContentResize(newSize) }
    }

    private func browseHeaderPill(entries: [FolderContentsLoader.Entry], activeURLs: [URL]) -> some View {
        let actions = ShelfBatchTransformAction.eligibleActions(for: activeURLs)
        let pill = HStack(spacing: 8) {
            Button { showActionsBar.toggle() } label: {
                HStack(spacing: 6) {
                    Text("Browse").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    if !entries.isEmpty {
                        Text(verbatim: "\(entries.count)").font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.92)).padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(.white.opacity(0.22)))
                    }
                }
            }.buttonStyle(.plain)
            Spacer(minLength: 4)
            Button { pickFilesForShelf() } label: {
                Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(.white).frame(width: 22, height: 22).background(Circle().fill(.white.opacity(0.18)))
            }.buttonStyle(.plain).help(Text("Add Files…"))
            if !actions.isEmpty {
                Button { showActionsBar.toggle() } label: {
                    Image(systemName: "wand.and.stars").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 22, height: 22).background(Circle().fill(.white.opacity(showActionsBar ? 0.34 : 0.16)))
                }.buttonStyle(.plain)
            }
            styleToggleButton
        }
        .padding(.horizontal, 14).frame(width: 256, height: 36)
        .background(Capsule(style: .continuous).fill(.ultraThinMaterial)
            .overlay(Capsule(style: .continuous).fill(LinearGradient(colors: [Color(red: 0.46, green: 0.41, blue: 0.72).opacity(0.86), Color(red: 0.35, green: 0.31, blue: 0.58).opacity(0.84)], startPoint: .topLeading, endPoint: .bottomTrailing))))
        .overlay(Capsule(style: .continuous).strokeBorder(isDropTargeted ? Color.accentColor : .white.opacity(0.28), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
        return Group { if let first = activeURLs.first { pill.onDrag { FileDragItemProvider.make(for: first) } } else { pill } }
    }

    private func floatingTransformBar(urls: [URL]) -> some View {
        let actions = ShelfBatchTransformAction.eligibleActions(for: urls)
        return HStack(spacing: 5) {
            if actions.contains(.zipItems) { pillAction("Zip") { ShelfActions.zip(urls, into: shelfStore); selected = [] } }
            if actions.contains(.mergeToPDF) { pillAction("Merge PDF") { mergeToPDF(urls) } }
            if actions.contains(where: { if case .convertImages = $0 { return true }; return false }) {
                Menu {
                    ForEach(ImageTargetFormat.allCases, id: \.rawValue) { fmt in
                        Button(fmt.rawValue.uppercased()) { ShelfActions.convertImage(urls, format: fmt, into: shelfStore) }
                    }
                } label: {
                    Text("Convert").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(.white.opacity(0.18)))
                }.menuStyle(.borderlessButton).fixedSize()
            }
            if actions.contains(.copyAllPaths) {
                pillAction("Copy Paths") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
                }
            }
            if actions.contains(.airDropShare) { pillAction("AirDrop") { ShelfActions.airDrop(urls) } }
            pillAction("Clear Unpinned") { shelfStore.clear(); selected = [] }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(.ultraThinMaterial).overlay(Capsule().fill(Color(white: 0.12).opacity(0.75))))
        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
    }

    private func pillAction(_ key: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(key).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.94))
                .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(.white.opacity(0.16)))
        }.buttonStyle(.plain)
    }

    private func cardRow(entry: FolderContentsLoader.Entry, index: Int, picked: Set<String>) -> some View {
        let path = entry.url.path, isHovered = hoveredPath == path
        let pres = ShelfCardPresentation.classify(url: entry.url, index: index, showTextExcerpt: showTextExcerpt)
        let card = ShelfFloatingCardView(entry: entry, presentation: pres, isPinned: shelfStore.isPinned(path), isSelected: picked.contains(path), isHovered: isHovered,
                                         onPin: { shelfStore.togglePin(path) },
                                         onQuickLook: { let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage"); p.arguments = ["-p", path]; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice; try? p.run() },
                                         onRemove: { shelfStore.remove(path) }) {
            let flags = NSEvent.modifierFlags
            if !picked.isEmpty || flags.contains(.command) || flags.contains(.shift) {
                if selected.contains(path) { selected.remove(path) } else { selected.insert(path) }
            } else { NSWorkspace.shared.open(entry.url); onClosePopup() }
        }
        .rotationEffect(.degrees((isHovered || reduceMotion) ? 0 : pres.tiltDegrees))
        .onHover { inside in hoveredPath = inside ? path : (hoveredPath == path ? nil : hoveredPath) }
        .floatingContextMenu { cellMenu(for: entry) }
        return Group { if entry.isAccessible { card.onDrag { FileDragItemProvider.make(for: entry.url) } } else { card } }
    }

    private func pickFilesForShelf() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseFiles = true; panel.canChooseDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, !panel.urls.isEmpty { shelfStore.stash(paths: panel.urls.map(\.path)) }
    }
    private func mergeToPDF(_ urls: [URL]) {
        Task {
            if let out = try? await Task.detached(priority: .userInitiated, operation: { try FileTransformEngine.mergePDFs(urls) }).value {
                shelfStore.stash(paths: [out.path])
            } else { NSSound.beep() }
        }
    }
    private func handleIncomingDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true; _ = p.loadObject(ofClass: URL.self) { u, _ in guard let u else { return }; DispatchQueue.main.async { shelfStore.stash(paths: [u.path]) } }
            } else if p.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                accepted = true; _ = p.loadObject(ofClass: URL.self) { u, _ in guard let u else { return }; DispatchQueue.main.async { shelfStore.stashText(u.absoluteString, suggestedName: u.host) } }
            } else if p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                accepted = true; _ = p.loadObject(ofClass: String.self) { s, _ in guard let s else { return }; DispatchQueue.main.async { shelfStore.stashText(s) } }
            }
        }
        return accepted
    }
}
private struct ShelfFloatingCardView: View {
    let entry: FolderContentsLoader.Entry; let presentation: ShelfCardPresentation
    let isPinned: Bool; let isSelected: Bool; let isHovered: Bool
    let onPin: () -> Void; let onQuickLook: () -> Void; let onRemove: () -> Void; let onTap: () -> Void
    @State private var previewImage: NSImage?; @Environment(\.displayScale) private var displayScale
    var body: some View {
        Group { if presentation.usesLightCardSurface { lightCard } else if presentation.archetype == .mediaCanvasCard { mediaCard } else { documentCard } }
        .frame(width: 280, alignment: .leading).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(isSelected ? Color.accentColor : Color.white.opacity(presentation.usesLightCardSurface ? 0.55 : 0.2), lineWidth: isSelected ? 2 : 1))
        .overlay(alignment: .bottomTrailing) { cornerBadge }
        .overlay(alignment: .topTrailing) { if isHovered || isPinned { hoverToolbar.padding(8) } }
        .shadow(color: .black.opacity(0.26), radius: 10, y: 5).contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: onTap).task(id: entry.url) { await loadPreviewIfNeeded() }
    }
    private var cornerBadge: some View {
        Image(systemName: presentation.badgeSymbol).font(.system(size: 11, weight: .bold))
            .foregroundStyle(presentation.usesLightCardSurface ? Color.black.opacity(0.85) : Color.white)
            .frame(width: 24, height: 24).background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(presentation.usesLightCardSurface ? Color.white : Color(white: 0.18).opacity(0.95)))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.black.opacity(presentation.usesLightCardSurface ? 0.12 : 0.35), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 3, y: 1).offset(x: -6, y: -6)
    }
    private var lightCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: presentation.title).font(.system(size: 12.5, weight: .bold)).foregroundStyle(Color.black.opacity(0.9)).lineLimit(1)
            Text(verbatim: presentation.excerpt ?? presentation.subtitle).font(.system(size: 11)).foregroundStyle(Color.black.opacity(0.75)).lineLimit(5)
        }.padding(.horizontal, 12).padding(.vertical, 10).padding(.trailing, 18).frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading).background(Color(white: 0.96))
    }
    private var mediaCard: some View {
        ZStack(alignment: .bottomLeading) {
            Color(white: 0.09)
            if let previewImage { Image(nsImage: previewImage).resizable().aspectRatio(contentMode: .fill).frame(width: 280, height: 118).clipped() }
            else { Image(nsImage: FolderIconResolver.resolve(entry.url.path, size: 48)).resizable().aspectRatio(contentMode: .fit).frame(width: 48, height: 48).frame(maxWidth: .infinity, maxHeight: .infinity) }
            LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
            Text(verbatim: entry.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).lineLimit(1).truncationMode(.middle).padding(.horizontal, 10).padding(.bottom, 7).padding(.trailing, 32)
        }.frame(height: 118)
    }
    private var documentCard: some View {
        HStack(spacing: 10) {
            Image(nsImage: previewImage ?? FolderIconResolver.resolve(entry.url.path, size: 42)).resizable().aspectRatio(contentMode: .fit).frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: presentation.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(2).truncationMode(.middle)
                Text(verbatim: "\(presentation.subtitle) · \(presentation.badgeText)").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 24)
        }.padding(12).frame(minHeight: 74, alignment: .leading).background(.ultraThinMaterial).background(Color(white: 0.11).opacity(0.78))
    }

    private func hoverIconButton(_ symbol: String, tint: Color = .white, help: LocalizedStringKey? = nil, action: @escaping () -> Void) -> some View {
        let btn = Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 20, height: 20).background(Circle().fill(Color.black.opacity(0.55)))
        }.buttonStyle(.plain)
        return Group { if let help { btn.help(Text(help)) } else { btn } }
    }

    private var hoverToolbar: some View {
        HStack(spacing: 4) {
            hoverIconButton(isPinned ? "pin.fill" : "pin", tint: isPinned ? .orange : .white, action: onPin)
            if isHovered {
                hoverIconButton("eye.fill", help: "Quick Look", action: onQuickLook)
                hoverIconButton("xmark", help: "Remove from Shelf", action: onRemove)
            }
        }
    }

    private func loadPreviewIfNeeded() async {
        guard entry.isAccessible, !entry.isDirectory, presentation.archetype != .richTextOrWikiCard, presentation.archetype != .chatOrSnippetCard else { return }
        if ShelfActions.isImage(entry.url), let img = NSImage(contentsOf: entry.url) { previewImage = img; return }
        let req = QLThumbnailGenerator.Request(fileAt: entry.url, size: CGSize(width: 280, height: 118), scale: max(1, displayScale), representationTypes: .thumbnail)
        let img = await withCheckedContinuation { (done: CheckedContinuation<NSImage?, Never>) in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
                done.resume(returning: rep.map { NSImage(cgImage: $0.cgImage, size: NSSize(width: 280, height: 118)) })
            }
        }
        if let img { previewImage = img }
    }
}
