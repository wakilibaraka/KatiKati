import AppKit

/// DiskView's menu-bar item: one status item showing the boot drive's free space, whose click menu
/// lists every mounted drive with its capacity bar. Off by default — enabling it is a Settings row
/// in the Menu Bar card, next to the metric readouts.
@MainActor
final class DriveMenuBarItem: NSObject, NSMenuDelegate {
    static let enabledKey = "com.katikati.menuBar.drives.enabled"

    private var item: NSStatusItem?
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var volumes: [DriveVolume] = []

    func start() {
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.apply() }
        }
        apply()
    }

    private var isOn: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    private func apply() {
        guard isOn else {
            timer?.invalidate()
            timer = nil
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            return
        }
        item = item ?? makeItem()
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func makeItem() -> NSStatusItem {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        statusItem.button?.image = NSImage(systemSymbolName: "internaldrive", accessibilityDescription: nil)
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        return statusItem
    }

    private func refresh() {
        volumes = DriveInventory.volumes()
        let boot = volumes.first
        item?.button?.title = boot.map { SystemMonitorFormat.bytes(Double($0.freeBytes)) } ?? "–"
        item?.button?.toolTip = boot?.capacityText
    }

    // MARK: - Menu (rebuilt on every open, so the bars are never stale)

    func menuNeedsUpdate(_ menu: NSMenu) {
        refresh()
        menu.removeAllItems()
        for volume in volumes {
            let row = NSMenuItem(title: "\(volume.name)  \(volume.capacityText)",
                                 action: #selector(openVolume(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = volume.mountPath
            row.image = Self.barImage(volume.usedFraction, removable: volume.isRemovable)
            menu.addItem(row)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: String(localized: "Open Settings…"), action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
    }

    @objc private func openVolume(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        (NSApp.delegate as? AppDelegate)?.openSettings(nil)
    }

    /// DiskView's bar: blue until the volume passes 90 %, red after. Not a template, so the colour
    /// survives the menu bar's monochrome rendering.
    private static func barImage(_ fraction: Double, removable: Bool) -> NSImage {
        let size = NSSize(width: 24, height: 12)
        let image = NSImage(size: size, flipped: false) { rect in
            let track = NSBezierPath(roundedRect: rect.insetBy(dx: 0, dy: 3), xRadius: 3, yRadius: 3)
            NSColor(white: 1, alpha: 0.25).setFill()
            track.fill()
            let f = min(max(fraction, 0), 1)
            guard f > 0 else { return true }
            let fill = NSRect(x: 0, y: 3, width: max(2, size.width * f), height: 6)
            (f > 0.9 ? NSColor.systemRed : removable ? NSColor.systemTeal : NSColor.systemBlue).setFill()
            NSBezierPath(roundedRect: fill, xRadius: 3, yRadius: 3).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
