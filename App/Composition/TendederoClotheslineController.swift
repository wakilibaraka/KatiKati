import AppKit
import Foundation
import QuickLookUI

// MARK: - Slice T-2: Tendedero Left Sidebar Clothesline

@MainActor
final class TendederoClotheslineController: NSObject, ObservableObject, QLPreviewPanelDataSource {
    static let shared = TendederoClotheslineController()
    static let unlimitedKey = "com.katikati.tendedero.unlimited"

    @Published private(set) var store = TendederoStore()
    @Published var selectedID: UUID?
    @Published var copiedID: UUID?
    /// NP-1: manual unless the owner opted into auto-hanging, so a copy never takes the screen on its own.
    @Published var captureMode: TendederoCaptureMode = TendederoPolicy.captureMode()
    @Published var unlimitedCapacity: Bool = UserDefaults.standard.bool(forKey: TendederoClotheslineController.unlimitedKey)

    var onNewScreenshot: (() -> Void)?

    private var started = false
    private var screenshotQuery: NSMetadataQuery?
    nonisolated(unsafe) private var queryObservers: [NSObjectProtocol] = []
    private var seenScreenshotPaths: Set<String> = []
    private var clipboardObserverID: UUID?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var physicsTimer: Timer?
    private var previewURL: URL?

    deinit {
        for token in queryObservers {
            NotificationCenter.default.removeObserver(token)
        }
        queryObservers.removeAll()
    }

    func start() {
        guard !started else { return }
        started = true
        applyCapacityMode()
        startScreenshotQuery()
        reconcilePasteboardWatch()
    }

    func setCaptureMode(_ mode: TendederoCaptureMode) {
        captureMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: TendederoPolicy.captureModeKey)
        if started { reconcilePasteboardWatch() }
    }

    func setUnlimitedCapacity(_ unlimited: Bool) {
        unlimitedCapacity = unlimited
        UserDefaults.standard.set(unlimited, forKey: Self.unlimitedKey)
        applyCapacityMode()
    }

    private func applyCapacityMode() {
        store.capacityMode = unlimitedCapacity ? .unlimited : .default
        store.pruneExpired()
    }

    func hangCurrentClipboard() {
        let pb = NSPasteboard.general
        lastChangeCount = pb.changeCount
        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL], let first = urls.first {
            if first.isFileURL {
                addAndAnimate(kind: .screenshot(url: first), title: first.lastPathComponent)
            } else {
                addAndAnimate(kind: .link(first), title: first.host ?? first.absoluteString)
            }
            return
        }
        if let image = NSImage(pasteboard: pb), let tiff = image.tiffRepresentation {
            addAndAnimate(kind: .imageData(tiff), title: "Image \(Int(image.size.width))×\(Int(image.size.height))")
            return
        }
        if let text = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            addAndAnimate(kind: .text(text), title: String(text.prefix(48)))
        }
    }

    func hangDroppedURL(_ url: URL) {
        if url.isFileURL {
            addAndAnimate(kind: .screenshot(url: url), title: url.lastPathComponent)
        } else {
            addAndAnimate(kind: .link(url), title: url.host ?? url.absoluteString)
        }
    }

    func togglePin(_ id: UUID) { store.togglePin(id: id); startPhysicsIfNeeded() }
    func remove(_ id: UUID) { store.remove(id: id) }
    func clearUnpinned() { store.clearUnpinned() }
    func markAllRead() { store.markAllRead() }
    func hover(_ id: UUID) { store.applyImpulse(id: id, degrees: 5); startPhysicsIfNeeded() }

    func copy(_ item: TendederoItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .screenshot(let url):
            if let img = NSImage(contentsOf: url) { pb.writeObjects([img, url as NSURL]) }
            else { pb.writeObjects([url as NSURL]) }
        case .imageData(let data):
            if let img = NSImage(data: data) { pb.writeObjects([img]) }
        case .link(let url):
            pb.writeObjects([url as NSURL])
        case .text(let text):
            pb.setString(text, forType: .string)
        }
        lastChangeCount = pb.changeCount
        copiedID = item.id
        store.applyImpulse(id: item.id, degrees: -8)
        startPhysicsIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            if self?.copiedID == item.id { self?.copiedID = nil }
        }
    }

    func open(_ item: TendederoItem) {
        switch item.kind {
        case .screenshot(let url), .link(let url):
            NSWorkspace.shared.open(url)
        case .imageData(let data):
            if let temp = writeTempFile(data: data, ext: "png") { NSWorkspace.shared.open(temp) }
        case .text:
            copy(item)
        }
    }

    func quickLook(_ item: TendederoItem) {
        switch item.kind {
        case .screenshot(let url): previewURL = url
        case .link(let url): previewURL = url
        case .imageData(let data): previewURL = writeTempFile(data: data, ext: "png")
        case .text(let text): previewURL = writeTempFile(data: Data(text.utf8), ext: "txt")
        }
        guard previewURL != nil, let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        if panel.isVisible { panel.reloadData() } else { panel.makeKeyAndOrderFront(nil) }
    }

    func dragProvider(for item: TendederoItem) -> NSItemProvider {
        switch item.kind {
        case .screenshot(let url): return NSItemProvider(object: url as NSURL)
        case .link(let url): return NSItemProvider(object: url as NSURL)
        case .imageData(let data):
            if let img = NSImage(data: data) { return NSItemProvider(object: img) }
            return NSItemProvider(object: item.title as NSString)
        case .text(let text): return NSItemProvider(object: text as NSString)
        }
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { 1 }
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { previewURL as NSURL? }
    }

    private func addAndAnimate(kind: TendederoItemKind, title: String) {
        _ = store.add(kind: kind, title: title)
        startPhysicsIfNeeded()
    }

    private func startPhysicsIfNeeded() {
        guard physicsTimer == nil else { return }
        physicsTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.store.tickPhysics(dt: 1.0 / 60.0)
                let active = self.store.items.contains { $0.swingAngleDegrees != 0 || $0.swingVelocity != 0 }
                if !active { self.physicsTimer?.invalidate(); self.physicsTimer = nil }
            }
        }
    }

    private func reconcilePasteboardWatch() {
        if let id = clipboardObserverID {
            ProductivityServices.shared.clipboard.removeRawChangeObserver(id)
            clipboardObserverID = nil
        }
        guard captureMode == .screenshotsAndAutoClipboard else { return }
        clipboardObserverID = ProductivityServices.shared.clipboard.addRawChangeObserver { [weak self] in
            guard let self, self.captureMode == .screenshotsAndAutoClipboard else { return }
            let count = NSPasteboard.general.changeCount
            guard count != self.lastChangeCount else { return }
            self.hangCurrentClipboard()
        }
    }

    private func startScreenshotQuery() {
        for token in queryObservers {
            NotificationCenter.default.removeObserver(token)
        }
        queryObservers.removeAll()
        screenshotQuery?.stop()

        let q = NSMetadataQuery()
        q.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        q.searchScopes = [NSMetadataQueryUserHomeScope]
        q.sortDescriptors = [NSSortDescriptor(key: kMDItemFSCreationDate as String, ascending: false)]
        let finishObs = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.seedInitialScreenshots(q) }
        }
        let updateObs = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate, object: q, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.ingestNewScreenshots(q) }
        }
        queryObservers = [finishObs, updateObs]
        q.start()
        screenshotQuery = q
    }

    private func seedInitialScreenshots(_ q: NSMetadataQuery) {
        q.disableUpdates()
        defer { q.enableUpdates() }
        for item in q.results.prefix(30) {
            if let md = item as? NSMetadataItem, let path = md.value(forAttribute: NSMetadataItemPathKey) as? String {
                seenScreenshotPaths.insert(path)
            }
        }
    }

    private func ingestNewScreenshots(_ q: NSMetadataQuery) {
        q.disableUpdates()
        defer { q.enableUpdates() }
        var added = false
        for item in q.results.prefix(10) {
            guard let md = item as? NSMetadataItem,
                  let path = md.value(forAttribute: NSMetadataItemPathKey) as? String,
                  !seenScreenshotPaths.contains(path) else { continue }
            seenScreenshotPaths.insert(path)
            let url = URL(fileURLWithPath: path)
            addAndAnimate(kind: .screenshot(url: url), title: url.lastPathComponent)
            added = true
        }
        if added { onNewScreenshot?() }
    }

    private func writeTempFile(data: Data, ext: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tendedero-preview.\(ext)")
        try? data.write(to: url)
        return url
    }
}
