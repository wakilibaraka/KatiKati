import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// Phase 23b/c: the define/translate card — the dictionary half plus the offline Apple translation.
/// Fully offline — nothing here touches the network.
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
            Divider().opacity(0.3)
            TranslationSection(text: request.text)
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
    }
}

/// The offline Apple translation half, driven by `.translationTask`.
/// Internal so the deck's dictionary page reuses this exact offline translation, not a second copy.
struct TranslationSection: View {
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

/// Floating selection action pill (Slice 2.2).
struct SelectionActionPillView: View {
    let actions: [SelectionAction]
    let onAction: (SelectionAction) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(actions) { action in
                Button {
                    onAction(action)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: action.symbol)
                            .font(.system(size: 10, weight: .semibold))
                        Text(verbatim: action.displayName)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.14)))
        .shadow(color: Color.black.opacity(0.18), radius: 8, y: 3)
    }
}

struct SelectionPillContainerView: View {
    let request: TranslateRequest
    let dictionary: DictionaryCardModel?
    let actions: [SelectionAction]
    let onAction: (SelectionAction) -> Void
    @State private var showTranslateCard = false

    var body: some View {
        VStack(spacing: 8) {
            SelectionActionPillView(actions: actions) { action in
                if action == .translate {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        showTranslateCard.toggle()
                    }
                } else {
                    onAction(action)
                }
            }

            if showTranslateCard {
                TranslateCardView(request: request, dictionary: dictionary)
                    .transition(.asymmetric(insertion: .scale(scale: 0.95).combined(with: .opacity), removal: .opacity))
            }
        }
    }
}
