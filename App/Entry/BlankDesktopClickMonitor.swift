import AppKit
import CoreGraphics

/// Optional, lazy passive detector for double-clicking an empty desktop area to toggle/reveal desktop boxes.
@MainActor
final class BlankDesktopClickMonitor {
    private var monitor: Any?
    private let onDoubleClick: () -> Void

    init(onDoubleClick: @escaping () -> Void) {
        self.onDoubleClick = onDoubleClick
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard event.clickCount == 2 else { return }
            let appKitPoint = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                guard let self, self.isBlankDesktop(at: appKitPoint) else { return }
                self.onDoubleClick()
            }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    private func isBlankDesktop(at appKitPoint: CGPoint) -> Bool {
        if NSApp.windows.contains(where: { $0.isVisible && $0.frame.contains(appKitPoint) }) {
            return false
        }
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let quartzPoint = CGPoint(x: appKitPoint.x, y: primaryHeight - appKitPoint.y)

        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }

        for entry in list {
            let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer >= 0 else { continue }
            let alpha = (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard alpha > 0.01 else { continue }
            guard let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary else { continue }
            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &rect) else { continue }
            guard rect.width >= 2, rect.height >= 2 else { continue }
            if rect.contains(quartzPoint) { return false }
        }
        return true
    }
}
