import SwiftUI

/// The notes flyout (Phase 7A-7b): note list on the left, editor on the right, undo toast at the
/// bottom. Pure binding to `NotesController`; autosave/undo rules live there.
struct NotesPopupView: View {
    @ObservedObject var controller: NotesController
    let onClose: () -> Void
    @State private var selection: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                list.frame(width: 150)
                Divider()
                editor
            }
            if let deleted = controller.undoableDeletion {
                undoToast(for: deleted)
                    .padding(10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: EdgeBarLayout.notesPopupSize.width, height: EdgeBarLayout.notesPopupSize.height)
        .animation(.easeInOut(duration: 0.15), value: controller.undoableDeletion)
        .onAppear { if selection == nil { selection = controller.notes.first?.id } }
        .onExitCommand(perform: onClose)
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    selection = controller.create().id
                } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                Spacer(minLength: 0)
            }
            .padding(10)
            Divider()
            if controller.notes.isEmpty {
                Spacer()
                Text("No Notes Yet").foregroundStyle(.secondary).font(.callout)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(controller.notes) { note in
                            row(note)
                        }
                    }
                    .padding(6)
                }
            }
        }
    }

    private func row(_ note: Note) -> some View {
        Button {
            selection = note.id
        } label: {
            HStack(spacing: 6) {
                if note.pinned {
                    Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary)
                }
                if note.displayTitle.isEmpty {
                    Text("Untitled").foregroundStyle(.secondary)
                } else {
                    Text(verbatim: note.displayTitle)
                }
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selection == note.id ? Color.accentColor.opacity(0.25) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var editor: some View {
        if let id = selection, let note = controller.note(id: id) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Spacer()
                    Button(note.pinned ? "Unpin" : "Pin") { controller.togglePin(id: id) }
                    Button("Delete", role: .destructive) {
                        controller.delete(id: id)
                        selection = controller.notes.first?.id
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                Divider()
                TextEditor(text: Binding(
                    get: { controller.note(id: id)?.body ?? "" },
                    set: { controller.edit(id: id, body: $0) }
                ))
                .font(.body)
                .modifier(TransparentEditorBackground())
                .padding(6)
            }
        } else {
            VStack {
                Spacer()
                Image(systemName: "note.text").font(.largeTitle).foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func undoToast(for note: Note) -> some View {
        HStack(spacing: 10) {
            Text("Note Deleted").font(.callout)
            Button("Undo") {
                controller.undoDelete()
                selection = note.id
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
    }
}

/// `TextEditor` paints an opaque dark box over the flyout's glass plate; hide it where the API exists (macOS 13+).
private struct TransparentEditorBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}
