import SwiftUI

/// SD-6: the EasyDict page. The deck's one search field is the lookup — type a word, press return, and the
/// offline system dictionary answers on the left while today's word and the recent lookups sit on the right.
/// The translation half is the same offline `TranslationSession` card the selection popup uses, not a copy.
struct SideDeckDictionaryPane: View {
    /// The deck header's field, shared so what the owner types in one place is in the other.
    @Binding var query: String

    @StateObject private var model = DictionaryPanelModel()
    @State private var history = DictionaryHistory.load()
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            definitionCard
            VStack(spacing: 12) {
                wordOfTheDayCard
                historyCard
            }
            .frame(width: 250)
        }
        .onAppear {
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lookUp(query) }
        }
    }

    // MARK: - Definition

    private var definitionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: SideDeckTab.dictionary.symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("Dictionary")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                if model.entry != nil {
                    Button {
                        model.copyDefinition()
                    } label: {
                        Text("Copy Definition").font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            TextField("Look up a word", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
                .onSubmit { lookUp(query) }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.08)))

            ScrollView {
                definitionBody
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sideDeckCard()
    }

    @ViewBuilder private var definitionBody: some View {
        if let entry = model.entry {
            Text(verbatim: entry.headword)
                .font(.system(size: 24, weight: .semibold, design: .serif))
            if let phonetic = entry.phonetic {
                Text(verbatim: phonetic)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(entry.blocks.enumerated()), id: \.offset) { _, block in
                VStack(alignment: .leading, spacing: 3) {
                    if let partOfSpeech = block.partOfSpeech {
                        Text(verbatim: partOfSpeech)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(block.senses.enumerated()), id: \.offset) { index, sense in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: "\(index + 1). \(sense.text)")
                                .font(.system(size: 12))
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(sense.examples, id: \.self) { example in
                                Text(verbatim: example)
                                    .font(.system(size: 11).italic())
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            if let origin = entry.origin {
                Text(verbatim: origin)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Divider().opacity(0.2)
            // The offline Apple translation of the headword, the same section the selection popup shows.
            TranslationSection(text: entry.headword)
        } else if model.searched {
            Text("No definition found")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else {
            Text(verbatim: "Type a word and press return.")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    // MARK: - Today's word

    private var wordOfTheDayCard: some View {
        let word = WordOfTheDay.word()
        return VStack(alignment: .leading, spacing: 6) {
            Text("Today")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: word)
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                Spacer()
                Button {
                    open(word)
                } label: {
                    Text("Open").font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sideDeckCard()
    }

    // MARK: - Recent lookups

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("History")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
            let words = history.matches(query)
            if words.isEmpty {
                Text(verbatim: "No lookups yet.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(words, id: \.self) { word in
                            Button { open(word) } label: {
                                Text(verbatim: word)
                                    .font(.system(size: 12))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 3)
                                    .padding(.horizontal, 6)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sideDeckCard()
    }

    /// Open a word the page already knows: the definition, and the field it came from, focused for the next one.
    private func open(_ word: String) {
        query = word
        lookUp(word)
        searchFocused = true
    }

    private func lookUp(_ word: String) {
        model.lookup(word)
        guard model.entry != nil else { return }
        history.record(word)
        history.save()
    }
}
