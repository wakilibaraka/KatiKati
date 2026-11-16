import AppKit
import SwiftUI

// Phase 47c — the optional 9th notch page: what Notification Center just showed, and the history the
// Notification Center database keeps. Off by default (`com.katikati.notch.notifications`); the banner
// observer runs only while the switch is on and this page is on screen, and the store is read only when
// the page opens.

struct NotchNotificationsPageView: View {
    @ObservedObject private var mirror = NotificationMirrorService.shared
    @AppStorage(NotificationHistoryStore.StorageKey.quietMode) private var quietMode = false
    @State private var searchQuery = ""
    @State private var unreadOnly = false

    private var visibleEntries: [NotificationHistoryEntry] {
        mirror.historyStore.visibleEntries(
            query: searchQuery,
            unreadOnly: unreadOnly,
            sensitiveBundleIDs: mirror.activeSensitiveBundleIDs(),
            placeholder: String(localized: "Notification content hidden")
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            if !mirror.historyStore.entries.isEmpty {
                searchBar
            }
            if !quietMode, let live = mirror.live { liveCard(live) }
            content
        }
        .padding(NotchDesignSpec.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(NotchDesignSpec.cardFillOpacity))
        )
        .onAppear {
            mirror.startBanners()
            mirror.loadHistory()
        }
        .onDisappear { mirror.stopBanners() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: quietMode ? "bell.slash.fill" : "bell.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text("Notifications")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            if mirror.historyStore.unreadCount > 0 {
                Text(verbatim: "\(mirror.historyStore.unreadCount)")
                    .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor.opacity(0.85)))
            }
            Spacer(minLength: 0)
            Button {
                unreadOnly.toggle()
            } label: {
                Text("Unread")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(unreadOnly ? .black : .white.opacity(0.75))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(unreadOnly ? Color.white : Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            if mirror.historyStore.unreadCount > 0 {
                Button {
                    mirror.markAllRead()
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                .help(String(localized: "Mark All Read"))
            }
            if !mirror.historyStore.entries.isEmpty {
                Button {
                    mirror.clearHistoryStore()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .buttonStyle(.plain)
                .help(String(localized: "Clear Inbox"))
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
            TextField(String(localized: "Search notifications"), text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 10.5))
                .foregroundStyle(.white)
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.08)))
    }

    /// The banner Notification Center is drawing now. It carries no app name: the accessibility tree does
    /// not name the notifying app, and this page does not guess one.
    private func liveCard(_ notification: MirroredNotification) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: notification.title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            if let detail = notification.detail {
                Text(verbatim: detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.10)))
    }

    /// One door at a time: the grant that blocks the page's headline (live banners need Accessibility)
    /// comes before the one that blocks its history, and neither is ever asked for from code.
    @ViewBuilder
    private var content: some View {
        if !visibleEntries.isEmpty {
            rows
        } else if !mirror.canReadBanners {
            door(Text("Accessibility Is Off"), pane: "Privacy_Accessibility")
        } else {
            switch mirror.historyState {
            case .noAccess:
                door(Text("Full Disk Access Is Off"), pane: "Privacy_AllFiles")
            case .unsupported:
                message(Text("Notification History Unavailable"))
            case .idle, .loading, .loaded:
                message(Text("No Notifications Yet"))
            }
        }
    }

    /// The newest few, of the persisted inbox: the page is 130 pt tall and does not scroll (the notch's
    /// own wheel steps pages).
    private var rows: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(visibleEntries.prefix(3)) { entry in
                Button {
                    mirror.markRead(id: entry.id)
                    open(entry.appBundleId)
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(entry.isRead ? Color.clear : Color.accentColor)
                            .frame(width: 5, height: 5)
                        Image(nsImage: NotificationAppIcon.icon(for: entry.appBundleId))
                            .resizable().frame(width: 14, height: 14)
                        Text(verbatim: NotificationAppIcon.name(for: entry.appBundleId))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1).fixedSize()
                        Text(verbatim: entry.title)
                            .font(.system(size: 11, weight: entry.isRead ? .regular : .semibold))
                            .foregroundStyle(.white.opacity(entry.isRead ? 0.72 : 1))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let body = entry.body {
                            Text(verbatim: body)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.45))
                                .lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func message(_ text: Text) -> some View {
        text.font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.55))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func door(_ text: Text, pane: String) -> some View {
        VStack(spacing: 5) {
            text.font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            Button(String(localized: "Open System Settings")) { openPrivacy(pane) }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// `AgendaPane.openPrivacy`'s route, inlined: this page is compiled into the test target too, where
    /// the calendar panel is not.
    private func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func open(_ bundleIdentifier: String?) {
        guard let bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// The notifying app's own icon and name, from the bundle id the store recorded. Nothing is invented: an
/// unknown id shows the generic notification glyph and the id's own last component.
enum NotificationAppIcon {
    private static var cache: [String: (name: String, icon: NSImage)] = [:]

    static func name(for bundleIdentifier: String?) -> String {
        entry(for: bundleIdentifier)?.name ?? ""
    }

    static func icon(for bundleIdentifier: String?) -> NSImage {
        entry(for: bundleIdentifier)?.icon ?? NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }

    private static func entry(for bundleIdentifier: String?) -> (name: String, icon: NSImage)? {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return nil }
        if let cached = cache[bundleIdentifier] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        let bundle = Bundle(url: url)
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let entry = (name: name, icon: icon)
        cache[bundleIdentifier] = entry
        return entry
    }
}
