import AppKit
import SwiftUI

// Phase 47c — the optional 9th notch page: what Notification Center just showed, and the history the
// Notification Center database keeps. Off by default (`com.katikati.notch.notifications`); the banner
// observer runs only while the switch is on and this page is on screen, and the store is read only when
// the page opens.

struct NotchNotificationsPageView: View {
    @ObservedObject private var mirror = NotificationMirrorService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if let live = mirror.live { liveCard(live) }
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
            Image(systemName: "bell.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text("Notifications")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            Text(verbatim: "\(mirror.history.count)")
                .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
        }
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
        if !mirror.canReadBanners {
            door(Text("Accessibility Is Off"), pane: "Privacy_Accessibility")
        } else {
            switch mirror.historyState {
            case .noAccess:
                door(Text("Full Disk Access Is Off"), pane: "Privacy_AllFiles")
            case .unsupported:
                message(Text("Notification History Unavailable"))
            case .idle, .loading:
                message(Text("No Notifications Yet"))
            case .loaded:
                if mirror.history.isEmpty { message(Text("No Notifications Yet")) } else { rows }
            }
        }
    }

    /// The newest few, of the 40 read: the page is 130 pt tall and does not scroll (the notch's own wheel
    /// steps pages).
    private var rows: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(mirror.history.prefix(4)) { notification in
                Button { open(notification.bundleIdentifier) } label: {
                    HStack(spacing: 6) {
                        Image(nsImage: NotificationAppIcon.icon(for: notification.bundleIdentifier))
                            .resizable().frame(width: 14, height: 14)
                        Text(verbatim: NotificationAppIcon.name(for: notification.bundleIdentifier))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1).fixedSize()
                        Text(verbatim: notification.title)
                            .font(.system(size: 11))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let detail = notification.detail {
                            Text(verbatim: detail)
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
