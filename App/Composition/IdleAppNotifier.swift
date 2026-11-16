import AppKit
import Foundation
import OSLog
import UserNotifications

/// Leaf-style interactive notification poster for idle / high-memory background apps.
@MainActor
final class IdleAppNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = IdleAppNotifier()

    static let categoryIdentifier = "com.katikati.idleApp"
    static let quitActionID = "com.katikati.idleApp.quit"
    static let hideActionID = "com.katikati.idleApp.hide"
    static let ignoreActionID = "com.katikati.idleApp.ignore"

    private let log = Logger(subsystem: "com.katikati.app", category: "idleAppNotifier")
    private var registered = false

    func registerCategoryIfNeeded() {
        guard !registered else { return }
        registered = true
        let quitAction = UNNotificationAction(
            identifier: Self.quitActionID,
            title: String(localized: "Quit"),
            options: []
        )
        let hideAction = UNNotificationAction(
            identifier: Self.hideActionID,
            title: String(localized: "Hide"),
            options: []
        )
        let ignoreAction = UNNotificationAction(
            identifier: Self.ignoreActionID,
            title: String(localized: "Ignore App"),
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [quitAction, hideAction, ignoreAction],
            intentIdentifiers: [],
            options: []
        )
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([category])
    }

    func post(appName: String, bundleID: String, pid: pid_t, idleMinutes: Int, memoryBytes: UInt64) {
        registerCategoryIfNeeded()

        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(appName) has been idle")
        if memoryBytes > 0 {
            let mem = AppMemorySampler.formatBytes(memoryBytes)
            content.body = String(localized: "Unused for \(idleMinutes) min (\(mem) RAM).")
        } else {
            content.body = String(localized: "Unused for \(idleMinutes) min.")
        }
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = ["bundleID": bundleID, "pid": Int(pid)]

        let request = UNNotificationRequest(
            identifier: "com.katikati.idleApp.\(bundleID)",
            content: content,
            trigger: nil
        )
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { [log] granted, _ in
            guard granted else { return }
            center.add(request) { error in
                if let error { log.warning("Idle notification failed: \(error.localizedDescription)") }
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let bundleID = userInfo["bundleID"] as? String
        let pid = (userInfo["pid"] as? Int).map { pid_t($0) }
        let actionID = response.actionIdentifier

        Task { @MainActor in
            defer { completionHandler() }
            guard let bundleID else { return }
            let targetApp = pid.flatMap { NSRunningApplication(processIdentifier: $0) }
                ?? NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID })

            switch actionID {
            case Self.quitActionID:
                targetApp?.terminate()
            case Self.hideActionID:
                targetApp?.hide()
            case Self.ignoreActionID:
                QuitOnLastWindowService.shared.setIdleAction(.keep, for: bundleID)
            default:
                break
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}
