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
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @ObservedObject private var editMode = WidgetEditMode.shared
    @State private var dragX: CGFloat = 0
    private var compact: Bool { width < 90 }

    var body: some View {
        HStack(spacing: compact ? 0 : 6) {
            button("chevron.left") { move(by: -1) }
            // Narrow widgets (launcher / widgets, 40 pt) get only the arrows; the ✓ lives on the wider ones.
            if !compact { button("checkmark") { editMode.end() } }
            button("chevron.right") { move(by: 1) }
        }
        .padding(.horizontal, compact ? 0 : 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 1.5))
        .offset(x: dragX)
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { dragX = $0.translation.width }
                .onEnded { value in
                    dragX = 0
                    move(by: Int((value.translation.width / max(40, width)).rounded()))
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
