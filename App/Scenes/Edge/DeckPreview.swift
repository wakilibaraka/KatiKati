import SwiftUI

/// Hover preview of a note (noty's `NotePreviewCard`): coloured dot, title, pin, four body lines on the note's own
/// paper. Hosted by the deck's flyout panel; clicking it opens the note.
struct DeckPreviewCard: View {
    let note: Note
    let onRight: Bool
    let onOpen: () -> Void

    static let size = CGSize(width: 236, height: 112)

    private var palette: NotePaletteEntry { NotePalette.entry(at: note.color) }

    private var lines: [String] {
        let all = note.body.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return Array((note.hasCustomTitle ? all : Array(all.dropFirst())).prefix(4))
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Circle().fill(palette.dashColor).frame(width: 7, height: 7)
                    if note.displayTitle.isEmpty {
                        Text("Untitled").font(.system(size: 11.5, weight: .bold)).foregroundColor(palette.inkColor.opacity(0.6))
                    } else {
                        Text(verbatim: note.displayTitle).font(.system(size: 11.5, weight: .bold)).foregroundColor(palette.inkColor).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if note.pinned { Image(systemName: "pin.fill").font(.system(size: 8.5)).foregroundColor(palette.inkColor.opacity(0.7)) }
                }
                if lines.isEmpty {
                    Text("Empty note").font(.system(size: 10).italic()).foregroundColor(palette.inkColor.opacity(0.45))
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(verbatim: line).font(.system(size: 10.5)).foregroundColor(palette.inkColor.opacity(0.8)).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(palette.paperColor))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.inkColor.opacity(0.12), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
