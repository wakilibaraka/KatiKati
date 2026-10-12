import AppKit
import SwiftUI

/// The floating chip panel's content: Winstrix-style window thumbnails (preview) or the jump list
/// (menu). The size is derived (`ChipPanelModel.plateSize`), never measured.
struct ChipPanelView: View {
    @ObservedObject var model: ChipPanelModel
    @ObservedObject var arrow: StackPopupArrowModel
    let usesLiquidGlass: Bool
    /// Called when the derived plate size changes, with the new panel window size.
    let onPanelSizeChange: (CGSize) -> Void

    @Environment(\.dockThemeStyle) private var dockThemeStyle
    private typealias Metrics = StackPopupMetrics

    var body: some View {
        let plate = model.plateSize
        ZStack(alignment: .top) {
            Group {
                switch model.mode {
                case .preview: previewBody
                case .menu: menuBody
                }
            }
            .frame(width: plate.width, height: plate.height, alignment: .top)
        }
        .frame(width: plate.width, height: plate.height, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background {
            StackPopupBackdrop(plateSize: plate,
                               arrowCenterX: plate.width / 2 + arrow.offsetFromCenter,
                               usesLiquidGlass: usesLiquidGlass)
        }
        .padding(.bottom, Metrics.arrowHeight)
        .padding(Metrics.panelMargin)
        .environment(\.colorScheme, .dark)
        .onChange(of: plate) { onPanelSizeChange(Metrics.panelSize(forPlate: $0)) }
    }

    // MARK: Preview

    private var previewBody: some View {
        let windows = model.previewWindows
        let grid = ChipPanelLayout.previewGrid(count: (model.expanded ? model.content?.allWindows.count : model.content?.ownWindows.count) ?? 0)
        let columns = Array(repeating: GridItem(.fixed(model.thumbSize.width), spacing: ChipPanelLayout.cardSpacing),
                            count: max(1, grid.columns))
        return VStack(spacing: 0) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: ChipPanelLayout.cardSpacing) {
                ForEach(windows) { window in
                    ChipPanelThumbCard(model: model, window: window)
                }
            }
            if grid.hidden > 0 {
                Text(verbatim: "+\(grid.hidden)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(height: ChipPanelLayout.titleHeight)
            }
        }
        .padding(ChipPanelLayout.plateInset)
    }

    // MARK: Menu

    private var menuBody: some View {
        let content = model.content
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let icon = content?.icon {
                    Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                }
                Text(verbatim: content?.appName ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: ChipPanelLayout.menuHeaderHeight)

            if let windows = content?.allWindows, !windows.isEmpty {
                menuSeparator
                ForEach(windows.prefix(ChipPanelModel.maxMenuWindows)) { window in
                    ChipPanelWindowRow(model: model, window: window)
                }
            }
            if let recents = content?.recents, !recents.isEmpty {
                menuSeparator
                Text("Most Used Files")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .frame(height: ChipPanelLayout.menuSectionLabelHeight, alignment: .bottom)
                ForEach(recents.prefix(ChipPanelModel.maxRecents)) { recent in
                    ChipPanelRow(title: recent.title, leading: AnyView(
                        Image(nsImage: NSWorkspace.shared.icon(forFile: recent.url.path))
                            .resizable().frame(width: 14, height: 14))) {
                        model.openRecent(recent)
                    }
                }
            }
            if let actions = content?.actions, !actions.isEmpty {
                menuSeparator
                ForEach(actions) { action in
                    ChipPanelRow(
                        title: (model.optionHeld ? action.optionTitle : nil) ?? action.title,
                        leading: AnyView(Image(systemName: action.isChecked == true ? "checkmark" : "circle")
                            .font(.system(size: 9, weight: .bold))
                            .opacity(action.isChecked == true ? 1 : 0)),
                        isDestructive: action.isDestructive
                    ) { model.runAction(action) }
                }
            }
        }
        .padding(.top, ChipPanelLayout.plateInset / 2)
    }

    private var menuSeparator: some View {
        Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
            .padding(.horizontal, 12)
            .frame(height: ChipPanelLayout.menuSeparatorHeight)
    }
}

/// One selectable row of the jump list.
private struct ChipPanelRow: View {
    let title: String
    var leading: AnyView?
    var isDestructive = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack { leading }.frame(width: 16)
            Text(verbatim: title).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .foregroundColor(isDestructive && hovered ? .white : .primary)
        .padding(.horizontal, 8)
        .frame(height: ChipPanelLayout.menuRowHeight)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(hovered ? (isDestructive ? Color.red.opacity(0.85) : Color.accentColor.opacity(0.9)) : .clear))
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture(perform: action)
    }
}

private struct ChipPanelWindowRow: View {
    @ObservedObject var model: ChipPanelModel
    let window: ChipPanelWindow
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                switch window.marker {
                case .front: Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                case .minimized: Image(systemName: "diamond").font(.system(size: 9))
                case .none: EmptyView()
                }
            }.frame(width: 16)
            Text(verbatim: window.title).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            if hovered {
                Button { model.closeWindow(window.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.white.opacity(0.18)))
                }
                .buttonStyle(.plain)
                .help(Text("Close Window"))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: ChipPanelLayout.menuRowHeight)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(hovered ? Color.accentColor.opacity(0.9) : .clear))
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { model.activateWindow(window.id) }
    }
}

/// A window card: live thumbnail (or the app icon when there is no capture), close button on hover,
/// title underneath.
private struct ChipPanelThumbCard: View {
    @ObservedObject var model: ChipPanelModel
    let window: ChipPanelWindow
    @State private var hovered = false

    var body: some View {
        let size = model.thumbSize
        VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.08))
                if let image = model.thumbnails[window.id] {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else if let icon = model.content?.icon {
                    Image(nsImage: icon).resizable().frame(width: 44, height: 44)
                        .frame(width: size.width, height: size.height)
                        .opacity(window.marker == .minimized ? 0.5 : 0.9)
                }
                if hovered {
                    Button { model.closeWindow(window.id) } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.black.opacity(0.55)))
                    }
                    .buttonStyle(.plain)
                    .padding(5)
                    .help(Text("Close Window"))
                }
            }
            .frame(width: size.width, height: size.height)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(hovered ? Color.accentColor : Color.white.opacity(0.14), lineWidth: hovered ? 2 : 1))
            HStack(spacing: 4) {
                if window.marker == .minimized { Image(systemName: "diamond").font(.system(size: 8)) }
                Text(verbatim: window.title).font(.system(size: 11)).lineLimit(1).truncationMode(.tail)
            }
            .frame(width: size.width, height: ChipPanelLayout.titleHeight - 4, alignment: .leading)
        }
        .frame(width: size.width, height: size.height + ChipPanelLayout.titleHeight)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { model.activateWindow(window.id) }
    }
}
