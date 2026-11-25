import AppKit
import Combine
import Foundation

// Phase 33e addition — Download Manager & Torrent Hub Service
//
// Unifies:
// 1. Live browser downloads watcher (Safari, Chrome, Firefox, Arc, Edge)
// 2. Direct HTTP/HTTPS link download manager with URLSession and pause/resume
// 3. Magnet / `.torrent` downloads driven through a real BitTorrent engine (`TorrentEngine`, Phase 44)
//
// Adheres to KatiKati zero idle CPU posture: runs ticker/scans only while active downloads exist
// or while a surface retains this service, and the engine process exists only while a torrent row does.

@MainActor
public final class DownloadManagerService: NSObject, ObservableObject {
    public static let shared = DownloadManagerService()

    @Published public private(set) var items: [DownloadItem] = []
    @Published public private(set) var aggregateDownloadBps: Int64 = 0
    @Published public private(set) var aggregateUploadBps: Int64 = 0

    private var tickGate = LiveTickGate()
    private var ticker: Timer?
    private var scanQueue = DispatchQueue(label: "com.katikati.downloadmanager.scan", qos: .utility)
    private var urlSession: URLSession!

    // Track active URLSession tasks
    private var activeTasks: [UUID: URLSessionDownloadTask] = [:]
    private var segmentTasks: [URLSessionDownloadTask: (id: UUID, index: Int)] = [:]
    private var segmentPlans: [UUID: DownloadSegmentPlan] = [:]
    private var segmentFiles: [UUID: [Int: URL]] = [:]
    private var segmentResumeCompleted: [UUID: [Int: Int64]] = [:]
    /// SD-4b: the scheduler that decides queueing, stealing and reconnects, and the one flat `.part` file each
    /// segmented transfer writes into.
    private var engineStates: [UUID: DownloadEngineState] = [:]
    private var partFiles: [UUID: URL] = [:]
    private var resumeDataMap: [UUID: Data] = [:]

    // Track previous byte counts for speed calculation
    private var previousBytes: [UUID: (bytes: Int64, timestamp: Date)] = [:]

    // BitTorrent (Phase 44): the engine the hub drives, and the GIDs each torrent row is polling. A
    // magnet row starts on the GID the engine hands to the magnet itself; once the engine has followed it
    // into the payload, `payloadGIDs` takes over so size/peers/speed describe the real download.
    private let torrent: TorrentEngineClient
    private var torrentGIDs: [UUID: String] = [:]
    private var payloadGIDs: [UUID: String] = [:]
    private let sessionDefaults: UserDefaults
    /// GIDs die with the engine process, so only the URI survives a restart (Phase 44b).
    static let torrentSessionKey = "com.katikati.torrents.session"

    // Browser partial file sizes cache to track delta & speed
    private var knownPartialFiles: [String: (bytes: Int64, modified: Date, id: UUID)] = [:]

    private var downloadsDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    }

    /// `torrent` is injectable so tests can drive the hub with a fake engine instead of spawning one.
    init(torrent: TorrentEngineClient? = nil, sessionDefaults: UserDefaults = .standard) {
        self.torrent = torrent ?? TorrentEngine.shared
        self.sessionDefaults = sessionDefaults
        super.init()
        let config = URLSessionConfiguration.default
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    // MARK: - Lifecycle & Idle-CPU Gate

    public func retain() {
        if tickGate.retain() {
            startTicker()
        }
    }

    public func release() {
        if tickGate.release() {
            reconcileTicker()
        }
    }

    private func startTicker() {
        guard ticker == nil else { return }
        scanBrowserDownloads()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.onTick()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        aggregateDownloadBps = 0
        aggregateUploadBps = 0
    }

    private func reconcileTicker() {
        let hasActiveTransfers = items.contains { $0.state == .active || $0.state == .initializing }
        if tickGate.isActive || hasActiveTransfers {
            startTicker()
        } else {
            stopTicker()
        }
    }

    // MARK: - Periodic Tick & Browser Downloads Scan

    private func finaliseFlat(id: UUID, destination: URL, part: URL, plan: DownloadSegmentPlan) {
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: part, to: destination)
            if let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx].totalBytes = plan.totalBytes
                items[idx].bytesDownloaded = plan.totalBytes
                items[idx].downloadSpeedBps = 0
                items[idx].etaSeconds = nil
                items[idx].state = .completed
                items[idx].completedAt = Date()
            }
            segmentPlans.removeValue(forKey: id)
            segmentFiles.removeValue(forKey: id)
            engineStates.removeValue(forKey: id)
            partFiles.removeValue(forKey: id)
            segmentResumeCompleted.removeValue(forKey: id)
            DownloadResumeRecord.remove(id: id)
            previousBytes.removeValue(forKey: id)
            reconcileTicker()
        } catch {
            if let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx].state = .failed(error.localizedDescription)
                items[idx].downloadSpeedBps = 0
            }
            reconcileTicker()
        }
    }

    private func onTick() {
        reconnectStalled()
        scanBrowserDownloads()
        refreshTorrents()
        updateAggregates()
    }

    private func updateAggregates() {
        var totalDown: Int64 = 0
        var totalUp: Int64 = 0
        for item in items where item.state == .active {
            totalDown += item.downloadSpeedBps
            totalUp += item.uploadSpeedBps
        }
        aggregateDownloadBps = totalDown
        aggregateUploadBps = totalUp
    }

    private func scanBrowserDownloads() {
        let dir = downloadsDirectory
        scanQueue.async { [weak self] in
            guard let self else { return }
            let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
            guard let fileURLs = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else { return }

            var partialDiscovered: [String: (bytes: Int64, modified: Date)] = [:]
            for url in fileURLs {
                let ext = url.pathExtension.lowercased()
                if DownloadActivity.partialExtensions.contains(ext) || ext == "aria2" {
                    let filename = url.lastPathComponent
                    let values = try? url.resourceValues(forKeys: Set(keys))
                    let size = Int64(values?.fileSize ?? 0)
                    let mod = values?.contentModificationDate ?? Date()
                    partialDiscovered[filename] = (bytes: size, modified: mod)
                }
            }

            DispatchQueue.main.async {
                self.syncBrowserDownloads(partialDiscovered)
            }
        }
    }

    private func syncBrowserDownloads(_ discovered: [String: (bytes: Int64, modified: Date)]) {
        let now = Date()
        // The engine keeps a `<name>.aria2` control file next to a running torrent: its bookkeeping, not a
        // browser download, so it must not become a row of its own (and it would report itself as ~200 B).
        let torrentNames = Set(items.filter { $0.type == .torrent }.map { $0.name })

        for (filename, info) in discovered {
            let cleanName = stripPartialExtension(filename)
            if filename != cleanName, torrentNames.contains(cleanName) { continue }

            if let cached = knownPartialFiles[filename] {
                // Already known - calculate speed delta
                let deltaBytes = max(0, info.bytes - cached.bytes)
                let deltaTime = max(0.5, now.timeIntervalSince(cached.modified))
                let speed = Int64(Double(deltaBytes) / deltaTime)

                if let idx = items.firstIndex(where: { $0.id == cached.id }) {
                    items[idx].bytesDownloaded = info.bytes
                    items[idx].downloadSpeedBps = speed
                    if items[idx].totalBytes > 0 && speed > 0 {
                        let remaining = max(0, items[idx].totalBytes - info.bytes)
                        items[idx].etaSeconds = Int(remaining / speed)
                    }
                }
                knownPartialFiles[filename] = (bytes: info.bytes, modified: now, id: cached.id)
            } else {
                // New browser partial download discovered. A `.download` file exposes no total length,
                // so none is invented: the row shows the bytes on disk against an unknown total until
                // the file lands (Phase 43 — this used to guess `bytes * 2` plus a fixed 2.4 MB/s and a
                // 45 s ETA).
                let newId = UUID()
                let item = DownloadItem(
                    id: newId,
                    name: cleanName,
                    type: .browser,
                    state: .active,
                    destinationURL: downloadsDirectory.appendingPathComponent(cleanName),
                    bytesDownloaded: info.bytes,
                    totalBytes: 0,
                    downloadSpeedBps: 0,
                    etaSeconds: nil,
                    addedAt: now
                )
                items.insert(item, at: 0)
                knownPartialFiles[filename] = (bytes: info.bytes, modified: now, id: newId)
            }
        }

        // Check if any tracked partial files disappeared (completed/renamed)
        for (filename, cached) in knownPartialFiles {
            if discovered[filename] == nil {
                // File disappeared: browser finished download and renamed it!
                if let idx = items.firstIndex(where: { $0.id == cached.id }) {
                    items[idx].state = .completed
                    items[idx].totalBytes = items[idx].bytesDownloaded
                    items[idx].downloadSpeedBps = 0
                    items[idx].etaSeconds = nil
                    items[idx].completedAt = now
                }
                knownPartialFiles.removeValue(forKey: filename)
            }
        }
    }

    private func stripPartialExtension(_ name: String) -> String {
        let ns = name as NSString
        let ext = ns.pathExtension.lowercased()
        if DownloadActivity.partialExtensions.contains(ext) || ext == "aria2" {
            return ns.deletingPathExtension
        }
        return name
    }

    // MARK: - Ingestion (Paste Magnet, Torrent, or Direct URL)

    /// Accepts a magnet link or `.torrent` URL (handed to the BitTorrent engine, when one is installed on
    /// this machine) or a direct http(s) link. Anything else is refused rather than answered with invented
    /// numbers: Phase 43 removed the fabricated swarm, Phase 44 makes magnets real.
    @discardableResult
    public func addDownload(input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.lowercased().hasPrefix("magnet:") {
            guard let magnet = MagnetURIParser.parse(trimmed) else { return false }
            return addTorrent(uri: trimmed, name: magnet.displayName, infoHash: magnet.infoHash)
        }

        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"), url.host != nil else {
            return false
        }
        if url.pathExtension.lowercased() == "torrent" {
            return addTorrent(uri: url.absoluteString, name: url.lastPathComponent, infoHash: nil)
        }
        return addDirectURL(url)
    }

    /// Hands a magnet / `.torrent` link to the engine. Refused when no engine is installed. The row starts
    /// CONNECTING: the engine's own poll supplies the name, size, speeds and swarm counts — nothing here is
    /// guessed.
    private func addTorrent(uri: String, name: String, infoHash: String?) -> Bool {
        guard torrent.isAvailable else { return false }
        let id = UUID()
        let item = DownloadItem(
            id: id,
            name: name,
            type: .torrent,
            state: .initializing,
            sourceURL: uri,
            infoHash: infoHash,
            bytesDownloaded: 0,
            totalBytes: 0,
            downloadSpeedBps: 0,
            etaSeconds: nil,
            addedAt: Date()
        )
        items.insert(item, at: 0)
        saveTorrentSession()
        reconcileTicker()

        Task { [weak self] in
            guard let self else { return }
            do {
                let gid = try await self.torrent.add(uri: uri, directory: self.downloadsDirectory)
                self.torrentGIDs[id] = gid
                await self.poll(gid: gid, item: id)
            } catch {
                self.fail(id: id, reason: (error as? TorrentEngineError)?.message ?? error.localizedDescription)
            }
        }
        return true
    }

    // MARK: - Session restore (Phase 44b)

    /// Re-adds unfinished torrents saved by the previous launch through the normal path. Called once
    /// from `AppDelegate` at launch — never from `init`, so tests stay hermetic unless they opt in.
    /// Completed/failed rows are not restored: their files already verified in the engine.
    public func restoreTorrentSession() {
        guard torrent.isAvailable else { return }
        guard let data = sessionDefaults.data(forKey: Self.torrentSessionKey),
              let entries = try? JSONDecoder().decode([TorrentSessionEntry].self, from: data),
              !entries.isEmpty else { return }
        sessionDefaults.removeObject(forKey: Self.torrentSessionKey)
        for entry in entries { _ = addDownload(input: entry.uri) }
    }

    private func saveTorrentSession() {
        let entries = items.filter { $0.type == .torrent && !$0.state.isTerminal }.compactMap { item -> TorrentSessionEntry? in
            guard let uri = item.sourceURL, !uri.isEmpty else { return nil }
            return TorrentSessionEntry(uri: uri, name: item.name, infoHash: item.infoHash, addedAt: item.addedAt)
        }
        if entries.isEmpty {
            sessionDefaults.removeObject(forKey: Self.torrentSessionKey)
        } else if let data = try? JSONEncoder().encode(entries) {
            sessionDefaults.set(data, forKey: Self.torrentSessionKey)
        }
    }

    private func addDirectURL(_ url: URL) -> Bool {
        let id = UUID()
        let name = url.lastPathComponent.isEmpty ? "file.download" : url.lastPathComponent
        let dest = downloadsDirectory.appendingPathComponent(name)
        let item = DownloadItem(
            id: id,
            name: name,
            type: .directUrl,
            state: .active,
            sourceURL: url.absoluteString,
            destinationURL: dest,
            bytesDownloaded: 0,
            totalBytes: 0,          // determined once headers arrive
            downloadSpeedBps: 0,    // the delegate reports the real rate
            etaSeconds: nil,
            addedAt: Date()
        )
        items.insert(item, at: 0)
        Task { [weak self] in await self?.startDirectDownload(id: id, url: url, destination: dest) }
        reconcileTicker()
        return true
    }

    private func startDirectDownload(id: UUID, url: URL, destination: URL) async {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 15
        let length: Int64?
        let acceptsRanges: Bool
        if let (_, response) = try? await URLSession.shared.data(for: request),
           let http = response as? HTTPURLResponse,
           http.statusCode == 200 || http.statusCode == 206 {
            length = http.value(forHTTPHeaderField: "Content-Length").flatMap(Int64.init)
            acceptsRanges = (http.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased() == "bytes")
        } else {
            length = nil
            acceptsRanges = false
        }
        await MainActor.run {
            guard self.items.contains(where: { $0.id == id && $0.type == .directUrl }) else { return }
            if let idx = self.items.firstIndex(where: { $0.id == id }) {
                self.items[idx].totalBytes = length ?? 0
            }
            let policy = DownloadEnginePolicy.stored()
            let plan = DownloadSegmentPlanner.plan(contentLength: length, acceptRanges: acceptsRanges,
                                                   segmentCount: policy.segmentCount(forContentLength: length))
            if plan.isMultiSegment {
                self.startSegmentTasks(id: id, url: url, destination: destination, plan: plan)
            } else {
                self.startSingleStream(id: id, url: url)
            }
        }
    }

    private func startSingleStream(id: UUID, url: URL) {
        let task = urlSession.downloadTask(with: url)
        activeTasks[id] = task
        task.resume()
    }

    private func startSegmentTasks(id: UUID, url: URL, destination: URL, plan: DownloadSegmentPlan) {
        segmentPlans[id] = plan
        let completed = segmentResumeCompleted[id] ?? [:]
        var state = DownloadEngineState(plan: plan, policy: DownloadEnginePolicy.stored(), completed: completed)
        engineStates[id] = state
        // SD-4b: one output file. Every worker seeks into it at its own offset, so nothing is concatenated
        // afterwards and a stolen or reconnected segment needs no repair pass.
        let part = destination.deletingPathExtension().appendingPathExtension(destination.pathExtension + ".part")
        if !FileManager.default.fileExists(atPath: part.path) {
            _ = FileManager.default.createFile(atPath: part.path, contents: nil)
        }
        partFiles[id] = part
        fillSlots(id: id, url: url, destination: destination)
        _ = state
    }

    /// SD-4b: open every connection the policy allows, one queued segment each.
    private func fillSlots(id: UUID, url: URL, destination: URL) {
        while var state = engineStates[id] {
            let action = state.next(freeSlot: false)
            engineStates[id] = state
            switch action {
            case .start(let index):
                startSegment(id: id, url: url, index: index)
            case .assemble:
                assembleSegments(id: id, destination: destination, plan: state.plan)
                return
            case .steal, .wait:
                return
            }
        }
    }

    /// SD-4b: a worker finished. Take the next queued segment, or steal the tail of the largest remaining one,
    /// or assemble when everything has landed.
    private func advanceAfterFinish(id: UUID) {
        guard var state = engineStates[id] else { return }
        let action = state.next(freeSlot: true)
        engineStates[id] = state
        guard let item = items.first(where: { $0.id == id }), let destination = item.destinationURL,
              let source = item.sourceURL, let url = URL(string: source) else { return }
        switch action {
        case .start(let index):
            startSegment(id: id, url: url, index: index)
        case .steal(let victim, let tail):
            // The victim's cancelled bytes are gone, so its offset resets to its own start before it restarts
            // on the shortened range.
            if var owning = engineStates[id] {
                owning.reset(index: victim)
                engineStates[id] = owning
            }
            cancelSegment(id: id, index: victim)
            startSegment(id: id, url: url, index: victim)
            startSegment(id: id, url: url, index: tail)
        case .assemble:
            assembleSegments(id: id, destination: destination, plan: state.plan)
        case .wait:
            break
        }
    }

    private func startSegment(id: UUID, url: URL, index: Int) {
        guard let state = engineStates[id],
              let segment = state.plan.segments.first(where: { $0.index == index }) else { return }
        let start = segment.start + (state.completed[index] ?? 0)
        guard start <= segment.end else { return }
        var request = URLRequest(url: url)
        request.setValue("bytes=\(start)-\(segment.end)", forHTTPHeaderField: "Range")
        request.timeoutInterval = 60
        let task = urlSession.downloadTask(with: request)
        segmentTasks[task] = (id: id, index: index)
        task.resume()
    }

    private func cancelSegment(id: UUID, index: Int) {
        for (task, owner) in segmentTasks where owner.id == id && owner.index == index {
            task.cancel()
            segmentTasks.removeValue(forKey: task)
        }
    }

    /// SD-4b: the ticker's reconnect path. Throughput feeds the connection ramp and a transfer that has gone
    /// quiet gets its furthest-behind segment restarted while the reconnect budget lasts.
    private func reconnectStalled() {
        for (id, var state) in engineStates {
            let action = state.tick()
            engineStates[id] = state
            guard case .start(let index)? = action,
                  let item = items.first(where: { $0.id == id }),
                  let source = item.sourceURL, let url = URL(string: source) else { continue }
            if var owning = engineStates[id] {
                owning.reset(index: index)
                engineStates[id] = owning
            }
            cancelSegment(id: id, index: index)
            startSegment(id: id, url: url, index: index)
        }
    }

    private func assembleSegments(id: UUID, destination: URL, plan: DownloadSegmentPlan) {
        // SD-4b: with flat writes the `.part` file is already the finished file.
        if let part = partFiles[id] {
            finaliseFlat(id: id, destination: destination, part: part, plan: plan)
            return
        }
        let files = segmentFiles[id] ?? [:]
        guard files.count == plan.segments.count else { return }
        let part = destination.deletingPathExtension().appendingPathExtension(destination.pathExtension + ".part")
        try? FileManager.default.removeItem(at: part)
        guard FileManager.default.createFile(atPath: part.path, contents: nil) else { return }
        do {
            let output = try FileHandle(forWritingTo: part)
            defer { try? output.close() }
            for segment in plan.segments {
                guard let file = files[segment.index],
                      let input = try? FileHandle(forReadingFrom: file) else { return }
                defer { try? input.close() }
                try output.seek(toOffset: UInt64(segment.start))
                while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                    try output.write(contentsOf: chunk)
                }
            }
            try output.synchronize()
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: part, to: destination)
            for file in files.values { try? FileManager.default.removeItem(at: file) }
            if let first = files.values.first {
                try? FileManager.default.removeItem(at: first.deletingLastPathComponent())
            }
            if let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx].totalBytes = plan.totalBytes
                items[idx].bytesDownloaded = plan.totalBytes
                items[idx].downloadSpeedBps = 0
                items[idx].etaSeconds = nil
                items[idx].state = .completed
                items[idx].completedAt = Date()
            }
            segmentPlans.removeValue(forKey: id)
            segmentFiles.removeValue(forKey: id)
            segmentResumeCompleted.removeValue(forKey: id)
            DownloadResumeRecord.remove(id: id)
            reconcileTicker()
        } catch {
            try? FileManager.default.removeItem(at: part)
            if let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx].state = .failed(error.localizedDescription)
                items[idx].downloadSpeedBps = 0
            }
            reconcileTicker()
        }
    }

    // MARK: - Actions (Pause, Resume, Cancel, Reveal)

    public func pause(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].state = .paused
        items[idx].downloadSpeedBps = 0
        items[idx].uploadSpeedBps = 0
        items[idx].etaSeconds = nil

        for (task, owner) in segmentTasks where owner.id == id {
            task.cancel()
        }
        segmentTasks = segmentTasks.filter { $0.value.id != id }
        if let task = activeTasks[id] {
            task.cancel(byProducingResumeData: { [weak self] data in
                Task { @MainActor in
                    self?.resumeDataMap[id] = data
                    self?.activeTasks.removeValue(forKey: id)
                }
            })
        }
        // A torrent: the engine refuses a transfer it already finished, which the next poll then shows.
        // The payload GID is the transfer once the engine has followed the magnet into it (pausing the
        // metadata GID afterwards is meaningless — it has nothing left to do).
        if let gid = payloadGIDs[id] ?? torrentGIDs[id], items[idx].type == .torrent {
            Task { [weak self] in try? await self?.torrent.pause(gid: gid) }
        }
        reconcileTicker()
    }

    public func resume(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].state = .active
        items[idx].downloadSpeedBps = 0

        if items[idx].type == .directUrl {
            if let plan = segmentPlans[id], plan.isMultiSegment {
                guard let src = items[idx].sourceURL, let url = URL(string: src) else { return }
                startSegmentTasks(id: id, url: url, destination: items[idx].destinationURL
                    ?? downloadsDirectory.appendingPathComponent(items[idx].name), plan: plan)
            } else if let resumeData = resumeDataMap[id] {
                let task = urlSession.downloadTask(withResumeData: resumeData)
                activeTasks[id] = task
                task.resume()
                resumeDataMap.removeValue(forKey: id)
            } else if let src = items[idx].sourceURL, let url = URL(string: src) {
                let task = urlSession.downloadTask(with: url)
                activeTasks[id] = task
                task.resume()
            }
        }
        if let gid = payloadGIDs[id] ?? torrentGIDs[id], items[idx].type == .torrent {
            Task { [weak self] in try? await self?.torrent.unpause(gid: gid) }
        }
        reconcileTicker()
    }

    public func cancel(id: UUID) {
        if let task = activeTasks[id] {
            task.cancel()
            activeTasks.removeValue(forKey: id)
        }
        for (task, owner) in segmentTasks where owner.id == id { task.cancel() }
        segmentTasks = segmentTasks.filter { $0.value.id != id }
        segmentPlans.removeValue(forKey: id)
        if let files = segmentFiles.removeValue(forKey: id)?.values {
            for file in files { try? FileManager.default.removeItem(at: file) }
        }
        resumeDataMap.removeValue(forKey: id)
        items.removeAll(where: { $0.id == id })
        dropTorrentGIDs(id)
        saveTorrentSession()
        reconcileTicker()
    }

    public func revealInFinder(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let targetURL = item.destinationURL ?? downloadsDirectory.appendingPathComponent(item.name)
        if FileManager.default.fileExists(atPath: targetURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([targetURL])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([downloadsDirectory])
        }
    }

    public func clearCompleted() {
        let finished = items.filter { $0.state.isTerminal }
        items.removeAll(where: { $0.state.isTerminal })
        for item in finished where item.type == .torrent { dropTorrentGIDs(item.id) }
        saveTorrentSession()
        stopEngineIfIdle()
    }

    // MARK: - BitTorrent Polling

    /// One status per torrent row, 1 Hz while the hub is up. Rows that finished are left alone; a row whose
    /// GID the engine has not handed back yet has nothing to ask about.
    func refreshTorrents() {
        for item in items where item.type == .torrent && !item.state.isTerminal {
            guard let gid = payloadGIDs[item.id] ?? torrentGIDs[item.id] else { continue }
            Task { [weak self] in await self?.poll(gid: gid, item: item.id) }
        }
    }

    private func poll(gid: String, item id: UUID) async {
        guard let status = try? await torrent.status(gid: gid) else { return }
        apply(status, to: id)
    }

    private func apply(_ status: Aria2RPC.Status, to id: UUID) {
        if let payload = status.payloadGID { payloadGIDs[id] = payload }
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }

        if let name = status.name, !name.isEmpty { items[idx].name = name }
        if let hash = status.infoHash, !hash.isEmpty { items[idx].infoHash = hash.uppercased() }
        items[idx].totalBytes = status.totalBytes
        items[idx].bytesDownloaded = status.completedBytes
        items[idx].downloadSpeedBps = status.downloadBps
        items[idx].uploadSpeedBps = status.uploadBps
        items[idx].seeders = status.seeders
        items[idx].peers = status.connections
        items[idx].state = status.state
        items[idx].etaSeconds = status.downloadBps > 0 && status.totalBytes > status.completedBytes
            ? Int((status.totalBytes - status.completedBytes) / status.downloadBps)
            : nil
        if let path = status.filePaths.first {
            // A one-file torrent has a file destination; a multi-file torrent is a folder of paths.
            items[idx].destinationURL = status.filePaths.count == 1
                ? URL(fileURLWithPath: path)
                : URL(fileURLWithPath: path).deletingLastPathComponent()
        }
        if status.state == .completed { items[idx].completedAt = items[idx].completedAt ?? Date() }
        if status.state.isTerminal {
            saveTorrentSession()
            reconcileTicker()
            stopEngineIfIdle()
        }
    }

    private func fail(id: UUID, reason: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].state = .failed(reason)
        items[idx].downloadSpeedBps = 0
        items[idx].uploadSpeedBps = 0
        items[idx].etaSeconds = nil
        saveTorrentSession()
        reconcileTicker()
        stopEngineIfIdle()
    }

    /// Drops every GID a torrent row owns (the magnet's and, once known, the payload's) from the engine,
    /// then stops the engine if that was the last row. Dropping runs first so the removals still land
    /// before the process goes away.
    private func dropTorrentGIDs(_ id: UUID) {
        let gids = Set([torrentGIDs[id], payloadGIDs[id]].compactMap { $0 })
        torrentGIDs.removeValue(forKey: id)
        payloadGIDs.removeValue(forKey: id)
        guard !gids.isEmpty else {
            stopEngineIfIdle()
            return
        }
        Task { [weak self] in
            for gid in gids { await self?.torrent.remove(gid: gid) }
            self?.stopEngineIfIdle()
        }
    }

    /// The engine only needs to exist while a torrent row does: stopping it when the last one goes keeps the
    /// idle footprint at zero, and the next magnet starts it again.
    private func stopEngineIfIdle() {
        if !items.contains(where: { $0.type == .torrent }) { torrent.shutdown() }
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManagerService: URLSessionDownloadDelegate {
    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let owner = segmentTasks[downloadTask] {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 206 {
                    for (task, _) in self.segmentTasks { task.cancel() }
                    self.segmentTasks.removeAll()
                    self.segmentPlans.removeValue(forKey: owner.id)
                    self.segmentFiles.removeValue(forKey: owner.id)
                    self.segmentResumeCompleted.removeValue(forKey: owner.id)
                    if let item = self.items.first(where: { $0.id == owner.id }),
                       let src = item.sourceURL, let url = URL(string: src) {
                        self.startSingleStream(id: owner.id, url: url)
                    }
                    return
                }
                guard let part = self.partFiles[owner.id],
                      let state = self.engineStates[owner.id],
                      let segment = state.plan.segments.first(where: { $0.index == owner.index }) else { return }
                // SD-4b: flat positioned write — this range's bytes go to its own offset in the one `.part`
                // file, so a stolen, shortened or reconnected segment needs no reassembly pass.
                if let data = try? Data(contentsOf: location) {
                    try? DownloadFlatWriter.write(data, to: part, offset: state.writeOffset(for: owner.index))
                    self.segmentResumeCompleted[owner.id, default: [:]][owner.index] = segment.start + Int64(data.count)
                    if let item = self.items.first(where: { $0.id == owner.id }) {
                        DownloadResumeRecord(source: item.sourceURL ?? "",
                                             destination: item.destinationURL?.path ?? "",
                                             totalBytes: state.plan.totalBytes,
                                             isMultiSegment: state.plan.isMultiSegment,
                                             completed: self.segmentResumeCompleted[owner.id] ?? [:])
                            .write(id: owner.id)
                    }
                }
                try? FileManager.default.removeItem(at: location)
                self.segmentTasks.removeValue(forKey: downloadTask)
                if var owning = self.engineStates[owner.id] {
                    owning.finish(index: owner.index)
                    self.engineStates[owner.id] = owning
                }
                self.advanceAfterFinish(id: owner.id)
            }
            return
        }
        let matchedId = activeTasks.first(where: { $0.value == downloadTask })?.key
        DispatchQueue.main.async { [weak self] in
            guard let self, let id = matchedId else { return }
            if let idx = self.items.firstIndex(where: { $0.id == id }) {
                let dest = self.items[idx].destinationURL ?? self.downloadsDirectory.appendingPathComponent(self.items[idx].name)
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.moveItem(at: location, to: dest)
                self.items[idx].state = .completed
                self.items[idx].bytesDownloaded = self.items[idx].totalBytes
                self.items[idx].downloadSpeedBps = 0
                self.items[idx].completedAt = Date()
            }
            self.activeTasks.removeValue(forKey: id)
            self.reconcileTicker()
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if let owner = segmentTasks[downloadTask] {
            DispatchQueue.main.async { [weak self] in
                guard let self, let plan = self.segmentPlans[owner.id],
                      let idx = self.items.firstIndex(where: { $0.id == owner.id }) else { return }
                let completed = plan.segments.enumerated().reduce(Int64(0)) { sum, entry in
                    if entry.offset == owner.index { return sum + totalBytesWritten }
                    return sum + entry.element.completedBytes
                }
                self.items[idx].bytesDownloaded = min(plan.totalBytes, completed)
                let previous = self.previousBytes[owner.id]
                let now = Date()
                if let previous, now.timeIntervalSince(previous.timestamp) >= 0.5 {
                    let speed = max(0, (completed - previous.bytes) / Int64(max(0.5, now.timeIntervalSince(previous.timestamp))))
                    self.items[idx].downloadSpeedBps = speed
                    let eta = plan.remainingBytes
                    self.items[idx].etaSeconds = speed > 0 ? Int(eta / speed) : nil
                    self.previousBytes[owner.id] = (bytes: completed, timestamp: now)
                } else if previous == nil {
                    self.previousBytes[owner.id] = (bytes: completed, timestamp: now)
                }
            }
            return
        }
        let matchedId = activeTasks.first(where: { $0.value == downloadTask })?.key
        DispatchQueue.main.async { [weak self] in
            guard let self, let id = matchedId else { return }
            if let idx = self.items.firstIndex(where: { $0.id == id }) {
                self.items[idx].bytesDownloaded = totalBytesWritten
                if totalBytesExpectedToWrite > 0 {
                    self.items[idx].totalBytes = totalBytesExpectedToWrite
                }

                // Compute instantaneous speed
                let now = Date()
                if let prev = self.previousBytes[id] {
                    let deltaBytes = totalBytesWritten - prev.bytes
                    let deltaTime = now.timeIntervalSince(prev.timestamp)
                    if deltaTime >= 0.5 {
                        let speed = Int64(Double(deltaBytes) / deltaTime)
                        self.items[idx].downloadSpeedBps = speed
                        if totalBytesExpectedToWrite > totalBytesWritten && speed > 0 {
                            self.items[idx].etaSeconds = Int((totalBytesExpectedToWrite - totalBytesWritten) / speed)
                        }
                        self.previousBytes[id] = (bytes: totalBytesWritten, timestamp: now)
                    }
                } else {
                    self.previousBytes[id] = (bytes: totalBytesWritten, timestamp: now)
                }
            }
        }
    }
}
