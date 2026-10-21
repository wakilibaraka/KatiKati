import AppKit
import Vision

/// Capture Area (Phase 7A-P5): the user drags a screen region with the system's own selector, then text and QR
/// codes in it are recognised on-device with Vision. Nothing is kept: the screenshot is a temp file deleted
/// right after recognition.
@MainActor
final class CaptureController: ObservableObject {
    enum State: Equatable {
        case idle
        case working
        case done(text: String, codes: [String])
        case cancelled
    }

    @Published private(set) var state: State = .idle

    /// Runs the selector; `completion` fires on the main actor once there is something to show (or the user cancelled).
    func start(completion: @escaping () -> Void) {
        guard state != .working else { return }
        state = .working
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("katikati-capture-\(UUID().uuidString).png")
        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-x", "-t", "png", file.path]
            try? process.run()
            process.waitUntilExit()
            let result = Self.recognise(file)
            try? FileManager.default.removeItem(at: file)
            await MainActor.run { [weak self] in
                self?.state = result.map { .done(text: $0.text, codes: $0.codes) } ?? .cancelled
                completion()
            }
        }
    }

    func reset() { state = .idle }

    // MARK: 55b — the dial's and the shortcut's shared screencapture runner

    /// Interactive area selector straight to the clipboard. It waits for the drag, so it never blocks the caller.
    nonisolated static func captureAreaToClipboard() { run(["-i", "-c"]) }
    nonisolated static func captureWindowToClipboard() { run(["-i", "-w", "-c"]) }

    nonisolated private static func run(_ arguments: [String]) {
        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = arguments
            try? process.run()
        }
    }

    nonisolated static func recognise(_ file: URL) -> (text: String, codes: [String])? {
        guard let image = NSImage(contentsOf: file), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil   // Esc in the selector, or Screen Recording is not allowed: no file
        }
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        let supported = (try? textRequest.supportedRecognitionLanguages()) ?? []
        let wanted = Locale.preferredLanguages.compactMap { tag in supported.first { $0.hasPrefix(String(tag.prefix(2))) } }
        textRequest.recognitionLanguages = Array(NSOrderedSet(array: wanted + ["en-US"])) as? [String] ?? ["en-US"]
        let barcodeRequest = VNDetectBarcodesRequest()
        try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([textRequest, barcodeRequest])
        let blocks = (textRequest.results ?? []).compactMap { obs -> CaptureRules.Block? in
            obs.topCandidates(1).first.map { CaptureRules.Block(text: $0.string, box: obs.boundingBox) }
        }
        let codes = CaptureRules.uniquePayloads((barcodeRequest.results ?? []).compactMap { $0.payloadStringValue })
        return (CaptureRules.readingOrder(blocks), codes)
    }
}
