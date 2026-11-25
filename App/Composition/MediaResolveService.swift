import AppKit
import Foundation

/// SD-5: runs the owner's resolver — the `yt-dlp` they installed, or an endpoint they host — and reports the
/// file it produced. Off until the owner opts in and names a tool, and nothing is bundled with the app, so the
/// resolver stays a thing they chose rather than a dependency they inherited.
@MainActor
final class MediaResolveService: ObservableObject {
    static let shared = MediaResolveService()

    /// The pane's opt-in switch. Everything below is inert while it is false.
    static let enabledKey = "com.katikati.mediaResolver.enabled"
    /// One field for either kind of tool: an `http(s)` URL is posted to, anything else is run as a binary.
    static let toolKey = "com.katikati.mediaResolver.tool"

    /// Everything the pane shows. `begin()`/`finish()` on this struct are the single funnel.
    @Published private(set) var state = MediaResolveState()

    var isResolving: Bool { state.isResolving }
    var lastFile: URL? { state.lastFile }
    var lastFailure: String? { state.lastFailure }

    /// Resolved files land beside ordinary downloads.
    var outputDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    /// Where the configured tool points: nowhere, a local binary, or an endpoint.
    var route: MediaResolveRoute {
        MediaResolveState.route(tool: UserDefaults.standard.string(forKey: Self.toolKey))
    }

    var hasTool: Bool { route != .notConfigured }

    func resolve(url: URL, options: MediaResolveOptions) {
        guard !state.isResolving else { return }
        state.begin()
        guard MediaResolver.isSupported(url) else {
            finish(.failure(.unsupportedURL))
            return
        }
        switch route {
        case .notConfigured:
            finish(.failure(.notConfigured))
        case .endpoint(let endpoint):
            post(to: endpoint, url: url, options: options)
        case .binary(let binary):
            run(binary, url: url, options: options)
        }
    }

    // MARK: - A local yt-dlp

    private func run(_ binary: String, url: URL, options: MediaResolveOptions) {
        let arguments = MediaResolver.arguments(for: url, options: options,
                                                outputDirectory: outputDirectory.path)
        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
            } catch {
                await MainActor.run { self.finish(.failure(.binaryFailed(error.localizedDescription))) }
                return
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(decoding: data, as: UTF8.self)
            let result = MediaResolveState.binaryOutcome(terminationStatus: process.terminationStatus,
                                                        output: output)
            await MainActor.run { self.finish(result) }
        }
    }

    // MARK: - A self-hosted endpoint

    private func post(to endpoint: URL, url: URL, options: MediaResolveOptions) {
        guard let body = MediaResolver.endpointBody(for: url, options: options) else {
            finish(.failure(.noFileProduced))
            return
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 120
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.finish(.failure(.binaryFailed(error.localizedDescription)))
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                self.finish(MediaResolveState.endpointOutcome(status: status, data: data))
            }
        }.resume()
    }

    /// The single funnel: the pure state records the outcome, and the one effect left here reveals the file.
    private func finish(_ result: Result<URL, MediaResolverFailure>) {
        state.finish(result)
        if case .success(let file) = result {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        }
    }
}
