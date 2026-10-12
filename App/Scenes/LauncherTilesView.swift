import AppKit
import SwiftUI

/// The widget row above the launcher grid (Phase 7B-L5). Tiles are the ones switched on in Settings; each is a
/// small card, nothing runs for a tile that is off.
/// Clock, Calculator and Countdown used to sit here too; they moved to the Pinboard (owner 2026-10-12).
struct LauncherTilesRow: View {
    let tiles: [LauncherTile]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(LauncherTile.ordered(tiles), id: \.self) { tile in
                    switch tile {
                    case .screenTime: LauncherScreenTimeTile()
                    }
                }
            }
        }
        .frame(height: 132)
    }
}

private struct LauncherScreenTimeTile: View {
    var body: some View {
        ScreenTimeSummaryView(rows: 3)
            .padding(12)
            .frame(width: 330, height: 128, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.10)))
    }
}
