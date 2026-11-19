import AppKit
import SwiftUI

/// Desktop-layer widget frame using `DockPanelBackdrop`, `dockPanelRim`, title controls, and 8-way snap resize.
struct DesktopWidgetChromeView<Content: View>: View {
    let item: DesktopWidgetItem
    var canvasTheme: DesktopCanvasThemeState = DesktopCanvasThemeState()
    var canvasBounds: CGRect = .zero
    var groupTabs: [DesktopWidgetItem] = []
    var mergeTargets: [(id: UUID, title: String)] = []
    let itemCount: Int?
    let usesLiquidGlass: Bool
    let isDropHighlighted: Bool
    let onUpdateItem: (DesktopWidgetItem) -> Void
    var onSelectTab: (UUID) -> Void = { _ in }
    var onCycleTab: (Int) -> Void = { _ in }
    var onDetachTab: (UUID) -> Void = { _ in }
    var onMergeInto: (UUID) -> Void = { _ in }
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
    var onHoverChanged: ((Bool) -> Void)? = nil
    var onCollapseCapsule: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dockThemeStyle) private var dockThemeStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isHovered = false
    @State private var isEditingTitle = false
    @State private var draftTitle = ""
    @State private var showAppearancePopover = false
    @State private var dragStartMouse: CGPoint?
    @State private var resizeStartMouse: CGPoint?
    @State private var activeResizeHandle: DesktopResizeHandle?
    @FocusState private var titleFieldFocused: Bool

    private var theme: DockThemeTokens { .resolved(for: colorScheme, style: dockThemeStyle) }
    private var isCompactWidth: Bool { item.frame.width < 165 }
    private var isTinyBox: Bool { item.frame.width < 105 || item.frame.height < 85 }
    private var headerHeight: CGFloat { isTinyBox ? 24 : 32 }
    private var effectiveMaterial: DesktopBoxMaterialStyle { item.appearance.materialOverride ?? canvasTheme.materialStyle }
    private var effectiveCornerRadius: CGFloat { item.appearance.cornerRadiusOverride ?? DockShape.panelCornerRadius }
    private var effectiveAccentColor: Color {
        guard let hex = item.appearance.accentHex, let rgb = DesktopHexColor.parse(hex) else { return .accentColor }
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    var body: some View {
        let cornerRadius = effectiveCornerRadius
        let baseCard = ZStack {
            backdropLayer(cornerRadius: cornerRadius)
            backgroundDecorationLayer(cornerRadius: cornerRadius)

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
        }
        .frame(width: item.frame.width, height: item.frame.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay { resizeHandlesOverlay }

        styledChrome(baseCard, cornerRadius: cornerRadius)
            .dockShadow(
                theme.popupShadow,
                visible: DockLiquidGlassConfiguration.stripShadowVisible(
                    usesLiquidGlass: usesLiquidGlass,
                    usesSystemVariant: DockGlassPresentation.usesSystemVariant
                )
            )
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.8), value: isDropHighlighted)
            .onHover {
                isHovered = $0
                onHoverChanged?($0)
            }
            .padding(PanelLayoutMetrics.shadowPadding)
    }

    @ViewBuilder
    private func backdropLayer(cornerRadius: CGFloat) -> some View {
        switch effectiveMaterial {
        case .inheritDock:
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
        case .frostedGlass:
            DockVisualEffectView(material: .hudWindow)
        case .tintedGlass:
            DockPanelBackdrop(
                theme: theme,
                cornerRadius: cornerRadius,
                usesLiquidGlass: usesLiquidGlass,
                matchesDockRefraction: true
            )
            .padding(1)
            effectiveAccentColor.opacity(0.16).allowsHitTesting(false)
        case .solidCard:
            let fill = colorScheme == .dark ? Color(white: 0.14, opacity: 0.96) : Color(white: 0.96, opacity: 0.96)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(fill)
        case .clearMinimal:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill((colorScheme == .dark ? Color.black : Color.white).opacity(0.08))
        }
    }

    @ViewBuilder
    private func backgroundDecorationLayer(cornerRadius: CGFloat) -> some View {
        switch item.appearance.background {
        case .materialOnly:
            EmptyView()
        case .tint(let hex, let opacity):
            if let rgb = DesktopHexColor.parse(hex) {
                Color(red: rgb.r, green: rgb.g, blue: rgb.b)
                    .opacity(opacity)
                    .allowsHitTesting(false)
            }
        case .image(let path, let opacity, let blurRadius):
            if let nsImg = DesktopAssetStore.decodedImage(
                at: path,
                maxPixelDimension: DesktopAssetKind.widgetBackground.maxPixelDimension
            ) {
                Image(nsImage: nsImg)
                    .resizable()
                    .scaledToFill()
                    .frame(width: item.frame.width, height: item.frame.height)
                    .blur(radius: blurRadius)
                    .opacity(opacity)
                    .allowsHitTesting(false)
            }
        case .panorama:
            if canvasTheme.panoramaEnabled,
               let path = canvasTheme.panoramaImagePath,
               let nsImg = DesktopAssetStore.decodedImage(
                   at: path,
                   maxPixelDimension: DesktopAssetKind.panorama.maxPixelDimension
               ),
               let slice = DesktopPanoramaEngine.slice(
                   widgetFrame: item.frame,
                   canvasBounds: canvasBounds,
                   imageSize: nsImg.size,
                   scaleMode: canvasTheme.panoramaScaleMode
               ) {
                Image(nsImage: nsImg)
                    .resizable()
                    .frame(width: slice.imageDrawSize.width, height: slice.imageDrawSize.height)
                    .blur(radius: canvasTheme.panoramaBlur)
                    .opacity(canvasTheme.panoramaOpacity)
                    .position(
                        x: slice.imageOriginInWidget.x + slice.imageDrawSize.width / 2.0,
                        y: slice.imageOriginInWidget.y + slice.imageDrawSize.height / 2.0
                    )
                    .frame(width: item.frame.width, height: item.frame.height)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func styledChrome<Card: View>(_ card: Card, cornerRadius: CGFloat) -> some View {
        switch item.appearance.borderStyle {
        case .standard:
            card.dockPanelRim(
                cornerRadius: cornerRadius,
                style: theme.panelRimStyle(highlighted: isDropHighlighted),
                lineWidth: theme.panelRimLineWidth(highlighted: isDropHighlighted),
                usesLiquidGlass: usesLiquidGlass,
                highlighted: isDropHighlighted,
                visible: true
            )
        case .glow:
            card
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(effectiveAccentColor.opacity(isDropHighlighted ? 0.95 : 0.7), lineWidth: 1.5)
                        .allowsHitTesting(false)
                )
                .shadow(color: effectiveAccentColor.opacity(0.32), radius: 8)
        case .hairline:
            card
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            isDropHighlighted ? effectiveAccentColor.opacity(0.9) : Color.primary.opacity(0.18),
                            lineWidth: isDropHighlighted ? 1.5 : 0.5
                        )
                        .allowsHitTesting(false)
                )
        case .none:
            card.dockPanelRim(
                cornerRadius: cornerRadius,
                style: theme.panelRimStyle(highlighted: isDropHighlighted),
                lineWidth: theme.panelRimLineWidth(highlighted: isDropHighlighted),
                usesLiquidGlass: usesLiquidGlass,
                highlighted: isDropHighlighted,
                visible: isDropHighlighted
            )
        }
    }

    private var kindSymbol: String {
        switch item.kind {
        case .folder: return "folder.fill"
        case .todo: return "checklist"
        case .quickCapture: return "square.and.pencil"
        case .glance: return "calendar"
        case .weather: return "cloud.sun.fill"
        case .music: return "opticaldisc.fill"
        case .search: return "magnifyingglass"
        }
    }

    @ViewBuilder
    private var headerIconView: some View {
        switch item.appearance.iconBadge {
        case .systemDefault:
            Image(systemName: kindSymbol)
                .font(.system(size: isTinyBox ? 11 : 13, weight: .medium))
                .foregroundStyle(theme.labelActive.color)
        case .emoji(let value):
            Text(verbatim: value)
                .font(.system(size: isTinyBox ? 12 : 14))
        case .sfSymbol(let name):
            Image(systemName: name)
                .font(.system(size: isTinyBox ? 11 : 13, weight: .medium))
                .foregroundStyle(effectiveAccentColor)
        case .customImage(let path):
            if let nsImg = DesktopAssetStore.decodedImage(
                at: path,
                maxPixelDimension: DesktopAssetKind.widgetIcon.maxPixelDimension
            ) {
                let side: CGFloat = isTinyBox ? 13 : 16
                Image(nsImage: nsImg)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Image(systemName: "folder.fill")
                    .font(.system(size: isTinyBox ? 11 : 13, weight: .medium))
                    .foregroundStyle(theme.labelActive.color)
            }
        }
    }

    private var titleBar: some View {
        HStack(spacing: 6) {
            headerIconView

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
                } else if groupTabs.count > 1 {
                    tabStripView
                } else {
                    Text(verbatim: item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.labelActive.color)
                        .desktopTextTreatment(item.appearance.textTreatment)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .onTapGesture(count: 2) { beginTitleEdit() }
                }

                if let itemCount, !isCompactWidth, groupTabs.count <= 1 {
                    Text(verbatim: "\(itemCount)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.labelSubtitle.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(theme.chipPillFill.normal.color))
                }
            }

            Spacer(minLength: 2)

            if !isCompactWidth && item.kind == .folder {
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

            if item.capsuleMode != .expanded {
                Button {
                    onCollapseCapsule?()
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.labelInactive.color)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Collapse to Capsule"))
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
            if item.kind == .folder {
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

            Menu(String(localized: "File Stacks")) {
                groupingButton(title: String(localized: "Flat"), mode: .none)
                groupingButton(title: String(localized: "Auto by Kind"), mode: .autoByKind)
                groupingButton(title: String(localized: "Manual Stacks"), mode: .manual)
                Divider()
                Menu(String(localized: "Popover Layout")) {
                    displayModeButton(title: String(localized: "Adaptive"), mode: .adaptive)
                    displayModeButton(title: "3×3", mode: .grid3x3)
                    displayModeButton(title: "5×5", mode: .grid5x5)
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
            }

            Divider()
            if !mergeTargets.isEmpty {
                Menu(String(localized: "Group With")) {
                    ForEach(mergeTargets, id: \.id) { target in
                        Button {
                            onMergeInto(target.id)
                        } label: {
                            Text(verbatim: target.title)
                        }
                    }
                }
            }
            if groupTabs.count > 1 {
                Button(String(localized: "Detach Tab")) { onDetachTab(item.id) }
            }
            Button(String(localized: "Customize Appearance…")) { showAppearancePopover = true }
            Divider()
            if item.capsuleMode == .expanded {
                Button(String(localized: "Collapse to Capsule")) {
                    var updated = item
                    updated.capsuleMode = .capsule
                    onUpdateItem(updated)
                }
            } else {
                Button(String(localized: "Expand to Window")) {
                    var updated = item
                    updated.capsuleMode = .expanded
                    onUpdateItem(updated)
                }
            }
            Menu(String(localized: "Dock to Screen Edge")) {
                Button(String(localized: "Floating Capsule")) {
                    var updated = item
                    updated.capsuleMode = .capsule
                    onUpdateItem(updated)
                }
                Divider()
                Button(String(localized: "Left Edge")) {
                    var updated = item
                    updated.capsuleMode = .edgeDocked(edge: .left)
                    onUpdateItem(updated)
                }
                Button(String(localized: "Right Edge")) {
                    var updated = item
                    updated.capsuleMode = .edgeDocked(edge: .right)
                    onUpdateItem(updated)
                }
                Button(String(localized: "Top Edge")) {
                    var updated = item
                    updated.capsuleMode = .edgeDocked(edge: .top)
                    onUpdateItem(updated)
                }
                Button(String(localized: "Bottom Edge")) {
                    var updated = item
                    updated.capsuleMode = .edgeDocked(edge: .bottom)
                    onUpdateItem(updated)
                }
            }
            if item.kind == .folder {
                Button(String(localized: "Show in Finder"), action: onRevealInFinder)
            }
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
        .popover(isPresented: $showAppearancePopover, arrowEdge: .trailing) {
            DesktopBoxAppearancePopover(
                item: item,
                canvasTheme: canvasTheme,
                onUpdate: onUpdateItem,
                onReset: {
                    var copy = item
                    copy.appearance = .standard
                    onUpdateItem(copy)
                }
            )
        }
        .onChange(of: showAppearancePopover) { _, isOpen in
            if isOpen { onAcquireLock(.popover) } else { onReleaseLock(.popover) }
        }
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

    private func groupingButton(title: String, mode: DesktopStackGroupingMode) -> some View {
        Button {
            var updated = item
            updated.stackGroupingMode = mode
            onUpdateItem(updated)
        } label: {
            if item.stackGroupingMode == mode {
                Label(title, systemImage: "checkmark")
            } else {
                Text(verbatim: title)
            }
        }
    }

    private func displayModeButton(title: String, mode: DesktopStackDisplayMode) -> some View {
        Button {
            var updated = item
            updated.stackDisplayMode = mode
            onUpdateItem(updated)
        } label: {
            if item.stackDisplayMode == mode {
                Label { Text(verbatim: title) } icon: { Image(systemName: "checkmark") }
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

    private var tabStripView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(groupTabs) { tab in
                    let isSelected = tab.id == item.id
                    Text(verbatim: tab.title)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? theme.labelActive.color : theme.labelInactive.color)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(isSelected ? theme.chipPillFill.normal.color : Color.clear)
                        )
                        .contentShape(Capsule())
                        .onTapGesture(count: 2) {
                            if isSelected { beginTitleEdit() } else { onSelectTab(tab.id) }
                        }
                        .onTapGesture {
                            if !isSelected { onSelectTab(tab.id) }
                        }
                        .contextMenu {
                            Button(String(localized: "Detach Tab")) { onDetachTab(tab.id) }
                            if isSelected {
                                Button(String(localized: "Remove Box"), role: .destructive, action: onRemoveBox)
                            }
                        }
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.8), value: item.id)
        }
        .overlay(DesktopTabWheelCatcher(onCycle: onCycleTab))
    }
}

private struct DesktopTabWheelCatcher: NSViewRepresentable {
    let onCycle: (Int) -> Void

    func makeNSView(context: Context) -> WheelNSView {
        let view = WheelNSView()
        view.onCycle = onCycle
        return view
    }

    func updateNSView(_ nsView: WheelNSView, context: Context) {
        nsView.onCycle = onCycle
    }

    final class WheelNSView: NSView {
        var onCycle: ((Int) -> Void)?
        private var lastCycleTimestamp: TimeInterval = 0

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func scrollWheel(with event: NSEvent) {
            let dominant = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
                ? event.scrollingDeltaX
                : event.scrollingDeltaY
            guard abs(dominant) > 1.5 else {
                super.scrollWheel(with: event)
                return
            }
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastCycleTimestamp >= 0.14 else { return }
            lastCycleTimestamp = now
            onCycle?(dominant > 0 ? 1 : -1)
        }
    }
}

extension View {
    @ViewBuilder
    func desktopTextTreatment(_ treatment: DesktopBoxTextTreatment) -> some View {
        switch treatment {
        case .auto:
            self
        case .shadowed:
            self.shadow(color: .black.opacity(0.65), radius: 2, x: 0, y: 1)
        case .highContrast:
            self.fontWeight(.semibold)
                .shadow(color: .black.opacity(0.45), radius: 1.5, x: 0, y: 0.5)
        case .monospaced:
            self.fontDesign(.monospaced)
        }
    }
}
