import AppKit
import SwiftUI

// Phase 37b/37c — the prompter UI shared by the floating window and the notch page. `compact` is the notch
// layout: scrolling text plus a play button; the full layout adds speed/size/mirror, editing and links.

private struct ScriptHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct TeleprompterScrollArea: View {
    @ObservedObject var model: TeleprompterModel

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                if model.script.isEmpty {
                    Text("Add a script in the Teleprompter window.")
                        .font(.system(size: 13)).foregroundColor(.white.opacity(0.6)).padding(.top, geo.size.height * 0.3)
                } else {
                    Text(verbatim: model.script)
                        .font(.system(size: model.fontSize, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .frame(width: max(geo.size.width - 28, 10))
                        .fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { Color.clear.preference(key: ScriptHeightKey.self, value: $0.size.height) })
                        .offset(y: geo.size.height * 0.35 - model.scroll.offset)
                }
                // Eye-line marker: where the line being read should sit, just under the camera.
                HStack {
                    Image(systemName: "arrowtriangle.right.fill").foregroundColor(.orange)
                    Spacer()
                    Image(systemName: "arrowtriangle.left.fill").foregroundColor(.orange)
                }
                .font(.system(size: 9))
                .offset(y: geo.size.height * 0.35 + model.fontSize * 0.4)
                .accessibilityHidden(true)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .clipped()
            .onPreferenceChange(ScriptHeightKey.self) { model.contentHeight = Double($0) }
            .scaleEffect(x: model.mirrored ? -1 : 1, y: 1)
        }
    }
}

struct TeleprompterView: View {
    @ObservedObject var model = TeleprompterModel.shared
    var compact = false
    @State private var editing = false
    @StateObject private var reader = LinkReaderModel()

    var body: some View {
        VStack(spacing: 8) {
            if reader.isActive {
                LinkReaderPane(reader: reader, model: model)
            } else if editing && !compact {
                TextEditor(text: $model.script).font(.system(size: 13)).frame(minHeight: 120)
            } else {
                TeleprompterScrollArea(model: model)
            }
            controls
            if !compact && !reader.isActive && !model.links.isEmpty { linkChips }
        }
        .padding(compact ? 0 : 12)
        .background(compact ? Color.clear : Color.black)
        .colorScheme(.dark)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button { model.togglePlay() } label: { Image(systemName: model.isPlaying ? "pause.fill" : "play.fill") }
                .keyboardShortcut(.space, modifiers: [])
                .accessibilityLabel(model.isPlaying ? Text("Pause") : Text("Play"))
            Button { model.restart() } label: { Image(systemName: "backward.end.fill") }
                .accessibilityLabel(Text("Restart"))
            if !compact {
                Button { model.nudge(-120) } label: { Image(systemName: "chevron.up") }.accessibilityLabel(Text("Back"))
                Button { model.nudge(120) } label: { Image(systemName: "chevron.down") }.accessibilityLabel(Text("Forward"))
                Divider().frame(height: 14)
                Image(systemName: "hare").foregroundColor(.white.opacity(0.6))
                Slider(value: $model.wpm, in: TeleprompterSpeed.wpmRange).frame(width: 90)
                Text(verbatim: "\(Int(model.wpm))").font(.system(size: 11).monospacedDigit()).frame(width: 28)
                Image(systemName: "textformat.size").foregroundColor(.white.opacity(0.6))
                Slider(value: $model.fontSize, in: TeleprompterSpeed.fontRange).frame(width: 80)
                Toggle(isOn: $model.mirrored) { Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right") }
                    .toggleStyle(.button).accessibilityLabel(Text("Mirror"))
                Spacer(minLength: 0)
                Button(editing ? "Done" : "Edit") { editing.toggle(); model.pause() }
            } else {
                Spacer(minLength: 0)
                Button { TeleprompterWindowController.shared.show() } label: { Image(systemName: "rectangle.expand.vertical") }
                    .accessibilityLabel(Text("Open Teleprompter Window"))
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 13))
    }

    private var linkChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.links, id: \.self) { url in
                    Button { reader.open(url) } label: {
                        Label(url.host ?? url.absoluteString, systemImage: "link")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}
