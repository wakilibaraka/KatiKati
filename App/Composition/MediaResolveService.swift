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

    @Published private(set) var isResolving = false
    @Published private(set) var lastFile: URL?
    @Published private(set) var lastFailure: String?

    /// Resolved files land beside ordinary downloads.
    var outputDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    /// What the owner configured, expanded and trimmed — nil when they have not chosen a tool yet.
    var configuredTool: String? {
        guard let raw = UserDefaults.standard.string(forKey: Self.toolKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw.hasPrefix("http") ? raw : (raw as NSString).expandingTildeInPath
    }

    func resolve(url: URL, options: MediaResolveOptions) {
        guard !isResolving else { return }
        lastFile = nil
        lastFailure = nil
        guard MediaResolver.isSupported(url) else {
            lastFailure = MediaResolverFailure.unsupportedURL.message
            return
        }
        guard let tool = configuredTool else {
            lastFailure = MediaResolverFailure.notConfigured.message
            return
        }
        if let remote = URL(string: tool), tool.hasPrefix("http") {
            post(to: remote, url: url, options: options)
        } else {
            run(tool, url: url, options: options)
        }
    }

    // MARK: - A local yt-dlp

    private func run(_ binary: String, url: URL, options: MediaResolveOptions) {
        isResolving = true
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
            let result: Result<URL, MediaResolverFailure>
            if let named = MediaResolver.parseDestination(output) {
                result = .success(URL(fileURLWithPath: named))
            } else if process.terminationStatus != 0 {
                let detail = output.split(separator: "\n").last.map(String.init) ?? ""
                result = .failure(.binaryFailed(detail))
            } else {
                result = .failure(.noFileProduced)
            }
            await MainActor.run { self.finish(result) }
        }
    }

    // MARK: - A self-hosted endpoint

    private func post(to endpoint: URL, url: URL, options: MediaResolveOptions) {
        guard let body = MediaResolver.endpointBody(for: url, options: options) else {
            lastFailure = MediaResolverFailure.noFileProduced.message
            return
        }
        isResolving = true
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
                if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
                    self.finish(.failure(.endpointFailed(status)))
                    return
                }
                let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
                guard let path = object?["path"] as? String, !path.isEmpty else {
                    self.finish(.failure(.noFileProduced))
                    return
                }
                self.finish(.success(URL(fileURLWithPath: path)))
            }
        }.resume()
    }

    private func finish(_ result: Result<URL, MediaResolverFailure>) {
        isResolving = false
        switch result {
        case .success(let file):
            lastFile = file
            NSWorkspace.shared.activateFileViewerSelecting([file])
        case .failure(let failure):
            lastFailure = failure.message
        }
    }
}
