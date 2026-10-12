import Foundation
import UserNotifications

// Phase 8b-4C — the opt-in OS Notification Center tier of the Live Island's event feed.
//
// Posted only when the user turned banners on AND no in-app surface showed the event (the router's
// `shouldPostOSBanner`), so it can never double an on-screen toast. Authorization is requested lazily,
// on the first banner the user could actually receive — never at launch — and a denial is silent
// (the in-app tier is the user-visible path). Copy comes from `LiveEventPresentation`.

@MainActor
final class LiveEventBannerPoster {
    func post(_ event: LiveEvent) {
        let presentation = LiveEventPresentation(event)
        let content = UNMutableNotificationContent()
        content.title = presentation.headline
        if let detail = presentation.detail, !detail.isEmpty { content.body = detail }
        let request = UNNotificationRequest(identifier: "com.katikati.liveEvent." + event.dedupeKey, content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            center.add(request)
        }
    }
}
