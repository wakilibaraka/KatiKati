import AppKit
import Contacts
import Foundation

/// Persists favorite contacts for the Dock II Friends HUD and provides opt-in `CNContactStore` import.
/// Never prompts for Contacts permission unless `com.katikati.dockII.friendsContactsEnabled` is true
/// and the user explicitly triggers a Contacts import or access request.
@MainActor
final class DockFriendsStore: ObservableObject {
    static let shared = DockFriendsStore()
    static let defaultsKey = "com.katikati.dockII.friends.v1"

    @Published private(set) var friends: [DockFriendContact]
    @Published private(set) var contactsAuthorization: CNAuthorizationStatus = .notDetermined

    private let defaults: UserDefaults
    private let avatarsDirectory: URL

    init(
        defaults: UserDefaults = .standard,
        avatarsDirectory: URL? = nil
    ) {
        self.defaults = defaults
        self.friends = DockFriendContact.decodeList(defaults.data(forKey: Self.defaultsKey))
        if let avatarsDirectory {
            self.avatarsDirectory = avatarsDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.avatarsDirectory = appSupport.appendingPathComponent("KatiKati/FriendAvatars", isDirectory: true)
        }
    }

    func addFriend(_ friend: DockFriendContact, avatarData: Data? = nil) {
        var entry = friend
        if let avatarData {
            entry.avatarImageFilename = saveAvatarData(avatarData, for: entry.id)
        }
        friends.append(entry)
        persist()
    }

    func updateFriend(_ friend: DockFriendContact, avatarData: Data? = nil) {
        guard let idx = friends.firstIndex(where: { $0.id == friend.id }) else { return }
        var entry = friend
        if let avatarData {
            entry.avatarImageFilename = saveAvatarData(avatarData, for: entry.id)
        }
        friends[idx] = entry
        persist()
    }

    func removeFriend(id: UUID) {
        if let filename = friends.first(where: { $0.id == id })?.avatarImageFilename {
            try? FileManager.default.removeItem(at: avatarsDirectory.appendingPathComponent(filename))
        }
        friends.removeAll { $0.id == id }
        persist()
    }

    func moveFriends(from source: IndexSet, to destination: Int) {
        var list = friends
        let moved = source.sorted().map { list[$0] }
        let before = source.filter { $0 < destination }.count
        for index in source.sorted().reversed() { list.remove(at: index) }
        list.insert(contentsOf: moved, at: destination - before)
        friends = list
        persist()
    }

    func avatarImage(for friend: DockFriendContact) -> NSImage? {
        guard let filename = friend.avatarImageFilename else { return nil }
        let url = avatarsDirectory.appendingPathComponent(filename)
        return NSImage(contentsOf: url)
    }

    /// Resolves unread badge text for a contact: explicit override if > 0, else the app-level badge from `BadgeStore`.
    func badgeText(for friend: DockFriendContact, badgesByBundleID: [String: String]) -> String? {
        if let override = friend.unreadOverride, override > 0 {
            return override > 999 ? "999+" : "\(override)"
        }
        guard let bid = friend.preferredApp.bundleIdentifier,
              let raw = badgesByBundleID[bid]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            return nil
        }
        return raw
    }

    func openFriend(_ friend: DockFriendContact) {
        if let url = friend.preferredApp.launchURL(handle: friend.handle),
           NSWorkspace.shared.open(url) {
            return
        }
        if let bid = friend.preferredApp.bundleIdentifier,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
        }
    }

    func openFaceTimeVideo(for friend: DockFriendContact) {
        let trimmed = friend.handle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty,
           let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
           let url = URL(string: "facetime://\(encoded)"),
           NSWorkspace.shared.open(url) {
            return
        }
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.FaceTime") {
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
        }
    }

    func openFaceTimeAudio(for friend: DockFriendContact) {
        let trimmed = friend.handle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty,
           let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
           let url = URL(string: "facetime-audio://\(encoded)"),
           NSWorkspace.shared.open(url) {
            return
        }
        openFaceTimeVideo(for: friend)
    }

    // MARK: Opt-in Contacts Framework Integration

    func requestContactsAccessIfAuthorizedOrOptedIn() async -> Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        contactsAuthorization = status
        if status == .authorized { return true }
        guard UserDefaults.standard.bool(forKey: "com.katikati.dockII.friendsContactsEnabled") else {
            return false
        }
        let store = CNContactStore()
        let granted = (try? await store.requestAccess(for: .contacts)) ?? false
        contactsAuthorization = CNContactStore.authorizationStatus(for: .contacts)
        return granted
    }

    struct ImportedContactCandidate: Identifiable, Equatable {
        var id: String
        var displayName: String
        var handle: String
        var thumbnailData: Data?
    }

    func searchSystemContacts(query: String) async -> [ImportedContactCandidate] {
        guard await requestContactsAccessIfAuthorizedOrOptedIn() else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return await Task.detached(priority: .userInitiated) {
            let store = CNContactStore()
            let keys: [CNKeyDescriptor] = [
                CNContactIdentifierKey as CNKeyDescriptor,
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor,
                CNContactEmailAddressesKey as CNKeyDescriptor,
                CNContactThumbnailImageDataKey as CNKeyDescriptor
            ]
            let request = CNContactFetchRequest(keysToFetch: keys)
            if !trimmed.isEmpty {
                request.predicate = CNContact.predicateForContacts(matchingName: trimmed)
            }
            var results: [ImportedContactCandidate] = []
            try? store.enumerateContacts(with: request) { contact, stop in
                let fullName = [contact.givenName, contact.familyName]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                guard !fullName.isEmpty else { return }
                let handle = contact.phoneNumbers.first?.value.stringValue
                    ?? (contact.emailAddresses.first?.value as String?)
                    ?? ""
                results.append(ImportedContactCandidate(
                    id: contact.identifier,
                    displayName: fullName,
                    handle: handle,
                    thumbnailData: contact.thumbnailImageData
                ))
                if results.count >= 40 { stop.pointee = true }
            }
            return results
        }.value
    }

    private func saveAvatarData(_ data: Data, for id: UUID) -> String? {
        try? FileManager.default.createDirectory(at: avatarsDirectory, withIntermediateDirectories: true)
        let filename = "\(id.uuidString).png"
        let url = avatarsDirectory.appendingPathComponent(filename)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return filename
    }

    private func persist() {
        defaults.set(DockFriendContact.encodeList(friends), forKey: Self.defaultsKey)
    }
}
