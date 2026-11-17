import AppKit

// Slice SD-1 removed the notch's notification page; the inbox itself now lives in the Left Edge Bar's
// Side Deck (`SideDeckNotificationsView`, in `App/Scenes/Edge/DeckViews.swift`). What stays in this file
// is the app icon/name resolver that view draws every row with — it is compiled into the test target too,
// so it must not reference the app-only drawer controller.

/// The notifying app's own icon and name, from the bundle id the store recorded. Nothing is invented: an
/// unknown id shows the generic notification glyph and no name.
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
