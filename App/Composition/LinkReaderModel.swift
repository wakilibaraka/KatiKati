import Foundation
import SwiftUI

// Phase 37d — the teleprompter's link reader. A link in the script is fetched only when the user taps its
// chip: https only, no private addresses (`LinkFetchPolicy`), no cookies or credentials, 10 s timeout, 2 MB cap,
// text/HTML only. The extracted text is shown here and can be sent to the prompter. Nothing is stored.

@MainActor
final class LinkReaderModel: ObservableObject {
    enum State: Equatable {
        case idle, loading(URL)
        case loaded(url: URL, title: String?, text: String)
        case failed(String)
    }

    static let maxBytes = 2_000_000
    @Published private(set) var state = State.idle
    var isActive: Bool { state != .idle }
    private var task: Task<Void, Never>?

    func close() { task?.cancel(); state = .idle }

    func open(_ url: URL) {
        switch LinkFetchPolicy.verdict(for: url) {
        case .insecure: state = .failed(String(localized: "Only secure (https) links can be opened.")); return
        case .privateHost: state = .failed(String(localized: "Private or local addresses can't be opened.")); return
        case .allowed: break
        }
        task?.cancel()
        state = .loading(url)
        task = Task { [weak self] in
            let result = await Self.fetch(url)
            guard !Task.isCancelled else { return }
            self?.state = result
        }
    }

    nonisolated private static func fetch(_ url: URL) async -> State {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        var request = URLRequest(url: url)
        request.setValue("text/html,text/plain;q=0.9", forHTTPHeaderField: "Accept")
        do {
            let (bytes, response) = try await URLSession(configuration: config).bytes(for: request)
            // A redirect may have left https or landed on a private host: re-check where we ended up.
            if let final = response.url, LinkFetchPolicy.verdict(for: final) != .allowed {
                return .failed(String(localized: "Private or local addresses can't be opened."))
            }
            let type = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            guard type.contains("text/html") || type.contains("text/plain") || type.isEmpty else {
                return .failed(String(localized: "This page can't be read here — it may need JavaScript or a subscription."))
            }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count >= maxBytes { break }
            }
            let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            let page = type.contains("text/plain") ? (title: nil, text: html) : ReadableText.extract(html: html)
            guard page.text.count >= ReadableText.minimumUsefulLength else {
                return .failed(String(localized: "This page can't be read here — it may need JavaScript or a subscription."))
            }
            return .loaded(url: url, title: page.title, text: page.text)
        } catch is CancellationError {
            return .idle
        } catch {
            return .failed(String(localized: "Couldn't load the page."))
        }
    }
}

struct LinkReaderPane: View {
    @ObservedObject var reader: LinkReaderModel
    @ObservedObject var model: TeleprompterModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch reader.state {
            case .idle:
                EmptyView()
            case .loading(let url):
                HStack { ProgressView().controlSize(.small); Text("Loading…"); Text(verbatim: url.host ?? "").foregroundColor(.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                Text(verbatim: message).foregroundColor(.orange).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(_, let title, let text):
                if let title { Text(verbatim: title).font(.system(size: 14, weight: .bold)) }
                ScrollView { Text(verbatim: text).font(.system(size: 13)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            }
            HStack {
                Button("Back") { reader.close() }
                Spacer()
                if case .loaded(_, _, let text) = reader.state {
                    Button("Send to Prompter") { model.script = text; model.restart(); reader.close() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .font(.system(size: 13))
    }
}
