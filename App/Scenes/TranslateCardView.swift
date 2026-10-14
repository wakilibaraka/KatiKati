import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// Phase 23b/c: the define/translate card. Dictionary on the 12 floor; the translation half appears only
/// on macOS 15+. Fully offline — nothing here touches the network.
struct TranslateCardView: View {
    let request: TranslateRequest
    let dictionary: DictionaryCardModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: dictionary?.headword ?? request.text)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
            if let dictionary, !dictionary.senses.isEmpty {
                ForEach(dictionary.senses, id: \.self) { sense in
                    Text(verbatim: sense).font(.system(size: 12)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("No definition found").font(.system(size: 12)).foregroundColor(.secondary)
            }
            if #available(macOS 15, *) {
                Divider().opacity(0.3)
                TranslationSection(text: request.text)
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
    }
}

/// macOS 15+: the offline Apple translation half, driven by `.translationTask`. Hidden entirely below 15.
@available(macOS 15, *)
private struct TranslationSection: View {
    let text: String
    @State private var output: String?
    @State private var failed = false
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Group {
            if let output, !output.isEmpty {
                Text(verbatim: output).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            } else if !failed {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { if configuration == nil { configuration = TranslationSession.Configuration(source: nil, target: nil) } }
        .translationTask(configuration) { session in
            do { output = try await session.translate(text).targetText } catch { failed = true }
        }
    }
}
