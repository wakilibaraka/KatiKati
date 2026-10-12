import AppKit
import AVFoundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

/// Dropover-style actions on shelf items: zip, compress (images via ImageIO, videos via AVFoundation) and
/// share / AirDrop. Results land back on the shelf. The heavy work runs off the main thread; nothing here
/// asks for a new permission.
@MainActor
enum ShelfActions {
    private static let logger = Logger(subsystem: "com.katikati.app", category: "shelf")

    enum Failure: Error { case unsupported, failed }

    // MARK: kinds

    static func isImage(_ url: URL) -> Bool { (UTType(filenameExtension: url.pathExtension)?.conforms(to: .image)) ?? false }
    static func isVideo(_ url: URL) -> Bool { (UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie)) ?? false }
    static func canCompress(_ url: URL) -> Bool { isImage(url) || isVideo(url) }

    // MARK: zip

    /// Zips `urls` into one archive next to the first item (or in Downloads if that folder isn't writable).
    static func zip(_ urls: [URL], into shelf: ShelfStore) {
        guard let first = urls.first else { return }
        let name = urls.count == 1 ? first.deletingPathExtension().lastPathComponent : "Shelf Archive"
        let folder = destinationFolder(for: first)
        Task {
            do {
                let out = try await Task.detached(priority: .userInitiated) { try makeZip(urls: urls, name: name, in: folder) }.value
                shelf.stash(paths: [out.path])
            } catch {
                logger.error("zip failed: \(String(describing: error), privacy: .public)")
                NSSound.beep()
            }
        }
    }

    nonisolated private static func makeZip(urls: [URL], name: String, in folder: URL) throws -> URL {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("katikati-zip-\(UUID().uuidString)", isDirectory: true)
        let bundle = staging.appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        for url in urls { try fm.copyItem(at: url, to: bundle.appendingPathComponent(url.lastPathComponent)) }
        let out = uniqueURL(folder.appendingPathComponent("\(name).zip"))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", bundle.path, out.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.failed }
        return out
    }

    // MARK: compress

    static func compress(_ urls: [URL], into shelf: ShelfStore) {
        for url in urls where canCompress(url) {
            let folder = destinationFolder(for: url)
            Task {
                do {
                    let out: URL
                    if isImage(url) {
                        out = try await Task.detached(priority: .userInitiated) { try compressImage(url, in: folder) }.value
                    } else {
                        out = try await compressVideo(url, in: folder)
                    }
                    shelf.stash(paths: [out.path])
                } catch {
                    logger.error("compress failed: \(String(describing: error), privacy: .public)")
                    NSSound.beep()
                }
            }
        }
    }

    /// JPEG at 60 % quality (HEIC when the image has transparency, since JPEG can't keep it).
    nonisolated private static func compressImage(_ url: URL, in folder: URL) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw Failure.unsupported
        }
        let alpha: Bool
        switch image.alphaInfo { case .none, .noneSkipFirst, .noneSkipLast: alpha = false; default: alpha = true }
        let type = alpha ? "public.heic" : "public.jpeg"
        let ext = alpha ? "heic" : "jpg"
        let out = uniqueURL(folder.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent) compressed.\(ext)"))
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, type as CFString, 1, nil) else { throw Failure.unsupported }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.6] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw Failure.failed }
        return out
    }

    /// 720p MP4 via the system export preset.
    private static func compressVideo(_ url: URL, in folder: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else { throw Failure.unsupported }
        let out = uniqueURL(folder.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent) compressed.mp4"))
        session.outputURL = out
        session.outputFileType = .mp4
        return try await withCheckedThrowingContinuation { continuation in
            session.exportAsynchronously {
                if session.status == .completed { continuation.resume(returning: out) } else { continuation.resume(throwing: session.error ?? Failure.failed) }
            }
        }
    }

    // MARK: share

    static func airDrop(_ urls: [URL]) {
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
    }

    /// The system share sheet, anchored at the pointer through a throwaway invisible window (the shelf
    /// popup is a non-activating panel with no view to anchor on from a menu action).
    static func share(_ urls: [URL]) {
        let mouse = NSEvent.mouseLocation
        let anchor = NSWindow(contentRect: NSRect(x: mouse.x, y: mouse.y, width: 1, height: 1), styleMask: .borderless, backing: .buffered, defer: false)
        anchor.backgroundColor = .clear
        anchor.level = .popUpMenu
        anchor.isReleasedWhenClosed = false
        anchor.orderFrontRegardless()
        guard let view = anchor.contentView else { return }
        let picker = NSSharingServicePicker(items: urls)
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { anchor.close() }
    }

    // MARK: helpers

    nonisolated private static func destinationFolder(for url: URL) -> URL {
        let dir = url.deletingLastPathComponent()
        if FileManager.default.isWritableFile(atPath: dir.path) { return dir }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
    }

    nonisolated private static func uniqueURL(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension, dir = url.deletingLastPathComponent()
        for i in 2...999 {
            let candidate = dir.appendingPathComponent("\(base) \(i)").appendingPathExtension(ext)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
    }
}
