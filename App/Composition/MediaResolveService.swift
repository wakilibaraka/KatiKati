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

    static let maxOutputBytes = 256 * 1024
    nonisolated static let defaultTimeoutSeconds: TimeInterval = 180

    private var activeProcess: Process?
    private var activeDataTask: URLSessionDataTask?
    private var timeoutTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private let resolveTimeout: TimeInterval

    init(resolveTimeout: TimeInterval = defaultTimeoutSeconds) {
        self.resolveTimeout = resolveTimeout
    }

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

    func cancel() {
        generation &+= 1
        timeoutTask?.cancel()
        timeoutTask = nil
        if let proc = activeProcess, proc.isRunning { proc.terminate() }
        activeProcess = nil
        activeDataTask?.cancel()
        activeDataTask = nil
        state.cancel()
    }

    func resolve(url: URL, options: MediaResolveOptions) {
        guard !state.isResolving else { return }
        generation &+= 1
        let currentGen = generation
        state.begin()
        guard MediaResolver.isSupported(url) else {
            finish(.failure(.unsupportedURL), generation: currentGen)
            return
        }
        switch route {
        case .notConfigured:
            finish(.failure(.notConfigured), generation: currentGen)
        case .endpoint(let endpoint):
            scheduleTimeout(generation: currentGen)
            post(to: endpoint, url: url, options: options, generation: currentGen)
        case .binary(let binary):
            scheduleTimeout(generation: currentGen)
            run(binary, url: url, options: options, generation: currentGen)
        }
    }

    private func scheduleTimeout(generation expectedGen: UInt64) {
        timeoutTask?.cancel()
        let seconds = resolveTimeout
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0.05, seconds) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.generation == expectedGen else { return }
                self.timeoutTask = nil
                if let proc = self.activeProcess, proc.isRunning { proc.terminate() }
                self.activeProcess = nil
                self.activeDataTask?.cancel()
                self.activeDataTask = nil
                self.finish(.failure(.binaryFailed("Timed out.")), generation: expectedGen)
            }
        }
    }

    // MARK: - A local yt-dlp

    private func run(_ binary: String, url: URL, options: MediaResolveOptions, generation currentGen: UInt64) {
        let arguments = MediaResolver.arguments(for: url, options: options,
                                                outputDirectory: outputDirectory.path)
        let cap = Self.maxOutputBytes
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        activeProcess = process

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try process.run()
            } catch {
                try? pipe.fileHandleForReading.close()
                let message = error.localizedDescription
                await MainActor.run { [weak self] in
                    self?.finish(.failure(.binaryFailed(message)), generation: currentGen)
                }
                return
            }
            var buffer = Data()
            while true {
                let chunk = pipe.fileHandleForReading.readData(ofLength: 8192)
                if chunk.isEmpty { break }
                buffer.append(chunk)
                if buffer.count > cap {
                    buffer.removeFirst(buffer.count - cap)
                }
            }
            process.waitUntilExit()
            let output = String(decoding: buffer, as: UTF8.self)
            let result = MediaResolveState.binaryOutcome(terminationStatus: process.terminationStatus,
                                                        output: output)
            await MainActor.run { [weak self] in
                self?.finish(result, generation: currentGen)
            }
        }
    }

    // MARK: - A self-hosted endpoint

    private func post(to endpoint: URL, url: URL, options: MediaResolveOptions, generation currentGen: UInt64) {
        guard let body = MediaResolver.endpointBody(for: url, options: options) else {
            finish(.failure(.noFileProduced), generation: currentGen)
            return
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = max(1, resolveTimeout)
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.finish(.failure(.binaryFailed(error.localizedDescription)), generation: currentGen)
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                self.finish(MediaResolveState.endpointOutcome(status: status, data: data), generation: currentGen)
            }
        }
        activeDataTask = task
        task.resume()
    }

    /// The single funnel: the pure state records the outcome, and the one effect left here reveals the file.
    private func finish(_ result: Result<URL, MediaResolverFailure>, generation expectedGen: UInt64) {
        guard generation == expectedGen else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        activeProcess = nil
        activeDataTask = nil
        state.finish(result)
        if case .success(let file) = result {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        }
    }
}
