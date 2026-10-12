import AppKit

/// Phase 8e — screen colour picker: the system's eyedropper (`NSColorSampler`, no permission), result
/// copied to the clipboard as `#RRGGBB` and confirmed with the shortcut toast.
@MainActor
final class ColorPickerService {
    private var sampler: NSColorSampler?
    private let toast: ShortcutToastPresenter

    init(toast: ShortcutToastPresenter) { self.toast = toast }

    func pick() {
        guard sampler == nil else { return }
        let s = NSColorSampler()
        sampler = s
        s.show { [weak self] color in
            Task { @MainActor in
                guard let self else { return }
                self.sampler = nil
                guard let rgb = color?.usingColorSpace(.sRGB) else { return }   // nil = user cancelled
                let hex = ColorFormat.hex(red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent))
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(hex, forType: .string)
                self.toast.show(hex, symbol: "eyedropper")
            }
        }
    }
}
