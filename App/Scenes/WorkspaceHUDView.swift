import SwiftUI

/// W-7: the workspace capsule. A row of that display's workspaces with a marker on the active one,
/// drawn only while a switch is settling.
///
/// Deliberately typographic: workspaces are numbers and letters, so the capsule reads the same in
/// every language and needs no localization entries. The marker follows the bar's ink colour rather
/// than introducing a new palette.
struct WorkspaceHUDView: View {
    let workspaces: [WorkspaceID]
    let active: WorkspaceID
    /// Reduce Motion keeps the marker still: it is drawn where it belongs instead of travelling.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            ForEach(workspaces, id: \.self) { workspace in
                Text(verbatim: workspace.token)
                    .font(.system(size: 11, weight: workspace == active ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(workspace == active ? Color(nsColor: .windowBackgroundColor) : Color.primary.opacity(0.75))
                    .frame(minWidth: 18, minHeight: 17)
                    .padding(.horizontal, 3)
                    .background {
                        Capsule(style: .continuous)
                            .fill(workspace == active ? Color.primary.opacity(0.88) : Color.primary.opacity(0.10))
                    }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
    }
}
