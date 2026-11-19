import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// File organizer content for a real-folder desktop box (Icon Grid, Compact List, D&D, QuickLook, native NSMenu).
struct DesktopFolderBoxView: View {
    let item: DesktopWidgetItem
    @ObservedObject var model: DesktopFolderBoxModel
    let onUpdateItem: (DesktopWidgetItem) -> Void
    let onQuickLook: ([URL]) -> Void
    let onAcquireLock: (DesktopInteractionLock) -> Void
    let onReleaseLock: (DesktopInteractionLock) -> Void
    let onDropTargetedChanged: (Bool) -> Void
    @Binding var createNewFolderTrigger: Int

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dockThemeStyle) private var dockThemeStyle
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var anchorSelectionPath: String?
    @State private var draggingFilename: String?
    @State private var renamingPath: String?
    @State private var renameDraft = ""
    @State private var pendingScrollPath: String?
    @State private var openStackID: String?
    @State private var hoveredStackID: String?
    @State private var permanentDeleteURLs: [URL] = []
    @State private var showPermanentDeleteConfirm = false
    @FocusState private var renameFieldFocused: Bool

    private var theme: DockThemeTokens { .resolved(for: colorScheme, style: dockThemeStyle) }
    private var iconSide: CGFloat { item.iconSizeOverride ?? DesktopCanvasConfig.defaultIconSize }
    private var isTinyBox: Bool { item.frame.width < 105 || item.frame.height < 85 }
    private var directoryURL: URL { URL(fileURLWithPath: model.backingPath, isDirectory: true) }

    var body: some View {
        Group {
            switch model.loadState {
            case .loading:
                statusPlaceholder(symbol: "hourglass", title: String(localized: "Loading…"))
            case .needsPermission:
                VStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: isTinyBox ? 16 : 22))
                        .foregroundStyle(theme.labelInactive.color)
                    if !isTinyBox {
                        Text("Folder access is required to display files.")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.labelSubtitle.color)
                            .multilineTextAlignment(.center)
                    }
                    Button("Grant Access") { model.requestFolderAccessViaOpenPanel() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .padding(8)
            case .volumeUnavailable(let path):
                VStack(spacing: 6) {
                    Image(systemName: "externaldrive.badge.xmark")
                        .font(.system(size: isTinyBox ? 16 : 22))
                        .foregroundStyle(theme.labelInactive.color)
                    if !isTinyBox {
                        Text("Volume Unavailable")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.labelActive.color)
                        Text(verbatim: path)
                            .font(.system(size: 10))
                            .foregroundStyle(theme.labelSubtitle.color)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        Text("Reconnect the drive to resume.")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.labelSubtitle.color)
                    }
                }
                .padding(8)
            case .error(let msg):
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: isTinyBox ? 16 : 20))
                        .foregroundStyle(theme.labelInactive.color)
                    if !isTinyBox {
                        Text("Can’t read this folder")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.labelActive.color)
                        Text(verbatim: msg)
                            .font(.system(size: 10))
                            .foregroundStyle(theme.labelSubtitle.color)
                            .lineLimit(2)
                    }
                }
                .padding(8)
            case .loaded(let entries):
                loadedContent(entries)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: Binding(
            get: { false },
            set: { onDropTargetedChanged($0) }
        )) { providers in
            handleExternalDrop(providers, into: directoryURL)
        }
        .onChange(of: createNewFolderTrigger) { _ in
            createNewFolderInline()
        }
        .onChange(of: showPermanentDeleteConfirm) { shown in
            if shown { onAcquireLock(.confirmDialog) } else { onReleaseLock(.confirmDialog) }
        }
        .alert(String(localized: "Delete Permanently"), isPresented: $showPermanentDeleteConfirm) {
            Button("Delete", role: .destructive) {
                try? DesktopFileOperations.permanentlyDelete(permanentDeleteURLs)
                permanentDeleteURLs = []
                model.reload()
            }
            Button("Cancel", role: .cancel) {
                permanentDeleteURLs = []
            }
        } message: {
            Text("Move to Trash is unavailable on this volume.")
        }
    }

    @ViewBuilder
    private func loadedContent(_ entries: [FolderContentsLoader.Entry]) -> some View {
        let cells = DesktopStackProjection.project(
            entries: entries,
            mode: item.stackGroupingMode,
            manualStacks: item.manualStacks
        )
        let activeStack: DesktopResolvedStack? = cells.compactMap {
            if case .stack(let s) = $0 { return s } else { return nil }
        }.first { $0.id == openStackID }

        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    model.selectedPaths.removeAll()
                    commitRenameIfNeeded()
                }
                .overlay(NativeMenuHost(popUpHandler: { event, view in
                    popMenu(urls: [], event: event, in: view, entries: entries)
                }))

            if entries.isEmpty {
                statusPlaceholder(symbol: "tray", title: String(localized: "Drop files here"))
                    .allowsHitTesting(false)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        if item.viewStyle == .iconGrid {
                            let spacing: CGFloat = item.compactDensity ? 4 : 8
                            let colWidth = max(42, iconSide + (item.compactDensity ? 14 : 24))
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: colWidth), spacing: spacing, alignment: .top)],
                                spacing: spacing
                            ) {
                                ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                                    switch cell {
                                    case .file(let entry):
                                        tileView(entry: entry, index: index, entries: entries)
                                            .id(cell.id)
                                    case .stack(let stack):
                                        stackTileView(stack)
                                            .id(cell.id)
                                    }
                                }
                            }
                            .padding(item.compactDensity ? 6 : 10)
                        } else {
                            LazyVStack(spacing: item.compactDensity ? 1 : 3) {
                                ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                                    switch cell {
                                    case .file(let entry):
                                        listRowView(entry: entry, index: index, entries: entries)
                                            .id(cell.id)
                                    case .stack(let stack):
                                        stackListRowView(stack)
                                            .id(cell.id)
                                    }
                                }
                            }
                            .padding(item.compactDensity ? 6 : 8)
                        }
                    }
                    .onChange(of: entries.count) { _ in
                        if let path = pendingScrollPath, entries.contains(where: { $0.url.path == path }) {
                            proxy.scrollTo("file:\(path)", anchor: .center)
                            pendingScrollPath = nil
                        }
                    }
                }
            }
        }
        .popover(isPresented: Binding(
            get: { activeStack != nil },
            set: { shown in if !shown { openStackID = nil } }
        )) {
            if let stack = activeStack {
                DesktopStackPopoverView(
                    stack: stack,
                    displayMode: item.stackDisplayMode,
                    directoryURL: directoryURL,
                    onChangeDisplayMode: { mode in
                        var updated = item
                        updated.stackDisplayMode = mode
                        onUpdateItem(updated)
                    },
                    onRenameStack: { id, title in
                        var updated = item
                        updated.manualStacks = DesktopStackProjection.rename(stackID: id, to: title, in: item.manualStacks)
                        onUpdateItem(updated)
                    },
                    onUngroupStack: { id in
                        var updated = item
                        updated.manualStacks = DesktopStackProjection.ungroup(stackID: id, in: item.manualStacks)
                        onUpdateItem(updated)
                        openStackID = nil
                    },
                    onRemoveFromStack: { id, targetURLs in
                        var updated = item
                        let names = targetURLs.map(\.lastPathComponent)
                        updated.manualStacks = DesktopStackProjection.removeFiles(names, fromStackID: id, in: item.manualStacks)
                        onUpdateItem(updated)
                    },
                    onQuickLook: onQuickLook,
                    onMutated: { model.reload() },
                    onDismiss: { openStackID = nil }
                )
                .environment(\.dockThemeStyle, dockThemeStyle)
            }
        }
        .onChange(of: openStackID) { next in
            if next != nil { onAcquireLock(.popover) } else { onReleaseLock(.popover) }
        }
    }

    private func stackTileView(_ stack: DesktopResolvedStack) -> some View {
        let previews = Array(stack.entries.prefix(4))
        let miniSize = max(14, iconSide * 0.42)
        let cardSide = max(38, iconSide)
        return VStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.chipPillFill.normal.color)
                    .overlay(
                        LazyVGrid(columns: [GridItem(.fixed(miniSize), spacing: 2), GridItem(.fixed(miniSize), spacing: 2)], spacing: 2) {
                            ForEach(previews, id: \.url.path) { entry in
                                DesktopFileIconView(entry: entry, size: miniSize, scale: displayScale)
                            }
                        }
                        .padding(4)
                    )
                    .frame(width: cardSide, height: cardSide)

                Text(verbatim: "\(stack.entries.count)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.labelActive.color)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .offset(x: 3, y: 3)
            }

            if item.filenameLines != .hidden {
                Text(verbatim: stack.title)
                    .font(.system(size: item.compactDensity ? 10 : 11, weight: .medium))
                    .foregroundStyle(theme.labelActive.color)
                    .lineLimit(item.filenameLines.rawValue)
                    .multilineTextAlignment(.center)
                    .truncationMode(.tail)
            }
        }
        .padding(item.compactDensity ? 4 : 6)
        .frame(maxWidth: .infinity)
        .scaleEffect(hoveredStackID == stack.id ? 1.03 : 1.0)
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.65), value: hoveredStackID == stack.id)
        .contentShape(Rectangle())
        .onHover { hovered in
            hoveredStackID = hovered ? stack.id : (hoveredStackID == stack.id ? nil : hoveredStackID)
        }
        .onTapGesture { openStackID = stack.id }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDropOntoStack(providers, stack: stack)
        }
        .help(stack.title)
    }

    private func stackListRowView(_ stack: DesktopResolvedStack) -> some View {
        HStack(spacing: 8) {
            Image(systemName: stack.category?.symbolName ?? "square.stack.3d.up.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.labelActive.color)
            Text(verbatim: stack.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.labelActive.color)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(verbatim: "\(stack.entries.count)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(theme.labelSubtitle.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, item.compactDensity ? 3 : 5)
        .contentShape(Rectangle())
        .onTapGesture { openStackID = stack.id }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDropOntoStack(providers, stack: stack)
        }
    }

    private func tileView(entry: FolderContentsLoader.Entry, index: Int, entries: [FolderContentsLoader.Entry]) -> some View {
        let path = entry.url.path
        let isSelected = model.selectedPaths.contains(path)
        let lines = item.filenameLines.rawValue
        return VStack(spacing: 4) {
            DesktopFileIconView(entry: entry, size: iconSide, scale: displayScale)
            if lines > 0 {
                if renamingPath == path {
                    inlineRenameField(for: entry.url)
                } else {
                    Text(verbatim: entry.name)
                        .font(.system(size: item.compactDensity ? 10 : 11))
                        .foregroundStyle(theme.labelActive.color)
                        .lineLimit(lines)
                        .multilineTextAlignment(.center)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(item.compactDensity ? 4 : 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.28) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { DesktopFileOperations.open([entry.url]) }
        .onTapGesture { selectEntry(path: path, index: index, entries: entries) }
        .onDrag {
            draggingFilename = entry.url.lastPathComponent
            return FileDragItemProvider.make(for: entry.url)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleTileDrop(providers, onto: entry, targetIndex: index, entries: entries)
        }
        .overlay(NativeMenuHost(popUpHandler: { event, view in
            if !model.selectedPaths.contains(path) {
                model.selectedPaths = [path]
                anchorSelectionPath = path
            }
            let urls = entries.filter { model.selectedPaths.contains($0.url.path) }.map(\.url)
            popMenu(urls: urls, event: event, in: view, entries: entries)
        }))
        .help(entry.name)
    }

    private func listRowView(entry: FolderContentsLoader.Entry, index: Int, entries: [FolderContentsLoader.Entry]) -> some View {
        let path = entry.url.path
        let isSelected = model.selectedPaths.contains(path)
        let rowIcon = max(16, min(28, iconSide * 0.5))
        return HStack(spacing: 8) {
            DesktopFileIconView(entry: entry, size: rowIcon, scale: displayScale)
            if renamingPath == path {
                inlineRenameField(for: entry.url)
            } else if item.filenameLines != .hidden {
                Text(verbatim: entry.name)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.labelActive.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, item.compactDensity ? 3 : 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.28) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { DesktopFileOperations.open([entry.url]) }
        .onTapGesture { selectEntry(path: path, index: index, entries: entries) }
        .onDrag {
            draggingFilename = entry.url.lastPathComponent
            return FileDragItemProvider.make(for: entry.url)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleTileDrop(providers, onto: entry, targetIndex: index, entries: entries)
        }
        .overlay(NativeMenuHost(popUpHandler: { event, view in
            if !model.selectedPaths.contains(path) {
                model.selectedPaths = [path]
                anchorSelectionPath = path
            }
            let urls = entries.filter { model.selectedPaths.contains($0.url.path) }.map(\.url)
            popMenu(urls: urls, event: event, in: view, entries: entries)
        }))
        .help(entry.name)
    }

    private func inlineRenameField(for url: URL) -> some View {
        TextField(text: $renameDraft) { EmptyView() }
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11))
            .focused($renameFieldFocused)
            .onSubmit { commitRename(at: url) }
            .onExitCommand { cancelRename() }
            .onChange(of: renameFieldFocused) { focused in
                if !focused && renamingPath == url.path { commitRename(at: url) }
            }
    }

    private func statusPlaceholder(symbol: String, title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: isTinyBox ? 16 : 20))
                .foregroundStyle(theme.labelInactive.color)
            if !isTinyBox {
                Text(verbatim: title)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.labelSubtitle.color)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(8)
    }

    private func selectEntry(path: String, index: Int, entries: [FolderContentsLoader.Entry]) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if model.selectedPaths.contains(path) { model.selectedPaths.remove(path) }
            else { model.selectedPaths.insert(path) }
            anchorSelectionPath = path
        } else if flags.contains(.shift),
                  let anchor = anchorSelectionPath,
                  let anchorIdx = entries.firstIndex(where: { $0.url.path == anchor }) {
            let range = min(anchorIdx, index)...max(anchorIdx, index)
            model.selectedPaths.formUnion(range.map { entries[$0].url.path })
        } else {
            model.selectedPaths = [path]
            anchorSelectionPath = path
        }
    }

    private func popMenu(urls: [URL], event: NSEvent, in view: NSView, entries: [FolderContentsLoader.Entry]) {
        let callbacks = DesktopFileMenuCallbacks(
            onQuickLook: { onQuickLook($0) },
            onRename: { beginRename(at: $0) },
            onNewFolder: { createNewFolderInline() },
            onCut: { model.cutURLs = $0 },
            onPaste: { pasteIntoCurrentFolder() },
            onTrash: { trashItems($0) },
            onCompress: { targetURLs in
                DesktopFileOperations.compressToZip(targetURLs, in: directoryURL) { _ in model.reload() }
            },
            onExtract: { archiveURL in
                DesktopFileOperations.extractZip(archiveURL, to: directoryURL) { _ in model.reload() }
            },
            onGroupIntoStack: { targetURLs in
                groupURLsIntoManualStack(targetURLs)
            },
            manualStackTargets: item.manualStacks.map { ($0.id, $0.title) },
            onAddToManualStack: { stackID, targetURLs in
                addURLsToManualStack(targetURLs, stackID: stackID)
            }
        )
        let menu = DesktopFileOperations.buildContextMenu(
            for: urls,
            in: directoryURL,
            hasCutItems: !model.cutURLs.isEmpty,
            callbacks: callbacks
        )
        onAcquireLock(.contextMenu)
        NSMenu.popUpContextMenu(menu, with: event, for: view)
        onReleaseLock(.contextMenu)
    }

    private func createNewFolderInline() {
        guard let created = try? DesktopFileOperations.createNewFolder(in: directoryURL) else { return }
        pendingScrollPath = created.path
        model.reload()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            beginRename(at: created)
        }
    }

    private func beginRename(at url: URL) {
        renameDraft = url.lastPathComponent
        renamingPath = url.path
        onAcquireLock(.inlineRename)
        renameFieldFocused = true
    }

    private func commitRenameIfNeeded() {
        guard let path = renamingPath else { return }
        commitRename(at: URL(fileURLWithPath: path))
    }

    private func commitRename(at url: URL) {
        _ = try? DesktopFileOperations.renameItem(at: url, to: renameDraft)
        renamingPath = nil
        onReleaseLock(.inlineRename)
        model.reload()
    }

    private func cancelRename() {
        renamingPath = nil
        onReleaseLock(.inlineRename)
    }

    private func pasteIntoCurrentFolder() {
        if !model.cutURLs.isEmpty {
            _ = try? DesktopFileOperations.importFiles(model.cutURLs, into: directoryURL, forceMove: true)
            model.cutURLs.removeAll()
        } else {
            let urls = DesktopFileOperations.readPasteboardURLs()
            _ = try? DesktopFileOperations.importFiles(urls, into: directoryURL, forceCopy: true)
        }
        model.reload()
    }

    private func trashItems(_ urls: [URL]) {
        switch DesktopFileOperations.moveToTrash(urls) {
        case .trashed:
            model.noteTrashedInApp()
            model.reload()
        case .requiresPermanentDeleteConfirmation(let pending):
            permanentDeleteURLs = pending
            showPermanentDeleteConfirm = true
        case .failed:
            NSSound.beep()
        }
    }

    private func handleTileDrop(
        _ providers: [NSItemProvider],
        onto entry: FolderContentsLoader.Entry,
        targetIndex: Int,
        entries: [FolderContentsLoader.Entry]
    ) -> Bool {
        if item.sortMode == .manual, let dragged = draggingFilename {
            draggingFilename = nil
            let currentNames = entries.map(\.url.lastPathComponent)
            let selectedNames = Set(model.selectedPaths.map { URL(fileURLWithPath: $0).lastPathComponent })
            let moving = selectedNames.contains(dragged) ? currentNames.filter { selectedNames.contains($0) } : [dragged]
            var updated = item
            updated.manualOrder = DesktopFolderOrdering.reorder(manualOrder: currentNames, moving: moving, toIndex: targetIndex)
            onUpdateItem(updated)
            return true
        }
        if entry.url.pathExtension.lowercased() == "app" {
            extractDroppedURLs(from: providers) { urls in
                DesktopFileOperations.open(urls, withApplication: entry.url)
            }
            return true
        }
        if entry.isDirectory {
            return handleExternalDrop(providers, into: entry.url)
        }
        return handleExternalDrop(providers, into: directoryURL)
    }

    private func handleExternalDrop(_ providers: [NSItemProvider], into destination: URL) -> Bool {
        draggingFilename = nil
        let flags = NSEvent.modifierFlags
        let forceCopy = flags.contains(.option)
        let forceMove = flags.contains(.command)
        extractDroppedURLs(from: providers) { urls in
            _ = try? DesktopFileOperations.importFiles(urls, into: destination, forceCopy: forceCopy, forceMove: forceMove)
            model.reload()
        }
        return !providers.isEmpty
    }

    private func extractDroppedURLs(from providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { raw, _ in
                let parsed: URL? = (raw as? URL) ?? (raw as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                if let parsed {
                    lock.lock()
                    urls.append(parsed)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            Task { @MainActor in
                if !urls.isEmpty { completion(urls) }
            }
        }
    }

    private func groupURLsIntoManualStack(_ urls: [URL]) {
        let names = urls.map(\.lastPathComponent)
        var updated = item
        updated.manualStacks = DesktopStackProjection.createStack(title: "", filenames: names, in: item.manualStacks)
        updated.stackGroupingMode = .manual
        onUpdateItem(updated)
    }

    private func addURLsToManualStack(_ urls: [URL], stackID: UUID) {
        let names = urls.map(\.lastPathComponent)
        var updated = item
        updated.manualStacks = DesktopStackProjection.addFiles(names, toStackID: stackID, in: item.manualStacks)
        updated.stackGroupingMode = .manual
        onUpdateItem(updated)
    }

    private func handleDropOntoStack(_ providers: [NSItemProvider], stack: DesktopResolvedStack) -> Bool {
        if let manualID = stack.manualStackID, let dragged = draggingFilename {
            draggingFilename = nil
            var updated = item
            updated.manualStacks = DesktopStackProjection.addFiles([dragged], toStackID: manualID, in: item.manualStacks)
            updated.stackGroupingMode = .manual
            onUpdateItem(updated)
            return true
        }
        guard let manualID = stack.manualStackID else {
            return handleExternalDrop(providers, into: directoryURL)
        }
        extractDroppedURLs(from: providers) { urls in
            let imported = (try? DesktopFileOperations.importFiles(urls, into: directoryURL)) ?? urls
            addURLsToManualStack(imported, stackID: manualID)
            model.reload()
        }
        return !providers.isEmpty
    }
}

struct DesktopFileIconView: View {
    let entry: FolderContentsLoader.Entry
    let size: CGFloat
    let scale: CGFloat

    @State private var thumbnail: NSImage?

    var body: some View {
        let fallback = DesktopThumbnailCache.icon(for: entry.url.path, size: size)
        Image(nsImage: thumbnail ?? fallback)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .task(id: "\(entry.url.path)|\(entry.dateModified?.timeIntervalSinceReferenceDate ?? 0)|\(Int(size))|\(Int(scale))") {
                if let cached = DesktopThumbnailCache.cachedThumbnail(
                    path: entry.url.path, modified: entry.dateModified, size: size, scale: scale
                ) {
                    thumbnail = cached
                } else if !entry.isDirectory {
                    thumbnail = await DesktopThumbnailCache.loadThumbnail(
                        path: entry.url.path, modified: entry.dateModified, size: size, scale: scale
                    )
                }
            }
    }
}
