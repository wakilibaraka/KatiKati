import Foundation

/// The eight note colours (Phase 7A-D1). Each has a `paper` (sheet / tab fill), a saturated `dash`
/// (pill dash, chip, accent) and an `ink` (text on paper) — slightly deeper than highlighter pastels so a
/// note reads as paper with colour in it. Values and the colour-order idea follow noty's `NoteColor`
/// (MIT, © Aymen Hamza — see NOTICE); names are stable identifiers, never shown to the user.
struct NotePaletteEntry: Equatable, Sendable {
    let name: String
    let paper: UInt32
    let dash: UInt32
    let ink: UInt32
}

enum NotePalette {
    static let all: [NotePaletteEntry] = [
        NotePaletteEntry(name: "Lemon", paper: 0xFCE795, dash: 0xE0AD08, ink: 0x3A3008),
        NotePaletteEntry(name: "Peach", paper: 0xFBCFA6, dash: 0xE2762A, ink: 0x422413),
        NotePaletteEntry(name: "Rose", paper: 0xFAC4D1, dash: 0xDC4570, ink: 0x40161F),
        NotePaletteEntry(name: "Lilac", paper: 0xD9C7FA, dash: 0x7C4DEE, ink: 0x2A1B44),
        NotePaletteEntry(name: "Sky", paper: 0xBEDDFA, dash: 0x2280D6, ink: 0x13293A),
        NotePaletteEntry(name: "Mint", paper: 0xB4E8D0, dash: 0x0E9B6E, ink: 0x0F2E23),
        NotePaletteEntry(name: "Sand", paper: 0xE3D3B4, dash: 0xA37B3C, ink: 0x372C18),
        NotePaletteEntry(name: "Slate", paper: 0xCBD6E2, dash: 0x4E6579, ink: 0x1A242E),
    ]

    /// Wraps any integer (including negatives) into the palette.
    static func entry(at index: Int) -> NotePaletteEntry {
        all[((index % all.count) + all.count) % all.count]
    }

    /// Colour for the next new note: one past the most recently created note's colour, so consecutive
    /// notes rotate through the palette.
    static func nextIndex(after notes: [Note]) -> Int {
        guard let newest = notes.max(by: { ($0.created, $0.id) < ($1.created, $1.id) }) else { return 0 }
        return (newest.color + 1) % all.count
    }
}
