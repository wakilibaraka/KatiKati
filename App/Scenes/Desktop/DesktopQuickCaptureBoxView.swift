import SwiftUI

/// Desktop Quick Capture: a newest-first text inbox with optional screen-text (OCR) capture.
struct DesktopQuickCaptureBoxView: View {
    @ObservedObject var store: DesktopQuickCaptureStore
    let onAcquireLock: (DesktopInteractionLock) -> Void
    let onReleaseLock: (DesktopInteractionLock) -> Void

    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                TextField(text: $draft, prompt: Text("Capture a thought…")) { EmptyView() }
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .onSubmit { submit() }
                    .onChange(of: fieldFocused) { _, focused in
                        if focused { onAcquireLock(.inlineRename) } else { onReleaseLock(.inlineRename) }
                    }
                Button(action: captureFromScreen) {
                    Image(systemName: "text.viewfinder")
                }
                .buttonStyle(.borderless)
                .help(Text("Capture Text from Screen"))
                .accessibilityLabel(Text("Capture Text from Screen"))
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            if store.log.entries.isEmpty {
                Spacer()
                Image(systemName: "square.and.pencil").font(.system(size: 22)).foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(store.log.entries) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: entry.text).font(.system(size: 12)).lineLimit(6)
                                Text(entry.created, style: .relative)
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contextMenu {
                                Button(String(localized: "Copy")) {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(entry.text, forType: .string)
                                }
                                Button(String(localized: "Delete"), role: .destructive) { store.delete(entry.id) }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func submit() {
        store.add(draft)
        draft = ""
    }

    private func captureFromScreen() {
        let capture = ProductivityServices.shared.capture
        capture.start {
            if case .done(let text, _) = capture.state { store.add(text) }
            capture.reset()
        }
    }
}
