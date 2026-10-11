import AppKit
import CoreImage

/// The launcher's backdrop layers (Phase 7B-L6): system blur, a blurred desktop picture, and an optional colour wash.
/// The desktop picture is downscaled before blurring (cheap) and cached per file + modification date.
@MainActor
final class LauncherBackdrop: NSView {
    private let blur = NSVisualEffectView()
    private let picture = NSImageView()
    private let wash = NSView()
    private static var pictureCache: (key: String, image: NSImage)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        for v in [blur, picture, wash] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: leadingAnchor), v.trailingAnchor.constraint(equalTo: trailingAnchor),
                v.topAnchor.constraint(equalTo: topAnchor), v.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        blur.blendingMode = .behindWindow
        blur.state = .active
        picture.imageScaling = .scaleAxesIndependently
        wash.wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("code-only") }

    /// Applies a theme + tint. Returns the appearance the hosted SwiftUI should use (nil = follow the system).
    func apply(theme: LauncherTheme, tint: LauncherTint, screen: NSScreen) -> NSAppearance? {
        var appearance: NSAppearance?
        var showPicture = false
        switch theme {
        case .system: blur.material = .fullScreenUI
        case .light: blur.material = .popover; appearance = NSAppearance(named: .aqua)
        case .dark: blur.material = .fullScreenUI; appearance = NSAppearance(named: .darkAqua)
        case .glass: blur.material = .underWindowBackground
        case .desktop:
            if let image = Self.blurredDesktop(for: screen) {
                picture.image = image
                showPicture = true
                appearance = NSAppearance(named: .darkAqua)
            } else {
                blur.material = .fullScreenUI
            }
        }
        picture.isHidden = !showPicture
        blur.isHidden = showPicture
        if let c = tint.rgb {
            wash.layer?.backgroundColor = NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: LauncherTint.washOpacity).cgColor
        } else {
            wash.layer?.backgroundColor = showPicture ? NSColor.black.withAlphaComponent(0.25).cgColor : nil
        }
        blur.appearance = appearance
        return appearance
    }

    private static func blurredDesktop(for screen: NSScreen) -> NSImage? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen), !url.hasDirectoryPath else { return nil }
        let stamp = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)|\(stamp)"
        if let hit = pictureCache, hit.key == key { return hit.image }
        guard let source = NSImage(contentsOf: url), let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let targetW = 480.0
        let scale = targetW / Double(cg.width)
        let ci = CIImage(cgImage: cg).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let blurred = ci.clampedToExtent().applyingGaussianBlur(sigma: 10).cropped(to: ci.extent)
        let rep = NSCIImageRep(ciImage: blurred)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        pictureCache = (key, image)
        return image
    }
}
