import AppKit
import Foundation

/// W-5: parking, restoring, and the durable state that makes both survive a crash.
///
/// The load-bearing order is here: a window's recovery frame is written to disk *before* the window
/// moves, and the record is only dropped once the restore has actually been written. A session that
/// dies mid-park therefore leaves a file the next launch can repair from.
extension TilingEngine {

    /// Parks one window, persisting its recovery frame *before* moving it.
    func parkWorkspaceWindow(_ id: WindowID, on screen: NSScreen) {
        guard NSEvent.pressedMouseButtons == 0 else { return }
        guard let record = lastWindows[id], let cg = record.cgWindowID, cg != 0 else { return }
        guard record.status == .active || record.status == .inactive else { return }
        guard parkedWorkspaceWindows[cg] == nil else { return }
        guard isTileable(record, cg) else { return }

        let screens = NSScreen.screens
        let primaryMaxY = screens.first?.frame.maxY ?? 0
        // Only park a window that really is on this display; a window owned by another display's
        // workspace is that display's to park.
        guard resolveScreen(for: record, screens: screens, primaryMaxY: primaryMaxY) === screen else { return }

        let quartzRecovery = axElement(for: record.pid, cgWindowID: cg).flatMap(WindowSnapService.frame(of:))
            ?? record.bounds
        guard let quartzRecovery else { return }

        let area = workArea(of: screen)
        let neighbourRight = screens.contains { other in
            other !== screen && abs(other.frame.minX - screen.frame.maxX) < 1
        }
        let side = WorkspaceParking.side(neighbourOnRight: neighbourRight)
        let cocoaRecovery = cocoaFrame(quartzRecovery, primaryMaxY: primaryMaxY)
        let parkedCocoa = WorkspaceParking.parked(cocoaRecovery, in: area, side: side)

        // The frame to return to when tiling is switched off, for a window tiling has never seen in
        // place (a window that was already parked when the pass first looked at it).
        if preTilingFrames[cg] == nil {
            preTilingFrames[cg] = quartzFrame(cocoaRecovery, primaryMaxY: primaryMaxY)
        }

        parkedWorkspaceWindows[cg] = WorkspaceParking.Record(
            windowID: id.rawValue,
            displayKey: screenKey(for: screen),
            workspace: (workspaceStore.workspace(of: id) ?? .numbered(1)).token,
            recoveryFrame: cocoaRecovery,
            side: side,
            pid: record.pid,
            cgWindowID: UInt32(cg)
        )
        persistParkedWorkspaceWindows()

        writeFrame(quartzFrame(parkedCocoa, primaryMaxY: primaryMaxY), pid: record.pid, cgWindowID: cg)
        lastAppliedFrames[cg] = quartzFrame(parkedCocoa, primaryMaxY: primaryMaxY)
        lastAppliedAt[cg] = ProcessInfo.processInfo.systemUptime
    }

    func parkWorkspaceWindows(_ ids: [WindowID], on screen: NSScreen) {
        for id in ids { parkWorkspaceWindow(id, on: screen) }
    }

    /// Puts one workspace's parked windows back on screen and only then drops their records — the
    /// reveal half of `parkWorkspaceWindow`, scoped to one switch.
    ///
    /// The retile that follows a switch writes frames for *tileable* windows alone, so a floated
    /// window keeps whatever frame parking gave it. Dropping its record without restoring the frame
    /// therefore leaves it off screen with nothing left to bring it back — not even the quit path, which
    /// iterates this same dictionary (found live 2026-11-27: 13 floated windows stranded past the right
    /// edge of the display after ⌃⌥3 then ⌃⌥1).
    func revealParkedWorkspaceWindows(in workspace: WorkspaceID, on displayKey: String, screen: NSScreen) {
        guard !parkedWorkspaceWindows.isEmpty else { return }
        let revealing = parkedWorkspaceWindows.filter {
            $0.value.displayKey == displayKey && $0.value.workspace == workspace.token
        }
        guard !revealing.isEmpty else { return }

        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        let area = workArea(of: screen)
        for (cg, record) in revealing {
            guard let pid = record.pid, pid > 0 else { continue }
            let quartz = quartzFrame(WorkspaceParking.revealFrame(record.recoveryFrame, in: area),
                                     primaryMaxY: primaryMaxY)
            writeFrame(quartz, pid: pid, cgWindowID: cg)
            lastAppliedFrames[cg] = quartz
            lastAppliedAt[cg] = ProcessInfo.processInfo.systemUptime
            parkedWorkspaceWindows.removeValue(forKey: cg)
        }
        persistParkedWorkspaceWindows()
    }

    /// Puts every parked window back where it was. Runs on quit, when workspaces are switched off,
    /// and at startup after a crash that left the parked file behind.
    func revealAllParkedWorkspaces() {
        guard !parkedWorkspaceWindows.isEmpty else { return }
        let screens = NSScreen.screens
        let primaryMaxY = screens.first?.frame.maxY ?? 0
        for (cg, record) in parkedWorkspaceWindows {
            guard let pid = lastWindows.values.first(where: { $0.cgWindowID == cg })?.pid ?? record.pid,
                  pid > 0 else { continue }
            writeFrame(quartzFrame(record.recoveryFrame, primaryMaxY: primaryMaxY), pid: pid, cgWindowID: cg)
        }
        parkedWorkspaceWindows.removeAll()
        persistParkedWorkspaceWindows()
    }

    /// Startup recovery: a parked file with no running session means the last session died after
    /// parking. Put those windows back before anything else touches them.
    func recoverParkedWorkspacesOnStart() {
        guard let url = parkedWorkspaceFileURL(),
              let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([WorkspaceParking.Record].self, from: data),
              !records.isEmpty else { return }

        let screens = NSScreen.screens
        let primaryMaxY = screens.first?.frame.maxY ?? 0
        for record in records {
            guard let cg = record.cgWindowID, let pid = record.pid, pid > 0 else { continue }
            writeFrame(quartzFrame(record.recoveryFrame, primaryMaxY: primaryMaxY), pid: pid, cgWindowID: cg)
        }
        parkedWorkspaceWindows.removeAll()
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Frame conversion

    func cocoaFrame(_ quartz: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(x: quartz.minX, y: primaryMaxY - quartz.maxY, width: quartz.width, height: quartz.height)
    }

    func quartzFrame(_ cocoa: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(origin: SnapPosition.accessibilityOrigin(of: cocoa, primaryMaxY: primaryMaxY), size: cocoa.size)
    }

    // MARK: - Durable state

    func workspaceSupportDirectory() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            .map { $0.appendingPathComponent("KatiKati", isDirectory: true) }
    }

    func parkedWorkspaceFileURL() -> URL? {
        workspaceSupportDirectory()?.appendingPathComponent("parked-workspaces.json")
    }

    /// Mode 0600, like the rest of the app's private state. Written before a window moves and
    /// rewritten after every restore, so the file always matches what is off screen.
    func persistParkedWorkspaceWindows() {
        guard let url = parkedWorkspaceFileURL() else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Array(parkedWorkspaceWindows.values))
            try data.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            log.error("workspace parking persist failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func persistWorkspaceStore() {
        Self.persist(workspaceStore, forKey: Self.workspaceStoreKey)
    }

    static func persist<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value),
              let text = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(text, forKey: key)
    }

    static func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let text = UserDefaults.standard.string(forKey: key),
              let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func storedWorkspaceRegistry() -> WorkspaceRegistry {
        load(WorkspaceRegistry.self, forKey: workspaceRegistryKey) ?? .default
    }

    static func storedWorkspaceRules() -> WorkspaceRules {
        guard let text = UserDefaults.standard.string(forKey: workspaceRulesKey) else { return .default }
        return WorkspaceRules.parse(text)
    }

    static func storedActiveWorkspaces() -> [String: WorkspaceID] {
        let tokens = UserDefaults.standard.dictionary(forKey: workspaceActiveKey) as? [String: String] ?? [:]
        return tokens.compactMapValues(WorkspaceID.init(token:))
    }

    static func storedWorkspaceStore() -> WorkspaceStore {
        load(WorkspaceStore.self, forKey: workspaceStoreKey) ?? WorkspaceStore()
    }
}
