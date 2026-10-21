import SwiftUI

// The track pill's contents and its equalizer, apart from the panel controller and the feed so a test can
// lay them out (and so the equalizer can be used by the notch island too).

/// The pill's contents without the feed or the entrance animation.
struct NotchTrackPillContent: View {
    let title: String
    let artist: String
    let artwork: NSImage?
    let isPlaying: Bool
    var accent: Color = .white
    var reduceMotion = false

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let artwork {
                    Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.white.opacity(0.12).overlay(Image(systemName: "music.note").foregroundStyle(.white.opacity(0.7)))
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                MarqueeText(text: title, font: .system(size: 12, weight: .bold, design: .rounded))
                MarqueeText(text: artist, font: .system(size: 11)).foregroundStyle(.white.opacity(0.6))
            }
            // `MarqueeText` takes whatever width it is offered (its hidden spacer is a space), so a
            // fitting-size parent like this pill has to offer one — with only `maxWidth` the column
            // collapsed to a few points and both lines rendered as slivers (owner screenshot 2026-10-21).
            .frame(width: TrackPillTextMetrics.columnWidth(title: title, artist: artist), alignment: .leading)
            MusicEqualizerBars(isActive: isPlaying && !reduceMotion, tint: accent)
                .frame(width: 18, height: 16)
        }
        .foregroundStyle(.white)
    }
}

/// Four bars that dance while music plays and rest flat otherwise (also the Reduce Motion path).
struct MusicEqualizerBars: View {
    let isActive: Bool
    var tint: Color = .white

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: !isActive)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let wave = isActive ? 0.35 + 0.65 * abs(sin(t * (2.1 + Double(i) * 0.7) + Double(i))) : 0.25
                    Capsule().fill(tint).frame(width: 2.5, height: 16 * wave)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }
}
