import SwiftUI

/// One-line text that scrolls to reveal a clipped tail: twice when the song starts, once more near its end.
struct MarqueeText: View {
    let text: String
    let font: Font
    var nearEnd = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textW: CGFloat = 0
    @State private var boxW: CGFloat = 0
    @State private var offset: CGFloat = 0

    private struct Width: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }
    private struct BoxWidth: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }

    private var overflow: CGFloat { max(0, textW - boxW) }

    var body: some View {
        // The box is a hidden one-line spacer that takes the width it is offered; the real text hangs off it, so a
        // long title can never size the box (it used to, and a `maxWidth` cap above it then clipped nothing).
        Text(verbatim: " ").font(font).lineLimit(1).hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { Color.clear.preference(key: BoxWidth.self, value: $0.size.width) })
            .overlay(alignment: .leading) {
                Text(verbatim: text).font(font).lineLimit(1).fixedSize()
                    .background(GeometryReader { Color.clear.preference(key: Width.self, value: $0.size.width) })
                    .offset(x: offset)
            }
            .clipped()
            .mask(fade)
            .onPreferenceChange(Width.self) { textW = $0 }
            .onPreferenceChange(BoxWidth.self) { boxW = $0 }
            .task(id: "\(text)|\(nearEnd)|\(Int(overflow))") { await scroll() }
    }

    /// Soft edges only while the text really overflows; the leading one appears once it has moved.
    private var fade: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(overflow > 1 && offset < -1 ? 0 : 1), .black], startPoint: .leading, endPoint: .trailing).frame(width: 8)
            Color.black
            LinearGradient(colors: [.black, .black.opacity(overflow > 1 && offset > -overflow + 1 ? 0 : 1)], startPoint: .leading, endPoint: .trailing).frame(width: 8)
        }
    }

    private func scroll() async {
        offset = 0
        guard overflow > 1, !reduceMotion else { return }
        let travel = Double(overflow) / 28
        for _ in 0..<(nearEnd ? 1 : 2) {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.linear(duration: travel)) { offset = -overflow }
            try? await Task.sleep(for: .seconds(travel + 0.8))
            withAnimation(.easeOut(duration: 0.4)) { offset = 0 }
            try? await Task.sleep(for: .seconds(0.4))
            if Task.isCancelled { return }
        }
    }
}
