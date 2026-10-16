import AppKit
import ApplicationServices
import Foundation
import SQLite3

/// Phase 47c — mirrored notifications: the banners Notification Center is drawing right now
/// (Accessibility, the same private UI `NotificationMoveService` walks) and the Notification Center
/// database's own history (Full Disk Access).
///
/// Nothing here runs by itself. The observer exists only while the switch is on and the page is on
/// screen; the database is opened read-only, read once, and closed again. Both halves fail closed with the
/// door to the missing grant, because neither grant can be requested from code.
@MainActor
final class NotificationMirrorService: ObservableObject {
    static let shared = NotificationMirrorService()
    /// The notch page's own switch; the page exists only while it is on.
    static let enabledKey = "com.katikati.notch.notifications"
    /// The database holds far more; the page shows the newest few and nothing scrolls the store forever.
    private static let historyLimit = 40
    private static let notificationCenterBundleID = "com.apple.notificationcenterui"
    /// `AXChildrenChanged` is not exported as a `kAX*` constant; the relocation feature registers the
    /// same raw string.
    private static let childrenChanged = "AXChildrenChanged" as CFString

    enum HistoryState: Equatable { case idle, loading, loaded, noAccess, unsupported }

    @Published private(set) var live: MirroredNotification?
    @Published private(set) var history: [MirroredNotification] = []
    @Published private(set) var historyState: HistoryState = .idle

    private var observer: AXObserver?
    private var appElement: AXUIElement?
    private var isWatching = false
    private var isEnabled = UserDefaults.standard.bool(forKey: NotificationMirrorService.enabledKey)

    private init() {}

    /// Reading banners needs the Accessibility grant; the page says so instead of showing an empty list.
    var canReadBanners: Bool { AXIsProcessTrusted() }

    func setEnabled(_ on: Bool) {
        guard isEnabled != on else { return }
        isEnabled = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        if !on { stopBanners() }
    }

    // MARK: - Live banners (Accessibility, event-driven: no timer)

    /// Called when the page appears. One AXObserver on Notification Center; nothing is polled.
    func startBanners() {
        guard isEnabled, !isWatching, AXIsProcessTrusted(),
              let application = NSRunningApplication
                  .runningApplications(withBundleIdentifier: Self.notificationCenterBundleID).first else { return }
        let element = AXUIElementCreateApplication(application.processIdentifier)
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let service = Unmanaged<NotificationMirrorService>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in service.readBanners() }
        }
        guard AXObserverCreate(application.processIdentifier, callback, &created) == .success,
              let observer = created else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, element, kAXWindowCreatedNotification as CFString, refcon)
        AXObserverAddNotification(observer, element, Self.childrenChanged, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.observer = observer
        appElement = element
        isWatching = true
        readBanners()       // a banner may already be on screen when the page opens
    }

    /// Called when the page goes away: the observer is removed with it.
    func stopBanners() {
        guard isWatching else { return }
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        appElement = nil
        isWatching = false
    }

    /// Walk the Notification Center windows, read the newest banner's own text, publish it. Anything we do
    /// not positively recognise contributes nothing.
    private func readBanners() {
        guard let appElement, let windows = copyElements(kAXWindowsAttribute as CFString, from: appElement) else { return }
        for window in windows {
            guard let banner = bannerElement(in: window),
                  let folded = NotificationBannerText.fold(bannerTexts(in: banner)) else { continue }
            live = MirroredNotification(id: folded.title, bundleIdentifier: nil, title: folded.title,
                                        subtitle: nil, body: folded.body, date: Date())
            return
        }
    }

    /// A banner is recognised by its subrole, exactly as the relocation feature recognises one. Any other
    /// UI shape means nothing is read.
    private func bannerElement(in window: AXUIElement) -> AXUIElement? {
        var queue = [window]
        var index = 0
        while index < queue.count, index <= NotificationUICapability.maxNodes {
            let element = queue[index]
            index += 1
            if let subrole = axString(kAXSubroleAttribute as CFString, from: element),
               NotificationUICapability.bannerSubroles.contains(subrole) { return element }
            queue.append(contentsOf: children(of: element))
        }
        return nil
    }

    /// The banner's own text, in the order the tree offers it.
    private func bannerTexts(in banner: AXUIElement) -> [String] {
        var texts: [String] = []
        var queue = [banner]
        var index = 0
        while index < queue.count, index <= NotificationUICapability.maxNodes {
            let element = queue[index]
            index += 1
            for attribute in [kAXValueAttribute, kAXTitleAttribute] {
                if let text = axString(attribute as CFString, from: element), !text.isEmpty { texts.append(text) }
            }
            queue.append(contentsOf: children(of: element))
        }
        return texts
    }

    // MARK: - History (Full Disk Access, read only while the page is open)

    func loadHistory() {
        guard isEnabled, historyState != .loading else { return }
        historyState = .loading
        DispatchQueue.global(qos: .utility).async {
            let result = NotificationHistoryReader.read(limit: Self.historyLimit)
            Task { @MainActor in self.apply(result) }
        }
    }

    private func apply(_ result: NotificationHistoryReader.Result) {
        switch result {
        case .entries(let rows): history = rows; historyState = .loaded
        case .noAccess: historyState = .noAccess
        case .unsupported: historyState = .unsupported
        }
    }

    // MARK: - Accessibility plumbing (the same minimal reads the window walk uses)

    private func copyElements(_ attribute: CFString, from element: AXUIElement) -> [AXUIElement]? {
        guard let value = axCopy(attribute, from: element) else { return nil }
        return value as? [AXUIElement]
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        let direct = (axCopy(kAXChildrenAttribute as CFString, from: element) as? [AXUIElement]) ?? []
        let visible = (axCopy("AXVisibleChildren" as CFString, from: element) as? [AXUIElement]) ?? []
        return direct + visible
    }

    private func axString(_ attribute: CFString, from element: AXUIElement) -> String? {
        guard let value = axCopy(attribute, from: element) else { return nil }
        return value as? String
    }

    private func axCopy(_ attribute: CFString, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value
    }
}

/// The Notification Center database, opened read-only and never written. Full Disk Access is what it
/// needs and what cannot be asked for from code, so a refusal is reported as `.noAccess` and the page
/// offers the System Settings door.
enum NotificationHistoryReader {
    enum Result: Equatable { case entries([MirroredNotification]), noAccess, unsupported }

    static func read(limit: Int) -> Result {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db")
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database = handle else {
            if let handle { sqlite3_close(handle) }
            return .noAccess
        }
        defer { sqlite3_close(database) }

        // `record.data` is the notification's own property list; `app.identifier` its bundle id.
        let sql = """
        SELECT r.data, a.identifier FROM record r
        LEFT JOIN app a ON a.app_id = r.app_id
        WHERE r.data IS NOT NULL
        ORDER BY COALESCE(r.delivered_date, r.request_date) DESC
        LIMIT ?
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let prepared = statement else {
            return .unsupported
        }
        defer { sqlite3_finalize(prepared) }
        sqlite3_bind_int(prepared, 1, Int32(limit))

        var rows: [MirroredNotification] = []
        while sqlite3_step(prepared) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(prepared, 0) else { continue }
            let length = Int(sqlite3_column_bytes(prepared, 0))
            let data = Data(bytes: bytes, count: length)
            let identifier = sqlite3_column_text(prepared, 1).map { String(cString: $0) }
            guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                  let record = plist as? [String: Any],
                  let notification = NotificationRecord.notification(fromRecord: record, bundleIdentifier: identifier)
            else { continue }
            rows.append(notification)
        }
        return .entries(rows)
    }
}
