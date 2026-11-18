import AppKit
import SwiftUI

/// Desktop-layer widget frame using `DockPanelBackdrop`, `dockPanelRim`, title controls, and 8-way snap resize.
struct DesktopWidgetChromeView<Content: View>: View {
    let item: DesktopWidgetItem
    let itemCount: Int?
    let usesLiquidGlass: Bool
    let isDropHighlighted: Bool
    let onUpdateItem: (DesktopWidgetItem) -> Void
    let onNewFolder: () -> Void
    let onRevealInFinder: () -> Void
    let onRemoveBox: () -> Void
    let onAcquireLock: (DesktopInteractionLock) -> Void
    let onReleaseLock: (DesktopInteractionLock) -> Void
    let onDragStarted: () -> Void
    let onDragChanged: (CGSize, Bool) -> Void
    let onDragEnded: (CGSize, Bool) -> Void
    let onResizeStarted: () -> Void
    let onResizeChanged: (DesktopResizeHandle, CGSize) -> Void
    let onResizeEnded: (DesktopResizeHandle, CGSize) -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dockThemeStyle) private var dockThemeStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isHovered = false
    @State private var isEditingTitle = false
    @State private var draftTitle = ""
    @State private var dragStartMouse: CGPoint?
    @State private var resizeStartMouse: CGPoint?
    @State private var activeResizeHandle: DesktopResizeHandle?
    @FocusState private var titleFieldFocused: Bool

    private var theme: DockThemeTokens { .resolved(for: colorScheme, style: dockThemeStyle) }
    private var isCompactWidth: Bool { item.frame.width < 165 }
    private var isTinyBox: Bool { item.frame.width < 105 || item.frame.height < 85 }
    private var headerHeight: CGFloat { isTinyBox ? 24 : 32 }

    var body: some View {
        let cornerRadius = DockShape.panelCornerRadius
        ZStack {
            DockPanelBackdrop(
                theme: theme,
                cornerRadius: cornerRadius,
                usesLiquidGlass: usesLiquidGlass,
                matchesDockRefraction: true
            )
            .padding(1)

            if theme.drawsEffectiveThickness && !usesLiquidGlass {
                theme.panelThicknessLayer(cornerRadius: cornerRadius)
            }

            VStack(spacing: 0) {
                titleBar
                if !isTinyBox {
                    Rectangle()
                        .fill(theme.zoneDivider.color)
                        .frame(height: 0.5)
                }
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .frame(width: item.frame.width, height: item.frame.height)
        .overlay { resizeHandlesOverlay }
        .dockPanelRim(
            cornerRadius: cornerRadius,
            style: theme.panelRimStyle(highlighted: isDropHighlighted),
            lineWidth: theme.panelRimLineWidth(highlighted: isDropHighlighted),
            usesLiquidGlass: usesLiquidGlass,
            highlighted: isDropHighlighted,
            visible: true
        )
        .dockShadow(
            theme.popupShadow,
            visible: DockLiquidGlassConfiguration.stripShadowVisible(
                usesLiquidGlass: usesLiquidGlass,
                usesSystemVariant: DockGlassPresentation.usesSystemVariant
            )
        )
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.8), value: isDropHighlighted)
        .onHover { isHovered = $0 }
        .padding(PanelLayoutMetrics.shadowPadding)
    }

    private var titleBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: isTinyBox ? 11 : 13, weight: .medium))
                .foregroundStyle(theme.labelActive.color)

            if !isTinyBox {
                if isEditingTitle {
                    TextField(text: $draftTitle) { EmptyView() }
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.labelActive.color)
                        .focused($titleFieldFocused)
                        .onSubmit { commitTitleEdit() }
                        .onExitCommand { cancelTitleEdit() }
                        .onChange(of: titleFieldFocused) { focused in
                            if !focused && isEditingTitle { commitTitleEdit() }
                        }
                } else {
                    Text(verbatim: item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.labelActive.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .onTapGesture(count: 2) { beginTitleEdit() }
                }

                if let itemCount, !isCompactWidth {
                    Text(verbatim: "\(itemCount)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.labelSubtitle.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(theme.chipPillFill.normal.color))
                }
            }

            Spacer(minLength: 2)

            if !isCompactWidth {
                Button {
                    var updated = item
                    updated.viewStyle = (item.viewStyle == .iconGrid) ? .compactList : .iconGrid
                    onUpdateItem(updated)
                } label: {
                    Image(systemName: item.viewStyle == .iconGrid ? "list.bullet" : "square.grid.2x2")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.labelInactive.color)
                }
                .buttonStyle(.plain)
                .help(item.viewStyle == .iconGrid ? String(localized: "List") : String(localized: "Grid"))

                Button(action: onNewFolder) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.labelInactive.color)
                }
                .buttonStyle(.plain)
                .help(String(localized: "New Folder"))
            }

            overflowMenu
        }
        .padding(.horizontal, isTinyBox ? 6 : 10)
        .frame(height: headerHeight)
        .contentShape(Rectangle())
        .gesture(titleDragGesture)
    }

    private var overflowMenu: some View {
        Menu {
            if isCompactWidth {
                Button(String(localized: "New Folder"), action: onNewFolder)
                Button(item.viewStyle == .iconGrid ? String(localized: "List") : String(localized: "Grid")) {
                    var updated = item
                    updated.viewStyle = (item.viewStyle == .iconGrid) ? .compactList : .iconGrid
                    onUpdateItem(updated)
                }
                Divider()
            }

            Menu(String(localized: "Sort By")) {
                sortButton(title: String(localized: "Manual"), mode: .manual)
                Divider()
                ForEach(FolderSortOrder.allCases, id: \.self) { order in
                    sortButton(title: order.menuTitle, mode: .rule(order))
                }
            }

            Menu(String(localized: "Icon Size")) {
                iconSizeButton(title: String(localized: "Small"), size: 32)
                iconSizeButton(title: String(localized: "Medium"), size: nil)
                iconSizeButton(title: String(localized: "Large"), size: 58)
            }

            Menu(String(localized: "Filenames")) {
                filenameLinesButton(title: String(localized: "Hidden"), lines: .hidden)
                filenameLinesButton(title: String(localized: "1 Line"), lines: .one)
                filenameLinesButton(title: String(localized: "2 Lines"), lines: .two)
            }

            Toggle(String(localized: "Compact Density"), isOn: Binding(
                get: { item.compactDensity },
                set: { val in
                    var updated = item
                    updated.compactDensity = val
                    onUpdateItem(updated)
                }
            ))

            Divider()
            Button(String(localized: "Show in Finder"), action: onRevealInFinder)
            Button(String(localized: "Remove Box"), role: .destructive, action: onRemoveBox)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: isTinyBox ? 11 : 12, weight: .medium))
                .foregroundStyle(theme.labelInactive.color)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text("More Options"))
    }

    private func sortButton(title: String, mode: DesktopSortMode) -> some View {
        Button {
            var updated = item
            updated.sortMode = mode
            onUpdateItem(updated)
        } label: {
            if item.sortMode == mode {
                Label(title, systemImage: "checkmark")
            } else {
                Text(verbatim: title)
            }
        }
    }

    private func iconSizeButton(title: String, size: CGFloat?) -> some View {
        Button {
            var updated = item
            updated.iconSizeOverride = size
            onUpdateItem(updated)
        } label: {
            if item.iconSizeOverride == size {
                Label(title, systemImage: "checkmark")
            } else {
                Text(verbatim: title)
            }
        }
    }

    private func filenameLinesButton(title: String, lines: DesktopFilenameLines) -> some View {
        Button {
            var updated = item
            updated.filenameLines = lines
            onUpdateItem(updated)
        } label: {
            if item.filenameLines == lines {
                Label(title, systemImage: "checkmark")
            } else {
                Text(verbatim: title)
            }
        }
    }

    private var titleDragGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { _ in
                let mouse = NSEvent.mouseLocation
                if dragStartMouse == nil {
                    dragStartMouse = mouse
                    onAcquireLock(.drag)
                    onDragStarted()
                }
                let start = dragStartMouse ?? mouse
                let delta = CGSize(width: mouse.x - start.x, height: mouse.y - start.y)
                onDragChanged(delta, NSEvent.modifierFlags.contains(.control))
            }
            .onEnded { _ in
                let mouse = NSEvent.mouseLocation
                let start = dragStartMouse ?? mouse
                let delta = CGSize(width: mouse.x - start.x, height: mouse.y - start.y)
                dragStartMouse = nil
                onDragEnded(delta, NSEvent.modifierFlags.contains(.control))
                onReleaseLock(.drag)
            }
    }

    @ViewBuilder
    private var resizeHandlesOverlay: some View {
        let edge: CGFloat = 6
        let corner: CGFloat = 12
        ZStack {
            // Edges
            resizeZone(.top).frame(height: edge).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.horizontal, corner)
            resizeZone(.bottom).frame(height: edge).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(.horizontal, corner)
            resizeZone(.left).frame(width: edge).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding(.vertical, corner)
            resizeZone(.right).frame(width: edge).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing).padding(.vertical, corner)
            // Corners
            resizeZone(.topLeft).frame(width: corner, height: corner).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            resizeZone(.topRight).frame(width: corner, height: corner).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            resizeZone(.bottomLeft).frame(width: corner, height: corner).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            resizeZone(.bottomRight).frame(width: corner, height: corner).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .opacity(isHovered || activeResizeHandle != nil ? 1 : 0.001)
    }

    private func resizeZone(_ handle: DesktopResizeHandle) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { _ in
                        let mouse = NSEvent.mouseLocation
                        if resizeStartMouse == nil {
                            resizeStartMouse = mouse
                            activeResizeHandle = handle
                            onAcquireLock(.drag)
                            onResizeStarted()
                        }
                        let start = resizeStartMouse ?? mouse
                        onResizeChanged(handle, CGSize(width: mouse.x - start.x, height: mouse.y - start.y))
                    }
                    .onEnded { _ in
                        let mouse = NSEvent.mouseLocation
                        let start = resizeStartMouse ?? mouse
                        let delta = CGSize(width: mouse.x - start.x, height: mouse.y - start.y)
                        resizeStartMouse = nil
                        activeResizeHandle = nil
                        onResizeEnded(handle, delta)
                        onReleaseLock(.drag)
                    }
            )
    }

    private func beginTitleEdit() {
        draftTitle = item.title
        isEditingTitle = true
        onAcquireLock(.inlineRename)
        titleFieldFocused = true
    }

    private func commitTitleEdit() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != item.title {
            var updated = item
            updated.title = trimmed
            onUpdateItem(updated)
        }
        isEditingTitle = false
        onReleaseLock(.inlineRename)
    }

    private func cancelTitleEdit() {
        isEditingTitle = false
        onReleaseLock(.inlineRename)
    }
}
