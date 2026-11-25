import Foundation

/// SD-5: the opt-in media URL resolver's decisions — what to ask for, how to name it, and how to read the
/// answer back — kept apart from the process or endpoint that does the work, so they can be tested without a
/// network or a `yt-dlp` binary.
///
/// Clean-room: no `cobalt` code, assets or CSS (AGPL / CC BY-NC-SA). The resolver is the owner's own tool —
/// a local `yt-dlp` they installed, or an endpoint they host — and nothing is bundled with the app.
enum MediaQuality: String, CaseIterable, Sendable {
    case best, p1080, p720, p480, audio

    /// What the owner sees. These are technical labels (`1080p`, `MP3`), shown verbatim on purpose: a
    /// translated "1080p" would be wrong in every language.
    var label: String {
        switch self {
        case .best: return "Best"
        case .p1080: return "1080p"
        case .p720: return "720p"
        case .p480: return "480p"
        case .audio: return "Audio"
        }
    }

    /// The selector handed to the resolver. `bestvideo+bestaudio` is yt-dlp's, and the caps are the usual
    /// "this tall or shorter" form, so a 1080p request still resolves on a 720p source.
    var formatSelector: String {
        switch self {
        case .best: return "bestvideo+bestaudio/best"
        case .p1080: return "bestvideo[height<=1080]+bestaudio/best[height<=1080]"
        case .p720: return "bestvideo[height<=720]+bestaudio/best[height<=720]"
        case .p480: return "bestvideo[height<=480]+bestaudio/best[height<=480]"
        case .audio: return "bestaudio/best"
        }
    }

    var isAudioOnly: Bool { self == .audio }
}

struct MediaResolveOptions: Equatable, Sendable {
    var quality: MediaQuality = .best
    /// Drop the audio track from a video download.
    var mute: Bool = false
    /// A base name for the saved file, without an extension. Empty means "let the resolver choose".
    var fileName: String = ""

    /// The name we actually ask for: trimmed, separator-safe, and empty when the owner typed nothing usable.
    var requestedBaseName: String? { MediaResolver.sanitise(fileName) }
}

/// Why a resolve did not produce a file. Every case says what the owner can do about it, because "failed" alone
/// is the state this UX exists to avoid.
enum MediaResolverFailure: Error, Equatable, Sendable {
    case notConfigured
    case unsupportedURL
    case binaryFailed(String)
    case endpointFailed(Int)
    case noFileProduced

    var message: String {
        switch self {
        case .notConfigured:
            return "Set a yt-dlp path or a resolver endpoint first."
        case .unsupportedURL:
            return "Only http and https links can be resolved."
        case .binaryFailed(let detail):
            return detail.isEmpty ? "The resolver exited with an error." : detail
        case .endpointFailed(let status):
            return "The resolver endpoint answered \(status)."
        case .noFileProduced:
            return "The resolver finished without naming a file."
        }
    }
}

enum MediaResolver {
    /// Only real links: the resolver shells out, so a file URL or a bare word is refused before anything runs.
    static func isSupported(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && (url.host?.isEmpty == false)
    }

    /// A safe base name, or nil when nothing usable is left. Separators and colons are replaced (they are path
    /// separators or illegal on at least one filesystem), and the result is length-capped.
    static func sanitise(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let replaced = trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        let cleaned = replaced.trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(120))
    }

    /// The `yt-dlp` invocation: quality, mute, and the output template that keeps the file inside `directory`.
    static func arguments(for url: URL, options: MediaResolveOptions, outputDirectory: String) -> [String] {
        var args = ["--no-playlist", "-f", options.quality.formatSelector]
        if options.quality.isAudioOnly {
            args += ["-x", "--audio-format", "mp3"]
        } else if options.mute {
            // Video with the audio track dropped, so a muted download needs no second pass by hand.
            args += ["--postprocessor-args", "ffmpeg:-an"]
        }
        let name = options.requestedBaseName
        let template = name.map { "%(ext)s".isEmpty ? $0 : $0 + ".%(ext)s" } ?? "%(title).120s.%(ext)s"
        args += ["-o", (outputDirectory as NSString).appendingPathComponent(template)]
        args.append(url.absoluteString)
        return args
    }

    /// The path a resolver named, from either of the two lines yt-dlp prints when it is done.
    static func parseDestination(_ output: String) -> String? {
        let lines = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        for line in lines.reversed() {
            for marker in ["[download] Destination: ", "Merging formats into \"", "[ExtractAudio] Destination: "] {
                guard line.hasPrefix(marker) else { continue }
                var path = String(line.dropFirst(marker.count))
                if path.hasSuffix("\"") { path.removeLast() }
                if !path.isEmpty { return path }
            }
        }
        return nil
    }

    /// A JSON body for a self-hosted endpoint: the URL, the quality selector and the wanted name.
    static func endpointBody(for url: URL, options: MediaResolveOptions) -> Data? {
        var body: [String: String] = ["url": url.absoluteString, "format": options.quality.formatSelector]
        if options.mute { body["mute"] = "true" }
        if let name = options.requestedBaseName { body["filename"] = name }
        return try? JSONSerialization.data(withJSONObject: body)
    }
}
