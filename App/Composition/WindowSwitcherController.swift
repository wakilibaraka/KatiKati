import AppKit
import Carbon.HIToolbox
import Combine
import OSLog
import SwiftUI

/// Phase 20c — Option+Tab window switcher with live thumbnails (inspired by AltTab; written from the behaviour,
/// not copied). Idle cost is a Combine subscription on the snapshot (MRU bookkeeping) and two Carbon hot keys;
/// the 50 ms modifier timer exists only while the panel is on screen. No global event monitor, no new permission
/// beyond the Screen Recording grant already used by hover previews (without it tiles show the app icon).
@MainActor
final class WindowSwitcherController: ObservableObject {
    static let enabledKey = "com.katikati.switcher.enabled"

    struct Tile: Identifiable, Equatable {
        let id: String
        let title: String
        let appName: String
        let bundleID: String?
        let cgWindowID: CGWindowID?
        let isMinimized: Bool
    }

    @Published private(set) var tiles: [Tile] = []
    @Published private(set) var selection = 0
    @Published private(set) var thumbnails: [String: NSImage] = [:]

    private let runtime: AppRuntime
    private var mru: [String] = []
    private var snapshotSink: AnyCancellable?
    private var defaultsObserver: NSObjectProtocol?
    private var forward: GlobalHotKeyMonitor?
    private var backward: GlobalHotKeyMonitor?
    private var panel: SwitcherPanel?
    private var modifierTimer: Timer?
    private let log = Logger(subsystem: "com.caye.macosdockcc.v2", category: "switcher")

    init(runtime: AppRuntime) {
        self.runtime = runtime
    }

    /// Starts MRU tracking and registers the hot keys when the setting is on; re-applies on setting changes.
    func start() {
        snapshotSink = runtime.$snapshot.sink { [weak self] snapshot in self?.noteSnapshot(snapshot) }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.applyEnabled() }
        }
        applyEnabled()
    }

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    private func applyEnabled() {
        if isEnabled {
            guard forward == nil else { return }
            forward = makeMonitor(id: 20, reverse: false)
            backward = makeMonitor(id: 21, reverse: true)
        } else {
            forward?.stop(); backward?.stop()
            forward = nil; backward = nil
            if panel != nil { cancel() }
        }
    }

    private func makeMonitor(id: UInt32, reverse: Bool) -> GlobalHotKeyMonitor? {
        var mods = UInt32(optionKey)
        if reverse { mods |= UInt32(shiftKey) }
        let shortcut = GlobalHotKeyShortcut(keyCode: UInt32(kVK_Tab), carbonModifiers: mods,
                                            displayGlyphs: reverse ? "⌥⇧Tab" : "⌥Tab",
                                            signature: 0x5467_4567, id: id)
        let monitor = GlobalHotKeyMonitor(shortcut: shortcut) { [weak self] in self?.pressed(reverse: reverse) }
        let status = monitor.start()
        guard status == .registered else {
            log.warning("Window switcher \(shortcut.displayGlyphs, privacy: .public) not registered: \(String(describing: status), privacy: .public)")
            return nil
        }
        return monitor
    }

    // MARK: - MRU

    private static func isSwitchable(_ w: WindowRecord) -> Bool {
        switch w.status {
        case .active, .inactive, .minimized, .hidden: return true
        case .closedPending, .disappeared: return false
        }
    }

    private func noteSnapshot(_ snapshot: DockSnapshot) {
        let alive = Set(snapshot.windows.values.filter(Self.isSwitchable).map(\.id.rawValue))
        let active = snapshot.windows.values.first { $0.status == .active }?.id.rawValue
        let next = WindowSwitcherModel.updatedMRU(mru, active: active, alive: alive)
        if next != mru { mru = next }
    }

    // MARK: - Showing

    private func pressed(reverse: Bool) {
        if panel != nil {
            selection = WindowSwitcherModel.step(selection: selection, count: tiles.count, reverse: reverse)
            return
        }
        open(reverse: reverse)
    }

    private func open(reverse: Bool) {
        let snapshot = runtime.snapshot
        let records = snapshot.windows.values.filter(Self.isSwitchable)
        let byID = Dictionary(records.map { ($0.id.rawValue, $0) }, uniquingKeysWith: { a, _ in a })
        let ordered = WindowSwitcherModel.order(candidates: snapshot.orderedWindowIDs.map(\.rawValue).filter { byID[$0] != nil },
                                                mru: mru)
        tiles = ordered.compactMap { id in
            guard let w = byID[id] else { return nil }
            let app = NSRunningApplication(processIdentifier: w.pid)
            return Tile(id: id, title: w.title, appName: app?.localizedName ?? w.bundleIdentifier ?? "",
                        bundleID: w.bundleIdentifier, cgWindowID: w.cgWindowID, isMinimized: w.status == .minimized)
        }
        guard tiles.count > 1 else { tiles = []; return }
        selection = WindowSwitcherModel.initialSelection(count: tiles.count, reverse: reverse)
        thumbnails = [:]
        showPanel()
        loadThumbnails()
        startModifierWatch()
    }

    private func showPanel() {
        let host = NSHostingView(rootView: WindowSwitcherView(controller: self, onPick: { [weak self] i in
            self?.selection = i; self?.commit()
        }))
        let size = host.fittingSize
        let area = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        let panel = SwitcherPanel(frame: NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                                                width: size.width, height: size.height))
        panel.onKey = { [weak self] code in self?.handleKey(code) }
        panel.contentView = host
        panel.orderFrontRegardless()
        panel.makeKey()
        self.panel = panel
    }

    private func loadThumbnails() {
        guard WindowThumbnailCapture.isAuthorized else { return }
        for tile in tiles {
            guard let cg = tile.cgWindowID, !tile.isMinimized else { continue }
            WindowThumbnailCapture.capture(windowID: cg, maxPixelSize: CGSize(width: 520, height: 320)) { [weak self] image in
                guard let self, self.panel != nil, let image else { return }
                self.thumbnails[tile.id] = image
            }
        }
    }

    private func startModifierWatch() {
        modifierTimer?.invalidate()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.panel != nil else { return }
                if !NSEvent.modifierFlags.contains(.option) { self.commit() }
            }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        modifierTimer = timer
    }

    private func handleKey(_ code: UInt16) {
        switch Int(code) {
        case kVK_Escape: cancel()
        case kVK_RightArrow: selection = WindowSwitcherModel.step(selection: selection, count: tiles.count, reverse: false)
        case kVK_LeftArrow: selection = WindowSwitcherModel.step(selection: selection, count: tiles.count, reverse: true)
        case kVK_Return: commit()
        default: break
        }
    }

    private func commit() {
        let chosen = tiles.indices.contains(selection) ? tiles[selection].id : nil
        close()
        if let chosen { runtime.activate(windowID: chosen) }
    }

    private func cancel() { close() }

    private func close() {
        modifierTimer?.invalidate(); modifierTimer = nil
        panel?.orderOut(nil); panel = nil
        tiles = []; thumbnails = [:]
    }
}

/// Borderless floating panel that can take key presses (Esc, arrows) without activating KatiKati.
private final class SwitcherPanel: NSPanel {
    var onKey: ((UInt16) -> Void)?

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = PanelCollectionBehavior.standard
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) { onKey?(event.keyCode) }
}

private struct WindowSwitcherView: View {
    @ObservedObject var controller: WindowSwitcherController
    let onPick: (Int) -> Void

    var body: some View {
        let columns = WindowSwitcherModel.columns(count: controller.tiles.count)
        let indexed = Array(controller.tiles.enumerated())
        let rows = stride(from: 0, to: indexed.count, by: columns).map { Array(indexed[$0..<min($0 + columns, indexed.count)]) }
        VStack(spacing: 10) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 10) {
                    ForEach(rows[r], id: \.element.id) { index, tile in
                        tileView(tile, selected: index == controller.selection)
                            .onTapGesture { onPick(index) }
                    }
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(20)
    }

    private func tileView(_ tile: WindowSwitcherController.Tile, selected: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.18))
                if let image = controller.thumbnails[tile.id] {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(4)
                } else if let id = tile.bundleID {
                    Image(nsImage: AppIconResolver.icon(for: id)).resizable().frame(width: 52, height: 52)
                        .opacity(tile.isMinimized ? 0.5 : 1)
                }
            }
            .frame(height: 104)
            HStack(spacing: 5) {
                if let id = tile.bundleID {
                    Image(nsImage: AppIconResolver.icon(for: id)).resizable().frame(width: 16, height: 16)
                }
                Text(verbatim: tile.title.isEmpty ? tile.appName : tile.title)
                    .font(.system(size: 11, weight: .medium)).lineLimit(1)
            }
        }
        .padding(8)
        .frame(width: 196)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(selected ? Color.accentColor.opacity(0.28) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
    }
}
