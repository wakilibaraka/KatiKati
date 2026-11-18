import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

/// Clipboard history (Phase 7A-P4): click a row to copy it back. Recording is opt-in and memory-only.
struct ClipboardFlyoutView: View {
    /// SD-2: the deck's one search field filters this list too.
    var query: String = ""
    @ObservedObject private var monitor = ProductivityServices.shared.clipboard
    @AppStorage(TilePalette.storageKey) private var palette: TilePalette = .classic
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.edgeBarStyle) private var barStyle
    @State private var copiedID: UUID?
    @State private var selectedID: UUID?
    @State private var hoveredEntry: ClipEntry?
    @State private var hoverWork: DispatchWorkItem?
    @State private var confirmingClear = false
    @State private var selectedCategory: ClipboardCategory = .all
    // Slice MC-3: Maccy's keyboard-first bits — sorting, pin badges, footer hints and auto-paste.
    @AppStorage(ClipboardSettingsKeys.sortBy) private var sortBy = ClipboardSortOrder.lastCopied.rawValue
    @AppStorage(ClipboardSettingsKeys.showFooterShortcuts) private var showFooter = true
    @AppStorage(ClipboardSettingsKeys.showPinShortcuts) private var showPinShortcuts = true
    @AppStorage(ClipboardSettingsKeys.pasteAutomatically) private var pasteAutomatically = false
    @State private var pinSlots: [UUID: Int] = [:]

    init(query: String = "") {
        self.query = query
    }

    var body: some View {
        let size = ProductivityFlyout.size(.clipboard)
        let env = TileEnv(palette: palette, isDark: colorScheme == .dark, glass: barStyle == .liquidGlass)
        BandTile(env: env, kind: .countdown, width: size.width - 16, height: size.height - 16, header: {
            HStack {
                Text("Clipboard")
                if monitor.captureMode == .paused {
                    capturePill(Text("Paused"), env: env)
                } else if monitor.captureMode.isSkippingNextCopy {
                    capturePill(Text("Skipping Next Copy"), env: env)
                }
                Spacer()
                if !monitor.history.entries.isEmpty {
                    Button { confirmingClear = true } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).help(Text("Clear History"))
                }
                Toggle(isOn: Binding(get: { monitor.isRecording }, set: { monitor.setRecording($0) })) { EmptyView() }
                    .toggleStyle(.switch).labelsHidden().scaleEffect(0.7).help(Text("Record Clipboard"))
            }
        }, content: {
            if !monitor.isRecording && monitor.history.entries.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Clipboard history is off").font(.system(size: 12, weight: .semibold))
                    Text("Turn it on to remember text you copy. History stays in memory only and is never saved, and copies marked secret by password managers are skipped.")
                        .font(.system(size: 11)).foregroundColor(env.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 6)
            } else if visibleEntries.isEmpty {
                Text("Nothing copied yet").font(.system(size: 12, weight: .semibold)).foregroundColor(env.secondary).padding(.top, 4)
            } else {
                HStack(spacing: 4) {
                    ForEach(ClipboardCategory.allCases) { cat in
                        Button {
                            selectedCategory = cat
                        } label: {
                            Text(verbatim: cat.rawValue.capitalized)
                                .font(.system(size: 10, weight: selectedCategory == cat ? .bold : .medium))
                                .foregroundColor(selectedCategory == cat ? .white : env.secondary)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(selectedCategory == cat ? Color.white.opacity(0.18) : Color.clear))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 4)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleEntries) { entry in row(entry, env: env) }
                    }
                }
                .popover(item: $hoveredEntry, arrowEdge: .trailing) { entry in
                    ScrollView {
                        Text(verbatim: entry.text)
                            .font(.system(size: 12))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(width: 300)
                    .frame(maxHeight: 240)
                }
                if showFooter {
                    Text(verbatim: "⏎ Copy · ⌥⏎ Paste · ⌥⇧⏎ Plain · ⌥P Pin")
                        .font(.system(size: 9)).foregroundColor(env.secondary).padding(.top, 4)
                }
            }
        })
        .padding(8)
        .focusable()
        .onKeyPress { press in handleKey(press) }
        .onAppear {
            refreshPinSlots()
            syncSelection()
        }
        .onChange(of: monitor.history.displayOrder.map(\.id)) { _ in
            refreshPinSlots()
            syncSelection()
        }
        .onChange(of: selectedCategory) { _ in syncSelection() }
        .onChange(of: query) { _ in syncSelection() }
        .confirmationDialog(Text("Clear Clipboard History?"), isPresented: $confirmingClear) {
            Button("Clear History", role: .destructive) { monitor.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pinned entries stay; everything else is forgotten. History is never saved to disk.")
        }
    }

    private func capturePill(_ title: Text, env: TileEnv) -> some View {
        title
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(env.secondary.opacity(0.18)))
    }

    /// MC-3: ⌘1–⌘9 stay with their pin while the history churns; only the gaps move.
    private func refreshPinSlots() {
        pinSlots = MaccyPinShortcutAssigner.assign(
            pinnedIDs: monitor.history.displayOrder.filter(\.pinned).map(\.id),
            previous: pinSlots
        )
    }

    private func syncSelection() {
        let entries = visibleEntries
        if let selectedID, entries.contains(where: { $0.id == selectedID }) { return }
        selectedID = entries.first?.id
    }

    private func moveSelection(by delta: Int) {
        let entries = visibleEntries
        guard !entries.isEmpty else { selectedID = nil; return }
        let current = selectedID.flatMap { id in entries.firstIndex(where: { $0.id == id }) } ?? 0
        let next = min(max(current + delta, 0), entries.count - 1)
        selectedID = entries[next].id
    }

    /// MC-3: Maccy's table, applied to the highlighted row (hover or arrow keys, first row by default).
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .upArrow { moveSelection(by: -1); return .handled }
        if press.key == .downArrow { moveSelection(by: 1); return .handled }
        guard let action = MaccyKeyAction.action(key: String(press.characters),
                                                 modifiers: MaccyKeyAction.Modifiers(press.modifiers)),
              let target = visibleEntries.first(where: { $0.id == selectedID }) ?? visibleEntries.first else { return .ignored }
        switch action {
        case .copy: monitor.copy(target)
        case .paste, .pastePlain: monitor.pastePlain(target)
        case .togglePin: monitor.togglePin(target.id)
        case .delete: monitor.remove(target.id)
        case .clearUnpinned: monitor.clearAll(keepingPinned: true)
        case .clearAll: monitor.clearAll(keepingPinned: false)
        }
        return .handled
    }

    private var visibleEntries: [ClipEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty
            ? monitor.history.displayOrder
            : monitor.history.displayOrder.filter { $0.text.localizedStandardContains(trimmed) }
        // MC-3: pins first in every order; the sort only decides among peers.
        let pinned = base.filter(\.pinned)
        var rest = base.filter { !$0.pinned }
        switch ClipboardSortOrder(rawValue: sortBy) ?? .lastCopied {
        case .lastCopied: break
        case .firstCopied: rest.reverse()
        case .mostUsed: rest.sort { $0.copyCount > $1.copyCount }
        }
        return pinned + rest
    }

    @ViewBuilder
    private func row(_ entry: ClipEntry, env: TileEnv) -> some View {
        let meta = ClipboardCardMetadata.classify(text: entry.text)
        if selectedCategory == .all || meta.category == selectedCategory {
            Button {
                if pasteAutomatically { monitor.pastePlain(entry) } else { monitor.copy(entry) }
                copiedID = entry.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { if copiedID == entry.id { copiedID = nil } }
            } label: {
                HStack(spacing: 6) {
                    if entry.pinned {
                        Image(systemName: "pin.fill").font(.system(size: 9)).foregroundColor(env.accent(.countdown))
                        if showPinShortcuts, let slot = pinSlots[entry.id] {
                            Text(verbatim: "⌘\(slot)")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(env.secondary)
                        }
                    }
                    switch meta.contentType {
                    case .hexColor(let hex, let color):
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(red: color.r, green: color.g, blue: color.b))
                            .frame(width: 12, height: 12)
                        Text(verbatim: hex).font(.system(size: 11, design: .monospaced))
                    case .text(let chars, let words):
                        Text(verbatim: ClipboardHistory.previewLine(entry.text)).font(.system(size: 12)).lineLimit(2)
                        Text(verbatim: "\(chars)c·\(words)w").font(.system(size: 9)).foregroundColor(env.secondary)
                    case .image(let w, let h):
                        Image(systemName: "photo").font(.system(size: 10))
                        Text(verbatim: "\(w)×\(h)").font(.system(size: 10)).foregroundColor(env.secondary)
                    }
                    Spacer(minLength: 4)
                    if copiedID == entry.id { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                }
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selectedID == entry.id ? Color.accentColor.opacity(0.18) : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                hoverWork?.cancel()
                if hovering {
                    selectedID = entry.id
                    if entry.text.count > 60 || entry.text.contains("\n") {
                        let work = DispatchWorkItem { hoveredEntry = entry }
                        hoverWork = work
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
                    } else {
                        hoveredEntry = nil
                    }
                } else if hoveredEntry?.id == entry.id {
                    hoveredEntry = nil
                }
            }
            .contextMenu {
                Button("Paste as Plain Text") { monitor.pastePlain(entry) }
                if entry.pinned { Button("Unpin") { monitor.togglePin(entry.id) } } else { Button("Pin") { monitor.togglePin(entry.id) } }
                Button("Delete") { monitor.remove(entry.id) }
            }
        }
    }
}

// MARK: - Slice T-2: Tendedero Left Sidebar Clothesline

@MainActor
final class TendederoClotheslineController: NSObject, ObservableObject, QLPreviewPanelDataSource {
    static let shared = TendederoClotheslineController()
    static let captureModeKey = "com.katikati.tendedero.captureMode"
    static let unlimitedKey = "com.katikati.tendedero.unlimited"

    @Published private(set) var store = TendederoStore()
    @Published var selectedID: UUID?
    @Published var copiedID: UUID?
    @Published var captureMode: TendederoCaptureMode = {
        TendederoCaptureMode(rawValue: UserDefaults.standard.string(forKey: TendederoClotheslineController.captureModeKey) ?? "") ?? .screenshotsAndAutoClipboard
    }()
    @Published var unlimitedCapacity: Bool = UserDefaults.standard.bool(forKey: TendederoClotheslineController.unlimitedKey)

    var onNewScreenshot: (() -> Void)?

    private var started = false
    private var screenshotQuery: NSMetadataQuery?
    private var seenScreenshotPaths: Set<String> = []
    private var pasteboardTimer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var physicsTimer: Timer?
    private var previewURL: URL?

    func start() {
        guard !started else { return }
        started = true
        applyCapacityMode()
        startScreenshotQuery()
        startPasteboardWatch()
    }

    func setCaptureMode(_ mode: TendederoCaptureMode) {
        captureMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.captureModeKey)
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

    private func startPasteboardWatch() {
        pasteboardTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.captureMode == .screenshotsAndAutoClipboard else { return }
                let count = NSPasteboard.general.changeCount
                guard count != self.lastChangeCount else { return }
                self.hangCurrentClipboard()
            }
        }
    }

    private func startScreenshotQuery() {
        let q = NSMetadataQuery()
        q.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        q.searchScopes = [NSMetadataQueryUserHomeScope]
        q.sortDescriptors = [NSSortDescriptor(key: kMDItemFSCreationDate as String, ascending: false)]
        NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.seedInitialScreenshots(q) }
        }
        NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate, object: q, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.ingestNewScreenshots(q) }
        }
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

struct LeftSidebarClotheslineView: View {
    /// SD-2: the deck's one search field filters the clothesline by its item titles.
    var query: String = ""
    @ObservedObject var controller = TendederoClotheslineController.shared

    init(query: String = "") {
        self.query = query
    }

    private var stagedItems: [TendederoItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return controller.store.items }
        return controller.store.items.filter { $0.title.localizedStandardContains(trimmed) }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Label("Clothesline", systemImage: "paperclip")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { controller.hangCurrentClipboard() } label: { Image(systemName: "plus.circle") }
                    .buttonStyle(.plain).help(Text("Hang Clipboard"))
                if controller.store.items.contains(where: { !$0.isPinned }) {
                    Button { controller.clearUnpinned() } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).help(Text("Clear Unpinned"))
                }
                Menu {
                    Picker("Capture", selection: Binding(get: { controller.captureMode }, set: { controller.setCaptureMode($0) })) {
                        Text("Screenshots + Auto Clipboard").tag(TendederoCaptureMode.screenshotsAndAutoClipboard)
                        Text("Screenshots + Manual").tag(TendederoCaptureMode.screenshotsAndManualClipboard)
                    }
                    Toggle("Unlimited Items", isOn: Binding(get: { controller.unlimitedCapacity }, set: { controller.setUnlimitedCapacity($0) }))
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
            .padding(.horizontal, 12).padding(.top, 10)

            if stagedItems.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "paperclip").font(.system(size: 24)).foregroundStyle(.secondary)
                    Text("No hung items yet").font(.system(size: 12, weight: .medium))
                    Text("Take a screenshot, copy content, or drop a file here.").font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Spacer()
                }.padding(16)
            } else {
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(Color.primary.opacity(0.18)).frame(width: 2).padding(.leading, 14)
                        VStack(spacing: 12) {
                            ForEach(stagedItems) { item in hangingCard(item) }
                        }.padding(.leading, 22).padding(.trailing, 10).padding(.vertical, 6)
                    }
                }
            }
        }
        .onAppear { controller.markAllRead() }
        .onKeyPress(.space) {
            if let id = controller.selectedID, let item = controller.store.items.first(where: { $0.id == id }) {
                controller.quickLook(item)
                return .handled
            }
            return .ignored
        }
        .onDrop(of: [.fileURL, .url], isTargeted: nil) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { Task { @MainActor in controller.hangDroppedURL(url) } }
                }
            }
            return !providers.isEmpty
        }
    }

    private func hangingCard(_ item: TendederoItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "paperclip").font(.system(size: 11)).foregroundStyle(.secondary)
            cardPreview(item)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.title).font(.system(size: 11, weight: .medium)).lineLimit(2)
                if controller.copiedID == item.id {
                    Text("Copied").font(.system(size: 9, weight: .semibold)).foregroundStyle(.green)
                }
            }
            Spacer(minLength: 4)
            Button { controller.togglePin(item.id) } label: {
                Image(systemName: item.isPinned ? "pin.fill" : "pin").font(.system(size: 10))
                    .foregroundStyle(item.isPinned ? Color.accentColor : Color.secondary)
            }.buttonStyle(.plain)
            Button { controller.remove(item.id) } label: {
                Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(.secondary)
            }.buttonStyle(.plain)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(controller.selectedID == item.id ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.quaternary))
        .rotationEffect(.degrees(item.swingAngleDegrees), anchor: .topLeading)
        .onHover { if $0 { controller.hover(item.id) } }
        .onTapGesture(count: 2) { controller.open(item) }
        .onTapGesture { controller.selectedID = item.id; controller.copy(item) }
        .onDrag { controller.dragProvider(for: item) }
        .contextMenu {
            Button("Copy") { controller.copy(item) }
            Button("Quick Look (Space)") { controller.quickLook(item) }
            Button("Open") { controller.open(item) }
            Button(item.isPinned ? "Unpin" : "Pin") { controller.togglePin(item.id) }
            Button("Delete") { controller.remove(item.id) }
        }
    }

    @ViewBuilder
    private func cardPreview(_ item: TendederoItem) -> some View {
        switch item.kind {
        case .screenshot(let url):
            if let img = NSImage(contentsOf: url) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).frame(width: 44, height: 34).clipped().cornerRadius(5)
            } else {
                Image(systemName: "photo").frame(width: 32, height: 32)
            }
        case .imageData(let data):
            if let img = NSImage(data: data) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).frame(width: 44, height: 34).clipped().cornerRadius(5)
            } else {
                Image(systemName: "photo").frame(width: 32, height: 32)
            }
        case .link:
            Image(systemName: "link").font(.system(size: 15)).frame(width: 32, height: 32)
        case .text:
            Image(systemName: "doc.text").font(.system(size: 15)).frame(width: 32, height: 32)
        }
    }
}

extension MaccyKeyAction.Modifiers {
    /// MC-3: one translation from SwiftUI's flags to the pure table's bits.
    init(_ flags: EventModifiers) {
        var set: MaccyKeyAction.Modifiers = []
        if flags.contains(.option) { set.insert(.option) }
        if flags.contains(.shift) { set.insert(.shift) }
        if flags.contains(.command) { set.insert(.command) }
        self = set
    }
}

// MARK: - Dock Utilities Floating Card Stack Flyouts

/// Floating Card Stack flyout for recent macOS screenshots (`TendederoClotheslineController`).
struct DockScreenshotsFlyoutView: View {
    @ObservedObject private var controller = TendederoClotheslineController.shared
    @State private var hoveredID: UUID?

    private var shots: [TendederoItem] {
        controller.store.items.filter {
            switch $0.kind {
            case .screenshot, .imageData: return true
            default: return false
            }
        }
    }

    var body: some View {
        DockPreviewCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Screenshots", systemImage: "camera.viewfinder")
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    if !shots.isEmpty {
                        Button("Clear") { controller.clearUnpinned() }
                            .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                    }
                }

                if shots.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "camera.viewfinder").font(.system(size: 22)).foregroundStyle(.secondary)
                        Text("No recent screenshots").font(.system(size: 12, weight: .medium))
                        Text("Captures and image drops appear here as draggable cards.")
                            .font(.system(size: 10.5)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                } else {
                    ScrollView {
                        VStack(spacing: -8) {
                            ForEach(Array(shots.prefix(10).enumerated()), id: \.element.id) { idx, item in
                                screenshotCardRow(item, idx: idx)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 270)
                }
            }
        }
        .onAppear {
            controller.start()
            controller.markAllRead()
        }
    }

    @ViewBuilder
    private func screenshotCardRow(_ item: TendederoItem, idx: Int) -> some View {
        let isHovered = hoveredID == item.id
        let scale: CGFloat = isHovered ? 1.02 : 1.0 - CGFloat(min(idx, 3)) * 0.01
        let zVal: Double = isHovered ? 20 : Double(10 - min(idx, 9))
        HStack(spacing: 10) {
            screenshotThumb(item)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.title).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                Text(controller.copiedID == item.id ? "Copied" : "Click copy · Space Quick Look")
                    .font(.system(size: 9.5))
                    .foregroundStyle(controller.copiedID == item.id ? .green : .secondary)
            }
            Spacer(minLength: 4)
            Button { controller.quickLook(item) } label: {
                Image(systemName: "eye").font(.system(size: 11))
            }.buttonStyle(.plain)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.92))
                .shadow(color: .black.opacity(0.18), radius: isHovered ? 6 : 2, y: 2)
        )
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.white.opacity(0.14)))
        .scaleEffect(scale)
        .zIndex(zVal)
        .padding(.bottom, isHovered ? 10 : 6)
        .onHover { hoveredID = $0 ? item.id : (hoveredID == item.id ? nil : hoveredID) }
        .onTapGesture { controller.copy(item) }
        .onDrag { controller.dragProvider(for: item) }
    }

    @ViewBuilder
    private func screenshotThumb(_ item: TendederoItem) -> some View {
        switch item.kind {
        case .screenshot(let url):
            if let img = NSImage(contentsOf: url) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).frame(width: 48, height: 34).clipShape(RoundedRectangle(cornerRadius: 6))
            } else { Image(systemName: "photo").frame(width: 48, height: 34) }
        case .imageData(let data):
            if let img = NSImage(data: data) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).frame(width: 48, height: 34).clipShape(RoundedRectangle(cornerRadius: 6))
            } else { Image(systemName: "photo").frame(width: 48, height: 34) }
        default:
            Image(systemName: "doc").frame(width: 48, height: 34)
        }
    }
}

/// Floating Card Stack flyout for Clipboard History anchored to the Dock Clipboard utility icon.
struct DockClipboardStackFlyoutView: View {
    @ObservedObject private var monitor = ProductivityServices.shared.clipboard
    @State private var query = ""
    @State private var hoveredID: UUID?

    private var entries: [ClipEntry] {
        let base = monitor.history.entries
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        return base.filter { $0.text.localizedStandardContains(trimmed) }
    }

    var body: some View {
        DockPreviewCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Clipboard", systemImage: "doc.on.clipboard")
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    if !monitor.history.entries.isEmpty {
                        Button("Clear") { monitor.clear() }
                            .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                    }
                }
                TextField("Filter copies…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)

                if entries.isEmpty {
                    Text(monitor.isRecording ? "Nothing copied yet" : "Clipboard recording is off")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary).padding(.vertical, 14)
                } else {
                    ScrollView {
                        VStack(spacing: -6) {
                            ForEach(Array(entries.prefix(12).enumerated()), id: \.element.id) { idx, entry in
                                clipboardCardRow(entry, idx: idx)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 270)
                }
            }
        }
    }

    @ViewBuilder
    private func clipboardCardRow(_ entry: ClipEntry, idx: Int) -> some View {
        let isHovered = hoveredID == entry.id
        let scale: CGFloat = isHovered ? 1.015 : 1.0 - CGFloat(min(idx, 3)) * 0.008
        let zVal: Double = isHovered ? 20 : Double(12 - min(idx, 11))
        HStack(spacing: 8) {
            Image(systemName: entry.pinned ? "pin.fill" : "doc.text")
                .font(.system(size: 10.5))
                .foregroundStyle(entry.pinned ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: ClipboardHistory.previewLine(entry.text))
                    .font(.system(size: 11.5, weight: .medium)).lineLimit(2)
                Text(verbatim: ClipboardToastBadge.badge(for: entry.text))
                    .font(.system(size: 9.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button { monitor.pastePlain(entry) } label: {
                Image(systemName: "doc.on.doc").font(.system(size: 10.5))
            }.buttonStyle(.plain).help(Text("Paste"))
            Button { monitor.togglePin(entry.id) } label: {
                Image(systemName: entry.pinned ? "pin.slash" : "pin").font(.system(size: 10.5))
            }.buttonStyle(.plain)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.92))
                .shadow(color: .black.opacity(0.16), radius: isHovered ? 5 : 2, y: 2)
        )
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.white.opacity(0.14)))
        .scaleEffect(scale)
        .zIndex(zVal)
        .padding(.bottom, isHovered ? 8 : 5)
        .onHover { hoveredID = $0 ? entry.id : (hoveredID == entry.id ? nil : hoveredID) }
        .onTapGesture { monitor.copy(entry) }
    }
}

/// Hosted unified borderless-panel containers for `Screenshots` and `Clipboard` when presented by
/// `PanelCoordinator`, reusing `StackUtilityBackdropHost` (`v` pointer or clean float) and Shelf-inspired card surfaces.
struct DockScreenshotsUtilityHostedView: View {
    let context: StackPopupContext
    let usesLiquidGlass: Bool
    var flyoutPreset: UtilityFlyoutPreset = .shelfDeck
    @Binding var isPinned: Bool
    let onClose: () -> Void
    let onContentResize: (CGSize) -> Void

    @ObservedObject private var controller = TendederoClotheslineController.shared
    @State private var hoveredID: UUID?

    private var shots: [TendederoItem] {
        controller.store.items.filter {
            switch $0.kind {
            case .screenshot, .imageData: return true
            default: return false
            }
        }
    }

    private var plateSize: CGSize {
        let count = shots.count
        let h: CGFloat
        if count == 0 {
            h = 196
        } else if flyoutPreset == .compactGrid {
            let rows = min(3, (count + 1) / 2)
            h = 56 + CGFloat(rows) * 96 + CGFloat(max(0, rows - 1)) * 8 + 16
        } else {
            let visible = min(3, count)
            h = 56 + CGFloat(visible) * 116 + CGFloat(max(0, visible - 1)) * 8 + 16
        }
        return CGSize(width: 316, height: h)
    }

    private var totalWindowSize: CGSize {
        let arrowH: CGFloat = context.arrow.isHidden ? 0 : StackPopupMetrics.arrowHeight
        return CGSize(width: plateSize.width + 2 * StackPopupMetrics.panelMargin,
                      height: plateSize.height + arrowH + 2 * StackPopupMetrics.panelMargin)
    }

    var body: some View {
        StackUtilityBackdropHost(plateSize: plateSize, usesLiquidGlass: usesLiquidGlass, arrow: context.arrow) {
            VStack(spacing: 8) {
                headerRow
                if shots.isEmpty {
                    emptyState
                } else if flyoutPreset == .compactGrid {
                    compactGridBody
                } else {
                    shelfDeckBody
                }
            }
            .padding(.top, 12).padding(.bottom, 12)
            .frame(width: plateSize.width, height: plateSize.height, alignment: .top)
        }
        .onAppear {
            controller.start()
            controller.markAllRead()
            onContentResize(totalWindowSize)
        }
        .onChange(of: totalWindowSize) { _, next in onContentResize(next) }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "camera.viewfinder").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.cyan)
            Text("Screenshots").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.white)
            if !shots.isEmpty {
                Text(verbatim: "\(shots.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(.white.opacity(0.16)))
            }
            Spacer(minLength: 4)
            if !shots.isEmpty {
                Button("Clear") { controller.clearUnpinned() }
                    .buttonStyle(.plain).font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(.white.opacity(0.12)))
            }
            DockUtilityPinButton(isPinned: $isPinned)
            Button(action: onClose) {
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "camera.viewfinder").font(.system(size: 24)).foregroundStyle(.white.opacity(0.5))
            Text("No recent screenshots").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.85))
            Text("Captures and image drops appear here as draggable cards.")
                .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var shelfDeckBody: some View {
        ScrollView(.vertical, showsIndicators: shots.count > 3) {
            LazyVStack(spacing: 8) {
                ForEach(Array(shots.prefix(12).enumerated()), id: \.element.id) { idx, item in
                    screenshotCanvasCard(item, index: idx)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 4)
        }
    }

    private var compactGridBody: some View {
        let cols = [GridItem(.fixed(138), spacing: 8), GridItem(.fixed(138), spacing: 8)]
        return ScrollView(.vertical, showsIndicators: shots.count > 6) {
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(shots.prefix(16)) { item in
                    VStack(spacing: 4) {
                        shotImage(item, size: CGSize(width: 138, height: 74))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Text(verbatim: item.title)
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                    }
                    .onTapGesture { controller.copy(item) }
                    .onDrag { controller.dragProvider(for: item) }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 4)
        }
    }

    private func screenshotCanvasCard(_ item: TendederoItem, index: Int) -> some View {
        let isHovered = hoveredID == item.id
        let isCopied = controller.copiedID == item.id
        return ZStack(alignment: .bottomLeading) {
            Color(white: 0.09)
            shotImage(item, size: CGSize(width: 284, height: 114))
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            HStack {
                Text(verbatim: isCopied ? "Copied" : item.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isCopied ? Color.green : Color.white)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 10).padding(.bottom, 7)
        }
        .frame(width: 284, height: 114)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(isHovered ? 0.38 : 0.16), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            if isHovered {
                HStack(spacing: 4) {
                    Button { controller.copy(item) } label: {
                        Image(systemName: "doc.on.doc").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white).frame(width: 22, height: 22)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }.buttonStyle(.plain)
                    Button { controller.quickLook(item) } label: {
                        Image(systemName: "eye.fill").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white).frame(width: 22, height: 22)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }.buttonStyle(.plain)
                }
                .padding(8)
            }
        }
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isHovered)
        .onHover { hoveredID = $0 ? item.id : (hoveredID == item.id ? nil : hoveredID) }
        .onTapGesture { controller.copy(item) }
        .onDrag { controller.dragProvider(for: item) }
    }

    @ViewBuilder
    private func shotImage(_ item: TendederoItem, size: CGSize) -> some View {
        switch item.kind {
        case .screenshot(let url):
            if let img = NSImage(contentsOf: url) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).frame(width: size.width, height: size.height).clipped()
            } else { Image(systemName: "photo").foregroundStyle(.white.opacity(0.5)).frame(width: size.width, height: size.height) }
        case .imageData(let data):
            if let img = NSImage(data: data) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).frame(width: size.width, height: size.height).clipped()
            } else { Image(systemName: "photo").foregroundStyle(.white.opacity(0.5)).frame(width: size.width, height: size.height) }
        default:
            Image(systemName: "doc").foregroundStyle(.white.opacity(0.5)).frame(width: size.width, height: size.height)
        }
    }
}

struct DockClipboardUtilityHostedView: View {
    let context: StackPopupContext
    let usesLiquidGlass: Bool
    var flyoutPreset: UtilityFlyoutPreset = .shelfDeck
    @Binding var isPinned: Bool
    let onClose: () -> Void
    let onContentResize: (CGSize) -> Void

    @ObservedObject private var monitor = ProductivityServices.shared.clipboard
    @State private var query = ""
    @State private var hoveredID: UUID?

    private var entries: [ClipEntry] {
        let base = monitor.history.entries
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        return base.filter { $0.text.localizedStandardContains(trimmed) }
    }

    private var plateSize: CGSize {
        let count = entries.count
        let h: CGFloat
        if count == 0 {
            h = 196
        } else if flyoutPreset == .compactGrid {
            let visible = min(6, count)
            h = 92 + CGFloat(visible) * 42 + CGFloat(max(0, visible - 1)) * 5 + 14
        } else {
            let visible = min(3, count)
            h = 92 + CGFloat(visible) * 84 + CGFloat(max(0, visible - 1)) * 8 + 16
        }
        return CGSize(width: 316, height: h)
    }

    private var totalWindowSize: CGSize {
        let arrowH: CGFloat = context.arrow.isHidden ? 0 : StackPopupMetrics.arrowHeight
        return CGSize(width: plateSize.width + 2 * StackPopupMetrics.panelMargin,
                      height: plateSize.height + arrowH + 2 * StackPopupMetrics.panelMargin)
    }

    var body: some View {
        StackUtilityBackdropHost(plateSize: plateSize, usesLiquidGlass: usesLiquidGlass, arrow: context.arrow) {
            VStack(spacing: 8) {
                headerRow
                searchField
                if entries.isEmpty {
                    emptyState
                } else {
                    ScrollView(.vertical, showsIndicators: entries.count > 3) {
                        LazyVStack(spacing: flyoutPreset == .compactGrid ? 5 : 8) {
                            ForEach(Array(entries.prefix(15).enumerated()), id: \.element.id) { idx, entry in
                                if flyoutPreset == .compactGrid {
                                    compactClipboardRow(entry)
                                } else {
                                    shelfClipboardCard(entry, index: idx)
                                }
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 4)
                    }
                }
            }
            .padding(.top, 12).padding(.bottom, 12)
            .frame(width: plateSize.width, height: plateSize.height, alignment: .top)
        }
        .onAppear { onContentResize(totalWindowSize) }
        .onChange(of: totalWindowSize) { _, next in onContentResize(next) }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard.fill").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.cyan)
            Text("Clipboard").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.white)
            if !monitor.history.entries.isEmpty {
                Text(verbatim: "\(monitor.history.entries.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(.white.opacity(0.16)))
            }
            Spacer(minLength: 4)
            if !monitor.history.entries.isEmpty {
                Button("Clear") { monitor.clear() }
                    .buttonStyle(.plain).font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(.white.opacity(0.12)))
            }
            DockUtilityPinButton(isPinned: $isPinned)
            Button(action: onClose) {
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            TextField("Filter copies…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.1)))
        .padding(.horizontal, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard").font(.system(size: 22)).foregroundStyle(.white.opacity(0.5))
            Text(monitor.isRecording ? "Nothing copied yet" : "Clipboard recording is off")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func compactClipboardRow(_ entry: ClipEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: entry.pinned ? "pin.fill" : "doc.text")
                .font(.system(size: 10.5)).foregroundStyle(entry.pinned ? Color.orange : .white.opacity(0.6))
            Text(verbatim: ClipboardHistory.previewLine(entry.text))
                .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white).lineLimit(1)
            Spacer(minLength: 4)
            Button { monitor.pastePlain(entry) } label: {
                Image(systemName: "doc.on.doc").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.8))
            }.buttonStyle(.plain)
            Button { monitor.togglePin(entry.id) } label: {
                Image(systemName: entry.pinned ? "pin.slash" : "pin").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.8))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(white: 0.14).opacity(0.92)))
        .onTapGesture { monitor.copy(entry) }
        .onDrag { NSItemProvider(object: entry.text as NSString) }
    }

    @ViewBuilder
    private func shelfClipboardCard(_ entry: ClipEntry, index: Int) -> some View {
        let isHovered = hoveredID == entry.id
        let tilt: Double = (isHovered || entry.pinned) ? 0 : (index % 2 == 0 ? -0.6 : 0.6)
        clipboardCardSurface(for: entry)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(isHovered ? 0.45 : 0.18), lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                clipboardHoverOverlay(for: entry, isHovered: isHovered)
            }
            .scaleEffect(isHovered ? 1.015 : 1.0)
            .rotationEffect(.degrees(tilt))
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isHovered)
            .onHover { hoveredID = $0 ? entry.id : (hoveredID == entry.id ? nil : hoveredID) }
            .onTapGesture { monitor.copy(entry) }
            .onDrag { NSItemProvider(object: entry.text as NSString) }
    }

    @ViewBuilder
    private func clipboardCardSurface(for entry: ClipEntry) -> some View {
        let meta = ClipboardCardMetadata.classify(text: entry.text)
        let isURL = entry.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("http")
        let badge = ClipboardToastBadge.badge(for: entry.text)
        switch meta.contentType {
        case let .hexColor(hex, rgba):
            hexColorCard(hex: hex, rgba: rgba)
        case .text, .image:
            if isURL {
                linkCard(text: entry.text, badge: badge)
            } else {
                noteCard(text: entry.text, badge: badge)
            }
        }
    }

    private func hexColorCard(hex: String, rgba: DockRGBA) -> some View {
        let swatch = Color(red: Double(rgba.r), green: Double(rgba.g), blue: Double(rgba.b), opacity: Double(rgba.a))
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(swatch)
                .frame(width: 44, height: 44)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: hex).font(.system(size: 13.5, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                Text("Color Swatch · Click to copy").font(.system(size: 10)).foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
        }
        .padding(12)
        .frame(width: 284, alignment: .leading)
        .frame(minHeight: 74)
        .background(Color(white: 0.12).opacity(0.92))
    }

    private func linkCard(text: String, badge: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Link", systemImage: "globe").font(.system(size: 10, weight: .bold)).foregroundStyle(.cyan)
            Text(verbatim: ClipboardHistory.previewLine(text))
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
            Text(verbatim: badge).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.6))
        }
        .padding(12)
        .frame(width: 284, alignment: .topLeading)
        .frame(minHeight: 78, alignment: .topLeading)
        .background(Color(white: 0.13).opacity(0.92))
    }

    private func noteCard(text: String, badge: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: ClipboardHistory.previewLine(text))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.9))
                .lineLimit(3)
            Text(verbatim: badge)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.55))
        }
        .padding(.horizontal, 12).padding(.vertical, 10).padding(.trailing, 34)
        .frame(width: 284, alignment: .topLeading)
        .frame(minHeight: 78, alignment: .topLeading)
        .background(Color(white: 0.96))
    }

    @ViewBuilder
    private func clipboardHoverOverlay(for entry: ClipEntry, isHovered: Bool) -> some View {
        if isHovered || entry.pinned {
            HStack(spacing: 4) {
                Button { monitor.togglePin(entry.id) } label: {
                    Image(systemName: entry.pinned ? "pin.fill" : "pin")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(entry.pinned ? .orange : .white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.black.opacity(0.58)))
                }.buttonStyle(.plain)
                if isHovered {
                    Button { monitor.pastePlain(entry) } label: {
                        Image(systemName: "arrow.turn.down.left")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.black.opacity(0.58)))
                    }.buttonStyle(.plain).help(Text("Paste"))
                }
            }
            .padding(8)
        }
    }
}
