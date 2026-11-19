import SwiftUI

/// Desktop Search pill (Phase 66A–B): type a query, press Return to open the unified results panel,
/// or hand the same query to the Command Bar.
struct DesktopSearchPillView: View {
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search everything", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focused)
                    .onSubmit { openSearch() }
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Clear Search"))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule().fill(.quaternary.opacity(0.6)))

            HStack(spacing: 6) {
                Button("Search") { openSearch() }
                Spacer()
                Button("Command Bar") {
                    AppDelegate.shared?.presentCommandBar(query: text)
                }
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
        .padding(10)
    }

    private func openSearch() {
        DesktopSearchPanelController.shared.present(query: text)
    }
}
