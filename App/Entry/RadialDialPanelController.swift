import AppKit
import SwiftUI
import Combine

/// Phase 31e: Manages the floating, non-activating radial dial panel and handles keyboard/mouse invocation.
@MainActor
final class RadialDialPanelController: ObservableObject {
    static let shared = RadialDialPanelController()

    private final class RadialDialPanel: NonConstrainingPanel {
        override var canBecomeKey: Bool { false }
        override func cancelOperation(_ sender: Any?) { orderOut(nil) }
    }

    private var panel: NSPanel?
    private var outsideMonitor: Any?
    private var escKeyMonitor: Any?
    private var escLocalKeyMonitor: Any?
    private var mouseTriggerMonitor: Any?
    private var localMouseTriggerMonitor: Any?

    @Published private(set) var isShown: Bool = false
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "com.katikati.dial.enabled")
            setupMouseTriggerMonitor()
        }
    }

    @Published var theme: RadialDialTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: "com.katikati.dial.theme")
        }
    }

    @Published var mouseTrigger: RadialMouseTrigger {
        didSet {
            UserDefaults.standard.set(mouseTrigger.rawValue, forKey: "com.katikati.dial.mouseTrigger")
            setupMouseTriggerMonitor()
        }
    }

    @Published var triggerMode: RadialTriggerMode {
        didSet {
            UserDefaults.standard.set(triggerMode.rawValue, forKey: "com.katikati.dial.triggerMode")
        }
    }

    private var currentPageIndex: Int = 0
    private var pages: [RadialDialPage] = RadialDialPresets.defaultPages()

    init() {
        let storedEnabled = UserDefaults.standard.object(forKey: "com.katikati.dial.enabled") as? Bool ?? true
        let storedThemeRaw = UserDefaults.standard.string(forKey: "com.katikati.dial.theme") ?? RadialDialTheme.lilacGlass.rawValue
        let storedMouseRaw = UserDefaults.standard.string(forKey: "com.katikati.dial.mouseTrigger") ?? RadialMouseTrigger.off.rawValue
        let storedModeRaw = UserDefaults.standard.string(forKey: "com.katikati.dial.triggerMode") ?? RadialTriggerMode.tapToggle.rawValue

        self.isEnabled = storedEnabled
        self.theme = RadialDialTheme(rawValue: storedThemeRaw) ?? .lilacGlass
        self.mouseTrigger = RadialMouseTrigger(rawValue: storedMouseRaw) ?? .off
        self.triggerMode = RadialTriggerMode(rawValue: storedModeRaw) ?? .tapToggle

        setupMouseTriggerMonitor()
    }

    func toggle() {
        if isShown {
            dismiss()
        } else {
            show()
        }
    }

    func show() {
        guard isEnabled else { return }
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }

        let dialSize: CGFloat = 340
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let binding = Binding<Int>(
            get: { [weak self] in self?.currentPageIndex ?? 0 },
            set: { [weak self] in self?.currentPageIndex = $0 }
        )

        let rootView = RadialDialView(
            pages: pages,
            currentPageIndex: binding,
            theme: theme,
            onSelectAction: { [weak self] action in
                self?.handleAction(action)
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )

        let host = NSHostingView(rootView: rootView)
        host.frame = NSRect(x: 0, y: 0, width: dialSize, height: dialSize)
        panel.contentView = host

        // Position centered on cursor, clamped to screen visibleFrame
        let mouse = NSEvent.mouseLocation
        let visible = screen.visibleFrame
        let x = min(max(mouse.x - dialSize / 2, visible.minX + 8), visible.maxX - dialSize - 8)
        let y = min(max(mouse.y - dialSize / 2, visible.minY + 8), visible.maxY - dialSize - 8)

        panel.setFrame(NSRect(x: x, y: y, width: dialSize, height: dialSize), display: true)
        panel.orderFrontRegardless()
        isShown = true
        installOutsideMonitor()
        installEscMonitors()
    }

    func dismiss() {
        RadialSnapPreviewPanelController.shared.hidePreview()
        panel?.orderOut(nil)
        isShown = false
        removeOutsideMonitor()
        removeEscMonitors()
    }

    func tearDown() {
        dismiss()
        if let mouseTriggerMonitor {
            NSEvent.removeMonitor(mouseTriggerMonitor)
            self.mouseTriggerMonitor = nil
        }
        if let localMouseTriggerMonitor {
            NSEvent.removeMonitor(localMouseTriggerMonitor)
            self.localMouseTriggerMonitor = nil
        }
    }

    private func handleAction(_ action: RadialDialActionType) {
        dismiss()
        switch action {
        case .snap(let position):
            WindowSnapService.apply(position)
        case .launchApp(let bundleID, _):
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        case .mediaPlayPause:
            NowPlayingService().togglePlayPause()
        case .mediaNext:
            NowPlayingService().nextTrack()
        case .mediaPrevious:
            NowPlayingService().previousTrack()
        case .captureArea:
            Task.detached(priority: .userInitiated) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-i", "-c"] // Interactive to clipboard
                try? process.run()
            }
        case .captureWindow:
            Task.detached(priority: .userInitiated) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-i", "-w", "-c"] // Window to clipboard
                try? process.run()
            }
        case .captureOCR:
            BarActionService.run(.ocr)
        case .openShelf:
            AppDelegate.shared?.toggleShelf()
        case .clipboard:
            AppDelegate.shared?.commandBarPanel.toggle()
        case .toggleTiling:
            TilingEngine.shared.setEnabled(!TilingEngine.shared.isEnabled)
        case .page, .custom:
            break
        }
    }

    private func makePanel() -> NSPanel {
        let panel = RadialDialPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return panel
    }

    private func installOutsideMonitor() {
        guard outsideMonitor == nil else { return }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func removeOutsideMonitor() {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        outsideMonitor = nil
    }

    private func installEscMonitors() {
        guard escKeyMonitor == nil else { return }
        escKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                DispatchQueue.main.async {
                    self?.dismiss()
                }
            }
        }
        escLocalKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.dismiss()
                return nil
            }
            return event
        }
    }

    private func removeEscMonitors() {
        if let escKeyMonitor { NSEvent.removeMonitor(escKeyMonitor) }
        escKeyMonitor = nil
        if let escLocalKeyMonitor { NSEvent.removeMonitor(escLocalKeyMonitor) }
        escLocalKeyMonitor = nil
    }

    private func setupMouseTriggerMonitor() {
        if let mouseTriggerMonitor {
            NSEvent.removeMonitor(mouseTriggerMonitor)
            self.mouseTriggerMonitor = nil
        }
        if let localMouseTriggerMonitor {
            NSEvent.removeMonitor(localMouseTriggerMonitor)
            self.localMouseTriggerMonitor = nil
        }

        guard isEnabled && mouseTrigger != .off else { return }

        // Register global mouse event monitor matching rightMouseDown and otherMouseDown
        mouseTriggerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self else { return }
            if self.matchesMouseTrigger(event) {
                DispatchQueue.main.async {
                    self.toggle()
                }
            }
        }

        localMouseTriggerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self else { return event }
            if self.matchesMouseTrigger(event) {
                DispatchQueue.main.async {
                    self.toggle()
                }
                return nil
            }
            return event
        }
    }

    private func matchesMouseTrigger(_ event: NSEvent) -> Bool {
        switch mouseTrigger {
        case .off:
            return false
        case .middleClick:
            return event.type == .otherMouseDown && event.buttonNumber == 2
        case .controlRightClick:
            return event.type == .rightMouseDown && event.modifierFlags.contains(.control)
        case .optionRightClick:
            return event.type == .rightMouseDown && event.modifierFlags.contains(.option)
        case .commandRightClick:
            return event.type == .rightMouseDown && event.modifierFlags.contains(.command)
        case .button4:
            return event.type == .otherMouseDown && event.buttonNumber == 3
        case .button5:
            return event.type == .otherMouseDown && event.buttonNumber == 4
        }
    }
}
