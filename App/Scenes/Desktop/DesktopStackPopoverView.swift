import AppKit
import SwiftUI

/// Expanded File Stack popover with Adaptive / 3x3 / 5x5 grid layouts, QuickLook, drag-out, and stack controls.
struct DesktopStackPopoverView: View {
    let stack: DesktopResolvedStack
    let displayMode: DesktopStackDisplayMode
    let directoryURL: URL
    let onChangeDisplayMode: (DesktopStackDisplayMode) -> Void
    let onRenameStack: ((UUID, String) -> Void)?
    let onUngroupStack: ((UUID) -> Void)?
    let onRemoveFromStack: ((UUID, [URL]) -> Void)?
    let onQuickLook: ([URL]) -> Void
    let onMutated: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dockThemeStyle) private var dockThemeStyle
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isEditingTitle = false
    @State private var titleDraft = ""
    @State private var permanentDeleteURLs: [URL] = []
    @State private var showPermanentDeleteConfirm = false
    @FocusState private var titleFieldFocused: Bool

    private var theme: DockThemeTokens { .resolved(for: colorScheme, style: dockThemeStyle) }

    var body: some View {
        let metrics = DesktopStackPopoverLayout.metrics(itemCount: stack.entries.count, mode: displayMode)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: metrics.columns)

        VStack(spacing: 0) {
            headerBar
            Divider().opacity(0.35)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(stack.entries, id: \.url.path) { entry in
                        stackEntryTile(entry)
                    }
                }
                .padding(12)
            }
        }
        .frame(width: metrics.size.width, height: metrics.size.height)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82), value: displayMode)
        .alert(String(localized: "Delete Permanently"), isPresented: $showPermanentDeleteConfirm) {
            Button("Delete", role: .destructive) {
                try? DesktopFileOperations.permanentlyDelete(permanentDeleteURLs)
                permanentDeleteURLs = []
                onMutated()
            }
            Button("Cancel", role: .cancel) {
                permanentDeleteURLs = []
            }
        } message: {
            Text("Move to Trash is unavailable on this volume.")
        }
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: stack.category?.symbolName ?? "square.stack.3d.up.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.labelActive.color)

            if let manualID = stack.manualStackID, isEditingTitle {
                TextField(text: $titleDraft) { EmptyView() }
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, weight: .semibold))
                    .focused($titleFieldFocused)
                    .onSubmit { commitTitleEdit(manualID: manualID) }
                    .onExitCommand { isEditingTitle = false }
            } else {
                Text(verbatim: stack.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.labelActive.color)
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        guard stack.manualStackID != nil else { return }
                        titleDraft = stack.title
                        isEditingTitle = true
                        titleFieldFocused = true
                    }
            }

            Text(verbatim: "\(stack.entries.count)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(theme.labelSubtitle.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(theme.chipPillFill.normal.color))

            Spacer(minLength: 4)

            Picker(selection: Binding(get: { displayMode }, set: { onChangeDisplayMode($0) })) {
                Text("Adaptive").tag(DesktopStackDisplayMode.adaptive)
                Text(verbatim: "3×3").tag(DesktopStackDisplayMode.grid3x3)
                Text(verbatim: "5×5").tag(DesktopStackDisplayMode.grid5x5)
            } label: { EmptyView() }
            .pickerStyle(.segmented)
            .fixedSize()

            if let manualID = stack.manualStackID {
                Button("Ungroup Stack") {
                    onUngroupStack?(manualID)
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func stackEntryTile(_ entry: FolderContentsLoader.Entry) -> some View {
        let iconSize: CGFloat = displayMode == .grid5x5 ? 36 : 42
        return VStack(spacing: 4) {
            DesktopFileIconView(entry: entry, size: iconSize, scale: displayScale)
            Text(verbatim: entry.name)
                .font(.system(size: displayMode == .grid5x5 ? 10 : 11))
                .foregroundStyle(theme.labelActive.color)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { DesktopFileOperations.open([entry.url]) }
        .onTapGesture { onQuickLook([entry.url]) }
        .onDrag { FileDragItemProvider.make(for: entry.url) }
        .overlay(NativeMenuHost(popUpHandler: { event, view in
            popEntryMenu(entry.url, event: event, in: view)
        }))
        .help(entry.name)
    }

    private func popEntryMenu(_ url: URL, event: NSEvent, in view: NSView) {
        let manualID = stack.manualStackID
        let callbacks = DesktopFileMenuCallbacks(
            onQuickLook: { onQuickLook($0) },
            onRename: { target in
                DesktopFileOperations.open([directoryURL])
                _ = target
            },
            onNewFolder: {},
            onCut: { _ in },
            onPaste: {},
            onTrash: { urls in
                switch DesktopFileOperations.moveToTrash(urls) {
                case .trashed:
                    TrashStateStore.shared.noteTrashedInApp()
                    onMutated()
                case .requiresPermanentDeleteConfirmation(let pending):
                    permanentDeleteURLs = pending
                    showPermanentDeleteConfirm = true
                case .failed:
                    NSSound.beep()
                }
            },
            onCompress: { targetURLs in
                DesktopFileOperations.compressToZip(targetURLs, in: directoryURL) { _ in onMutated() }
            },
            onExtract: { archiveURL in
                DesktopFileOperations.extractZip(archiveURL, to: directoryURL) { _ in onMutated() }
            },
            onRemoveFromManualStack: manualID.map { id in
                { urls in onRemoveFromStack?(id, urls) }
            }
        )
        let menu = DesktopFileOperations.buildContextMenu(
            for: [url],
            in: directoryURL,
            hasCutItems: false,
            callbacks: callbacks
        )
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private func commitTitleEdit(manualID: UUID) {
        onRenameStack?(manualID, titleDraft)
        isEditingTitle = false
    }
}
