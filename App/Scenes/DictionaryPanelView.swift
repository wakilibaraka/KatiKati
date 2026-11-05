import AppKit
import SwiftUI

/// State of the dictionary panel: the typed query and the entry the system dictionary returned for it.
@MainActor
final class DictionaryPanelModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var entry: DictionaryEntry?
    @Published private(set) var searched = false

    func lookup(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        query = trimmed
        guard !trimmed.isEmpty else { entry = nil; searched = false; return }
        entry = DictionaryEntry.parse(headword: trimmed, payload: DictionaryService.define(trimmed))
        searched = true
    }

    func copyDefinition() {
        guard let entry else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.copyText, forType: .string)
    }
}

/// The dictionary card: search field, big serif headword + phonetic, numbered senses with examples, origin,
/// and a bottom bar to look up / copy. Source is the system dictionary only (offline).
struct DictionaryPanelView: View {
    @ObservedObject var model: DictionaryPanelModel
    let onClose: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchRow
            Divider().opacity(0.4)
            ScrollView { content.padding(18).frame(maxWidth: .infinity, alignment: .leading) }
            Divider().opacity(0.4)
            bottomBar
        }
        .frame(width: 460, height: 520)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
        .environment(\.colorScheme, .dark)
        .onAppear { focused = true }
        .onExitCommand(perform: onClose)
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            Button(action: onClose) { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            TextField("Look up a word", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($focused)
                .onSubmit { model.lookup(model.query) }
            Image(systemName: "magnifyingglass").opacity(0.5)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    @ViewBuilder private var content: some View {
        if let entry = model.entry {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: entry.headword).font(.system(size: 34, weight: .semibold, design: .serif))
                if let phonetic = entry.phonetic {
                    Text(verbatim: phonetic)
                        .font(.system(size: 13)).padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                ForEach(Array(entry.blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
                if let origin = entry.origin {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ORIGIN").font(.system(size: 11, weight: .semibold)).opacity(0.5)
                        Text(verbatim: origin).font(.system(size: 13))
                    }
                    .padding(.top, 6)
                }
            }
        } else {
            Text(model.searched ? "No definition found" : "Type a word and press Return")
                .opacity(0.6)
                .frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    private func blockView(_ block: DictionaryEntry.Block) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let pos = block.partOfSpeech {
                Text(verbatim: pos).font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.35)))
            }
            ForEach(Array(block.senses.enumerated()), id: \.offset) { index, sense in
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: "\(index + 1). \(sense.text)").font(.system(size: 14))
                    ForEach(sense.examples, id: \.self) { example in
                        Text(verbatim: "“\(example)”").font(.system(size: 13)).italic().opacity(0.6)
                    }
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            Text("System dictionary").font(.system(size: 11)).opacity(0.5)
            Spacer()
            Button("Define Word") { model.lookup(model.query) }
            Button("Copy Definition") { model.copyDefinition() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.entry == nil)
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}
