import AppKit
import SwiftUI

/// Where the popup's arrow points. The coordinator owns it and rewrites it with every frame it
/// gives the popup window: once the plate is clamped at a screen edge it is no longer centred on
/// its chip, and the arrow has to stay on the chip.
@MainActor
final class StackPopupArrowModel: ObservableObject {
    /// Arrow centre minus plate centre, in points.
    @Published var offsetFromCenter: CGFloat = 0
    /// Phase 18d: beside a side rail the plate opens sideways, so the bottom arrow is dropped.
    @Published var isHidden = false
    /// Bumped by a host that outlives one showing (the drawer) each time the plate goes away:
    /// a scrolled grid is rebuilt at its top while nobody is looking, never at the next open.
    @Published var scrollGeneration = 0
    /// Bumped when the host opens the plate on the grid's **tail** rather than its top — the drawer's
    /// capsule carries the background-app count, and its click asks for exactly that section. A count,
    /// not a flag: every open that asks scrolls once, and an open that does not ask changes nothing.
    @Published var revealTailGeneration = 0
}

/// What the coordinator knows and a popup's content needs: how large the grid may get on this
/// screen, and the arrow.
struct StackPopupContext {
    let limits: StackGridLayout.Limits
    let arrow: StackPopupArrowModel
}

/// The frame shared by the folder, shelf and Trash popups, laid out like the native Dock's stack
/// grid: title row, optional status line, grid, and the plate with its arrow. Width and height are
/// derived from `layout` — never measured.
struct StackPopupChrome<Grid: View>: View {
    let title: String
    /// A line between title and grid; the native grid has none (empty shelf, Trash state).
    let note: String?
    let layout: StackGridLayout.Result
    /// The plate's frame and cells (`StackPlateMetrics`). No default: the plate's size derives from it.
    let plate: StackPlateMetrics
    let usesLiquidGlass: Bool
    @ObservedObject var arrow: StackPopupArrowModel
    /// The popup window's new size whenever the plate's changes. No default: without it the
    /// window stops following its content.
    let onPanelSizeChange: (CGSize) -> Void
    /// Non-nil shows the back button (drilled into a subfolder).
    var onBack: (() -> Void)?
    /// Animates cells arriving and leaving; nil while the first population lands.
    var gridAnimation: Animation?
    var gridAnimationKey: [String] = []
    /// Drawn over the grid area instead of cells (the shelf's first-use guide). The layout still sets the size.
    var intro: AnyView?
    /// Replaces the note line's text with a custom view (the shelf's multi-select action bar). `note` must be
    /// non-nil so the layout reserves the line.
    var noteAccessory: AnyView?
    /// Vertical space the `grid` closure spends that `layout` does not know about — the drawer's section
    /// rule (`StackSectionRuleLabel`). The plate and the grid area both grow by it, so a grid that does not
    /// scroll still shows every row. The drawer's row budget reserves the same amount
    /// (`StackGridLayout.drawerLimits`), so the taller plate still clears the top of the screen.
    var gridExtraHeight: CGFloat = 0
    /// The cells; they land in a `LazyVGrid` of `layout.columns` fixed columns.
    @ViewBuilder let grid: () -> Grid

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dockThemeStyle) private var dockThemeStyle
    private var theme: DockThemeTokens { .resolved(for: colorScheme, style: dockThemeStyle) }
    private typealias Metrics = StackPopupMetrics

    private var plateSize: CGSize {
        let base = plate.plateSize(columns: layout.columns, rows: layout.visibleRows,
                                  hasNote: note != nil, scrolls: layout.scrolls)
        return CGSize(width: base.width, height: base.height + gridExtraHeight)
    }
    private var gridWidth: CGFloat { CGFloat(layout.columns) * plate.cell.cellSize.width }
    private var gridHeight: CGFloat { CGFloat(layout.visibleRows) * plate.cell.cellSize.height }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if plate.hasSeparator { separator }
            Color.clear.frame(height: plate.gridTop - plate.headerHeight - (plate.hasSeparator ? 1 : 0))
            if let note {
                if let noteAccessory {
                    noteAccessory
                        .padding(.horizontal, plate.sidePadding)
                        .frame(width: plateSize.width, height: Metrics.noteHeight)
                } else {
                    noteLine(note)
                }
            }
            ZStack(alignment: .topLeading) {
                gridArea
                if let intro {
                    intro
                        .frame(width: gridWidth, height: gridHeight, alignment: .topLeading)
                        .padding(.leading, plate.sidePadding)
                }
            }
        }
        .frame(width: plateSize.width, height: plateSize.height, alignment: .top)
        // The plate is what the window leaves for it, not `plateSize`: while the coordinator
        // tweens the window to a new content size the plate changes with it and stays on the
        // chip. The content keeps its final layout, rides the plate's top edge and is clipped by
        // it. The ideal size is still the content's, which is what `fittingSize` reports.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .background {
            GeometryReader { proxy in
                StackPopupBackdrop(plateSize: proxy.size,
                                   arrowCenterX: arrow.isHidden ? nil : proxy.size.width / 2 + arrow.offsetFromCenter,
                                   usesLiquidGlass: usesLiquidGlass)
            }
        }
        .padding(.bottom, Metrics.arrowHeight)
        .padding(Metrics.panelMargin)
        // Only so the system scroller draws its light knob on this dark plate; nothing reads it.
        .environment(\.colorScheme, .dark)
        // Derived, not measured: `fittingSize` read inside this update returns zero.
        .onChange(of: plateSize) { onPanelSizeChange(Metrics.panelSize(forPlate: $0)) }
    }

    private var header: some View {
        Text(title)
            .font(.system(size: Metrics.titleSize))
            .foregroundStyle(theme.stackPopupText.color)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 44)
            .frame(width: plateSize.width, height: plate.headerHeight)
            .offset(y: plate.titleCenterY - plate.headerHeight / 2)
            .overlay(alignment: .topLeading) { backButton }
    }

    private var separator: some View {
        theme.stackPopupSeparator.color
            .frame(height: 1)
            .padding(.horizontal, plate.sidePadding)
            .frame(width: plateSize.width)
    }

    @ViewBuilder
    private var backButton: some View {
        if let onBack {
            Group {
                if let art = NativeStackArtwork.backButton {
                    Image(nsImage: art).blendMode(.plusLighter)
                } else {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.stackPopupText.color)
                        .frame(width: Metrics.backButtonSize.width, height: Metrics.backButtonSize.height)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(theme.stackPopupBackFill.color))
                }
            }
            .frame(width: Metrics.backButtonSize.width, height: Metrics.backButtonSize.height)
            // A 21pt target is the native size; the hit area reaches the plate's corner.
            .padding(.leading, Metrics.backButtonOrigin.x)
            .padding(.top, Metrics.backButtonOrigin.y)
            .padding([.trailing, .bottom], 6)
            .contentShape(Rectangle())
            .onTapGesture(perform: onBack)
            .help(Text("Back"))
        }
    }

    private func noteLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Metrics.labelSize))
            .foregroundStyle(theme.stackPopupNote.color)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, plate.sidePadding)
            .frame(width: plateSize.width, height: Metrics.noteHeight)
    }

    /// Scrolls the grid to its tail when the host has asked for it — a generation of zero is "no
    /// request", and one that was already consumed must not drag a later open to the bottom.
    private func scrollToTail(_ proxy: ScrollViewProxy) {
        guard arrow.revealTailGeneration > 0 else { return }
        withTransaction(Transaction(animation: nil)) {
            proxy.scrollTo(StackPopupScrollAnchor.tail, anchor: .bottom)
        }
    }

    @ViewBuilder
    private var gridArea: some View {
        let columns = Array(repeating: GridItem(.fixed(plate.cell.cellSize.width), spacing: 0), count: layout.columns)
        let cells = LazyVGrid(columns: columns, alignment: .leading, spacing: 0, content: grid)
            .frame(width: gridWidth, alignment: .leading)
            .animation(gridAnimation, value: gridAnimationKey)
        if layout.scrolls {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Flexible, not the scroll view's width: an always-shown scroller takes its width
                        // out of the content area, and wider content would be centred, sliding the grid left.
                        cells.frame(maxWidth: .infinity, alignment: .leading)
                        // Zero height, so nothing about the grid's layout moves: an anchor the host can
                        // scroll to when it opens the plate on the tail (see `revealTailGeneration`).
                        Color.clear.frame(height: 0).id(StackPopupScrollAnchor.tail)
                    }
                }
                .frame(width: gridWidth + plate.scrollerGutter,
                       height: gridHeight + gridExtraHeight + (plate.scrollsToBottomEdge ? plate.bottomPadding : 0))
                .padding(.leading, plate.sidePadding)
                .id(arrow.scrollGeneration)
                // No animation, for the same reason the drawer has none on open (owner 2026-09-04):
                // this scroll is part of that one reveal, and easing it would play a second motion.
                .onChange(of: arrow.revealTailGeneration) { _, _ in scrollToTail(proxy) }
                // A host that builds its plate while the request is already standing (no prewarm, or a
                // new row limit) gets no change event, so the appear is the other half.
                .onAppear { scrollToTail(proxy) }
            }
        } else {
            cells
                .frame(height: gridHeight + gridExtraHeight, alignment: .top)
                .padding(.leading, plate.sidePadding)
        }
    }
}

/// A ruled break between two groups of cells: a hairline across the grid and a small label under
/// it, the way the system's own panels divide one list from the next. Its height has to agree with
/// the space a host reserves (`StackPopupMetrics.sectionRuleHeight`, passed to the chrome as
/// `gridExtraHeight`), which is why both read the one constant.
struct StackSectionRuleLabel: View {
    let title: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dockThemeStyle) private var dockThemeStyle
    private var theme: DockThemeTokens { .resolved(for: colorScheme, style: dockThemeStyle) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(theme.stackPopupSeparator.color)
                .frame(height: 1)
            Spacer(minLength: 0)
            Text(title)
                .font(.system(size: StackPopupMetrics.sectionLabelSize, weight: .medium))
                .foregroundStyle(theme.stackPopupNote.color)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: StackPopupMetrics.sectionRuleHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityAddTraits(.isHeader)
    }
}

/// The grid scroller's end marker. A file-scope enum because `StackPopupChrome` is generic and
/// Swift has no static stored properties in a generic type.
private enum StackPopupScrollAnchor {
    static let tail = "stack-popup-grid-tail"
}
