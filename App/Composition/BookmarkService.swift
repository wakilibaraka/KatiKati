import Foundation

/// Phase 30g: loads Safari + Chrome bookmark files. Both live behind Full Disk Access (TCC) on current
/// macOS, so this fails closed — a missing/unreadable file just yields nothing (no prompt).
enum BookmarkService {
    static func load() -> [Bookmark] {
        let home = NSHomeDirectory()
        var out: [Bookmark] = []
        if let data = FileManager.default.contents(atPath: "\(home)/Library/Safari/Bookmarks.plist"),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
            out += BookmarkImport.parseSafari(plist)
        }
        if let data = FileManager.default.contents(atPath: "\(home)/Library/Application Support/Google/Chrome/Default/Bookmarks") {
            out += BookmarkImport.parseChrome(data)
        }
        return out
    }
}
