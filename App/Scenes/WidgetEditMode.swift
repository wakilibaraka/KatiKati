import SwiftUI

/// Phase 10a-4: "Edit Widgets" mode on the strip. While on, every widget (except Apps) wears a small control
/// overlay — move left, done, move right — and can be dragged sideways to reorder. No global monitors: it ends
/// from the ✓ button or the widget menu.
@MainActor
final class WidgetEditMode: ObservableObject {
    static let shared = WidgetEditMode()
    @Published private(set) var isEditing = false

    func toggle() { isEditing.toggle() }
    func end() { isEditing = false }
}

struct WidgetEditOverlay: View {
    let section: BarSection
    let width: CGFloat
    var isVertical = false
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @ObservedObject private var editMode = WidgetEditMode.shared
    @State private var dragOffset: CGFloat = 0
    private var compact: Bool { isVertical || width < 90 }

    var body: some View {
        let prevSymbol = isVertical ? "chevron.up" : "chevron.left"
        let nextSymbol = isVertical ? "chevron.down" : "chevron.right"
        let controls = Group {
            button(prevSymbol) { move(by: -1) }
            if !compact { button("checkmark") { editMode.end() } }
            button(nextSymbol) { move(by: 1) }
        }
        Group {
            if isVertical {
                VStack(spacing: 0) { controls }
            } else {
                HStack(spacing: compact ? 0 : 6) { controls }
                    .padding(.horizontal, compact ? 0 : 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 1.5))
        .offset(x: isVertical ? 0 : dragOffset, y: isVertical ? dragOffset : 0)
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { dragOffset = isVertical ? $0.translation.height : $0.translation.width }
                .onEnded { value in
                    let delta = isVertical ? value.translation.height : value.translation.width
                    dragOffset = 0
                    move(by: Int((delta / max(40, width)).rounded()))
                }
        )
    }

    private func button(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: compact ? 16 : 20, height: 20).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func move(by steps: Int) {
        guard steps != 0, let index = settingsStore.widgetLayout.order.firstIndex(of: section) else { return }
        let count = settingsStore.widgetLayout.order.count
        let target = min(max(index + steps, 0), count - 1)
        guard target != index else { return }
        settingsStore.setWidgetLayout(settingsStore.widgetLayout.moving(from: IndexSet(integer: index), to: target > index ? target + 1 : target))
    }
}
