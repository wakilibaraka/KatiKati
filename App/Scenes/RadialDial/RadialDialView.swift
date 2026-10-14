import SwiftUI

/// Top-level interactive radial dial view (Phase 31b).
struct RadialDialView: View {
    let pages: [RadialDialPage]
    @Binding var currentPageIndex: Int
    let theme: RadialDialTheme
    let onSelectAction: (RadialDialActionType) -> Void
    let onDismiss: () -> Void

    @State private var hoveredSector: Int?
    @State private var isCenterHovered = false
    @State private var isAppearing = false

    private let dialSize: CGFloat = 340
    private let outerRadius: CGFloat = 160
    private let innerRadius: CGFloat = 48

    private var center: CGPoint {
        CGPoint(x: dialSize / 2, y: dialSize / 2)
    }

    private var currentPage: RadialDialPage {
        guard !pages.isEmpty else {
            return RadialDialPage(id: .main, title: "main", items: [])
        }
        let safeIndex = min(max(currentPageIndex, 0), pages.count - 1)
        return pages[safeIndex]
    }

    var body: some View {
        ZStack {
            // Backdrop translucent circle
            Circle()
                .fill(backdropFill)
                .frame(width: outerRadius * 2, height: outerRadius * 2)
                .overlay(
                    Circle()
                        .strokeBorder(outerBorderColor, lineWidth: 1.5)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 16, x: 0, y: 8)

            // Wedges
            let sectors = RadialDialGeometry.sectors(
                count: currentPage.items.count,
                innerRadius: innerRadius,
                outerRadius: outerRadius
            )

            ForEach(Array(currentPage.items.enumerated()), id: \.element.id) { index, item in
                if index < sectors.count {
                    RadialDialWedgeView(
                        sector: sectors[index],
                        item: item,
                        isHovered: hoveredSector == index,
                        theme: theme,
                        center: center,
                        onSelect: {
                            selectItem(item)
                        }
                    )
                }
            }

            // Center hub
            RadialDialCenterHub(
                title: currentPage.title,
                pageCount: pages.count,
                pageIndex: currentPageIndex,
                centerItem: currentPage.centerItem,
                isHovered: isCenterHovered,
                theme: theme,
                onPreviousPage: previousPage,
                onNextPage: nextPage,
                onCenterAction: {
                    if let centerItem = currentPage.centerItem {
                        selectItem(centerItem)
                    }
                }
            )
        }
        .frame(width: dialSize, height: dialSize)
        .scaleEffect(isAppearing ? 1.0 : 0.78)
        .opacity(isAppearing ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                isAppearing = true
            }
        }
        // Continuous mouse coordinate tracking via DragGesture(minimumDistance: 0) (compatible with macOS 12+)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    handlePointerMove(at: value.location)
                }
                .onEnded { value in
                    handlePointerUp(at: value.location)
                }
        )
    }

    private func handlePointerMove(at point: CGPoint) {
        let result = RadialDialGeometry.hitTest(
            point: point,
            center: center,
            count: currentPage.items.count,
            innerRadius: innerRadius,
            outerRadius: outerRadius
        )

        switch result {
        case .center:
            hoveredSector = nil
            isCenterHovered = true
        case .sector(let idx):
            hoveredSector = idx
            isCenterHovered = false
        case .outside:
            hoveredSector = nil
            isCenterHovered = false
        }
        updateSnapPreview()
    }

    private func updateSnapPreview() {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else {
            RadialSnapPreviewPanelController.shared.hidePreview()
            return
        }

        if isCenterHovered, let centerItem = currentPage.centerItem, case .snap(let pos) = centerItem.action {
            RadialSnapPreviewPanelController.shared.showPreview(for: pos, on: screen, theme: theme)
        } else if let idx = hoveredSector, idx < currentPage.items.count, case .snap(let pos) = currentPage.items[idx].action {
            RadialSnapPreviewPanelController.shared.showPreview(for: pos, on: screen, theme: theme)
        } else {
            RadialSnapPreviewPanelController.shared.hidePreview()
        }
    }

    private func handlePointerUp(at point: CGPoint) {
        RadialSnapPreviewPanelController.shared.hidePreview()
        let result = RadialDialGeometry.hitTest(
            point: point,
            center: center,
            count: currentPage.items.count,
            innerRadius: innerRadius,
            outerRadius: outerRadius
        )

        switch result {
        case .center:
            if let centerItem = currentPage.centerItem {
                selectItem(centerItem)
            }
        case .sector(let idx):
            if idx < currentPage.items.count {
                selectItem(currentPage.items[idx])
            }
        case .outside:
            break
        }
    }

    private func selectItem(_ item: RadialDialItem) {
        RadialSnapPreviewPanelController.shared.hidePreview()
        switch item.action {
        case .page(let pageID):
            if let targetIdx = pages.firstIndex(where: { $0.id == pageID }) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
                    currentPageIndex = targetIdx
                    hoveredSector = nil
                    isCenterHovered = false
                }
            }
        default:
            onSelectAction(item.action)
        }
    }

    private func previousPage() {
        RadialSnapPreviewPanelController.shared.hidePreview()
        guard !pages.isEmpty else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
            currentPageIndex = (currentPageIndex - 1 + pages.count) % pages.count
            hoveredSector = nil
            isCenterHovered = false
        }
    }

    private func nextPage() {
        RadialSnapPreviewPanelController.shared.hidePreview()
        guard !pages.isEmpty else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
            currentPageIndex = (currentPageIndex + 1) % pages.count
            hoveredSector = nil
            isCenterHovered = false
        }
    }

    private var backdropFill: some ShapeStyle {
        switch theme {
        case .lilacGlass:
            return AnyShapeStyle(
                Color(red: 0.16, green: 0.14, blue: 0.24).opacity(0.85)
            )
        case .darkObsidian:
            return AnyShapeStyle(
                Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.90)
            )
        case .systemFrosted:
            return AnyShapeStyle(
                Color.black.opacity(0.65)
            )
        case .neonCyber:
            return AnyShapeStyle(
                Color(red: 0.04, green: 0.05, blue: 0.10).opacity(0.92)
            )
        }
    }

    private var outerBorderColor: Color {
        switch theme {
        case .lilacGlass:
            return Color(red: 0.65, green: 0.55, blue: 0.95).opacity(0.35)
        case .darkObsidian:
            return Color.white.opacity(0.18)
        case .systemFrosted:
            return Color.white.opacity(0.25)
        case .neonCyber:
            return Color(red: 0.0, green: 0.85, blue: 0.95).opacity(0.6)
        }
    }
}
