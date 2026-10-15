import SwiftUI

/// One note as a sheet of its own coloured paper (Phase 7A-D4), pulled out of its tab like noty's expanded note:
/// colour dots, pin, delete, the text editor and the undo toast. Autosave / undo rules live in `NotesController`.
struct NoteSheetView: View {
    @ObservedObject var controller: NotesController
    let noteID: String
    let onRight: Bool
    let tabFont: String
    let onClose: () -> Void

    @State private var pulled = false

    static let size = CGSize(width: 330, height: 300)

    private var note: Note? { controller.note(id: noteID) }

    var body: some View {
        let palette = NotePalette.entry(at: note?.color ?? 0)
        ZStack(alignment: .bottom) {
            if let note {
                VStack(spacing: 0) {
                    header(note, palette: palette)
                    NoteBodyEditor(text: Binding(
                        get: { controller.note(id: noteID)?.body ?? "" },
                        set: { controller.edit(id: noteID, body: $0) }
                    ), ink: palette.inkColor, face: tabFont)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                }
            }
            if let deleted = controller.undoableDeletion {
                undoToast(for: deleted, palette: palette)
                    .padding(10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.paperColor))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.inkColor.opacity(0.12), lineWidth: 1))
        .animation(.easeInOut(duration: 0.15), value: controller.undoableDeletion)
        // The pull: a short slide off the edge, a touch of scale anchored there, and a fade (a full-width slide reads
        // as a window flying in).
        .offset(x: pulled ? 0 : (onRight ? 40 : -40))
        .scaleEffect(pulled ? 1 : 0.965, anchor: onRight ? .trailing : .leading)
        .opacity(pulled ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { pulled = true } }
        .onExitCommand(perform: onClose)
        .onChange(of: note == nil) { gone in if gone && controller.undoableDeletion == nil { onClose() } }
    }

    private func header(_ note: Note, palette: NotePaletteEntry) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<NotePalette.all.count, id: \.self) { i in
                let entry = NotePalette.entry(at: i)
                Button { controller.setColor(id: noteID, i) } label: {
                    Circle().fill(entry.dashColor).frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(palette.inkColor, lineWidth: i == note.color ? 2 : 0).padding(-3))
                }
                .buttonStyle(.plain)
                .help(DeckTab.colorName(i))
            }
            Spacer(minLength: 8)
            Button { controller.togglePin(id: noteID) } label: {
                Image(systemName: note.pinned ? "pin.fill" : "pin").foregroundColor(palette.inkColor.opacity(0.75))
            }
            .buttonStyle(.plain)
            .help(note.pinned ? Text("Unpin") : Text("Pin"))
            Button { controller.delete(id: noteID) } label: {
                Image(systemName: "trash").foregroundColor(palette.inkColor.opacity(0.75))
            }
            .buttonStyle(.plain)
            .help(Text("Delete"))
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func undoToast(for note: Note, palette: NotePaletteEntry) -> some View {
        HStack(spacing: 10) {
            Text("Note Deleted").font(.callout)
            Button("Undo") { controller.undoDelete() }.buttonStyle(.borderless)
        }
        .foregroundColor(palette.inkColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.white.opacity(0.55)))
        .overlay(Capsule().strokeBorder(palette.inkColor.opacity(0.15)))
    }
}

/// `scrollContentBackground(.hidden)` is what lets the note's own paper colour show through.
private struct NoteBodyEditor: View {
    @Binding var text: String
    let ink: Color
    let face: String

    private var font: Font {
        if !face.isEmpty, NSFont(name: face, size: 13) != nil { return .custom(face, size: 14) }
        return .system(size: 13.5)
    }

    var body: some View {
        TextEditor(text: $text).font(font).foregroundColor(ink).scrollContentBackground(.hidden)
    }
}
