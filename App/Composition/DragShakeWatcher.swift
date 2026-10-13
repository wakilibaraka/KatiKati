import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// "Shake to shelf": while a file drag is in progress, a quick left-right shake of the pointer pops a
/// small drop target near the cursor that parks the dropped files on the shelf.
///
/// No global event tap (resident mouse monitors are banned by the project rules). A low-rate (8 Hz,
/// loose tolerance) timer reads `NSEvent.pressedMouseButtons` and the drag pasteboard's change count; only
/// once a *file* drag is detected does it sample the pointer at 60 Hz into the pure `ShakeDetector`, and
/// only until the button is released. That 5 Hz check is the one resident poll — its cost is measured in
/// the HYBRID_PLAN check log.
@MainActor
final class DragShakeWatcher {
    private let shelf: ShelfStore
    private var idleTimer: Timer?
    private var sampleTimer: Timer?
    private var detector = ShakeDetector()
    private var baselineChangeCount = NSPasteboard(name: .drag).changeCount
    private var dropTarget: ShelfDropTargetPanel?
    private var epoch = Date()

    init(shelf: ShelfStore) { self.shelf = shelf }

    func setEnabled(_ enabled: Bool) {
        enabled ? start() : stop()
    }

    private func start() {
        guard idleTimer == nil else { return }
        baselineChangeCount = NSPasteboard(name: .drag).changeCount
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.idleTick() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    private func stop() {
        idleTimer?.invalidate(); idleTimer = nil
        endSampling()
        dropTarget?.close(); dropTarget = nil
    }

    private var leftDown: Bool { NSEvent.pressedMouseButtons & 1 != 0 }

    /// Reads only `pressedMouseButtons` (no IPC) while the button is up; the drag pasteboard (an IPC round
    /// trip) is touched only while a button is held. A drag session is recognised by the pasteboard's change
    /// count differing from the last session already handled.
    private func idleTick() {
        guard leftDown, sampleTimer == nil else { return }
        let board = NSPasteboard(name: .drag)
        guard board.changeCount != baselineChangeCount,
              board.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return }
        beginSampling()
    }

    private func beginSampling() {
        baselineChangeCount = NSPasteboard(name: .drag).changeCount
        detector.reset()
        epoch = Date()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleTick() }
        }
        timer.tolerance = 0.004
        RunLoop.main.add(timer, forMode: .common)
        sampleTimer = timer
    }

    private func sampleTick() {
        guard leftDown else { endSampling(); return }
        let location = NSEvent.mouseLocation
        if detector.add(x: Double(location.x), at: Date().timeIntervalSince(epoch)), dropTarget == nil {
            shelf.pulseForShake()
            let panel = ShelfDropTargetPanel(shelf: shelf)
            panel.present(near: location)
            dropTarget = panel
        }
    }

    private func endSampling() {
        sampleTimer?.invalidate(); sampleTimer = nil
        baselineChangeCount = NSPasteboard(name: .drag).changeCount   // this session is handled
        // The drop lands as the button comes up; leave the target a beat so it can accept, then remove it.
        if let panel = dropTarget {
            dropTarget = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { panel.close() }
        }
    }
}

/// The floating drop zone shown after a shake.
@MainActor
final class ShelfDropTargetPanel {
    private let panel: NSPanel
    private let model = ShelfDropTargetModel()

    init(shelf: ShelfStore) {
        model.itemCount = shelf.itemPaths.count
        model.onDrop = { urls in shelf.stash(paths: urls.map(\.path)) }
        let size = CGSize(width: 220, height: 120)
        panel = NSPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        let host = NSHostingView(rootView: ShelfDropTargetView(model: model))
        host.frame = CGRect(origin: .zero, size: size)
        panel.contentView = host
    }

    func present(near cursor: CGPoint) {
        let size = panel.frame.size
        panel.setFrameOrigin(CGPoint(x: cursor.x - size.width / 2, y: cursor.y + 28))
        panel.orderFrontRegardless()
    }

    func close() { panel.orderOut(nil) }
}

@MainActor
final class ShelfDropTargetModel: ObservableObject {
    @Published var isTargeted = false
    @Published var dropped = 0
    @Published var itemCount = 0
    var onDrop: ([URL]) -> Void = { _ in }
}

struct ShelfDropTargetView: View {
    @ObservedObject var model: ShelfDropTargetModel

    var body: some View {
        VStack(spacing: 8) {
            ShelfTrayArt(size: 44, lifted: model.isTargeted, state: ShelfIconState.from(count: model.itemCount))
            Group {
                if model.dropped > 0 { Text("Added to Shelf") } else { Text("Drop to Shelf") }
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(model.isTargeted ? Color.accentColor : Color.white.opacity(0.2), lineWidth: model.isTargeted ? 2 : 1))
        .onDrop(of: [UTType.fileURL], isTargeted: $model.isTargeted) { providers in
            var urls: [URL] = []
            let group = DispatchGroup()
            for provider in providers {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) { urls.append(url) }
                    else if let url = item as? URL { urls.append(url) }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                guard !urls.isEmpty else { return }
                model.onDrop(urls)
                model.dropped += urls.count
            }
            return true
        }
        .animation(.easeOut(duration: 0.12), value: model.isTargeted)
    }
}
