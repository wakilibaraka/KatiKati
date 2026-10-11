import CryptoKit
import Foundation
import Security

/// Stores the notes AES key as a generic-password Keychain item (this device only, no iCloud
/// Keychain sync, available after first unlock). Created lazily on first use.
struct KeychainNoteKeyProvider: NoteKeyProviding {
    enum KeychainError: Error { case status(OSStatus), malformed }

    let service: String
    let account: String

    init(service: String = "com.katikati.notes", account: String = "note-key") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func loadOrCreateKey() throws -> SymmetricKey {
        var read = baseQuery
        read[kSecReturnData as String] = true
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &item)
        if status == errSecSuccess {
            guard let data = item as? Data, data.count == 32 else { throw KeychainError.malformed }
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else { throw KeychainError.status(status) }

        let key = NoteCipher.generateKey()
        var add = baseQuery
        add[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        if addStatus == errSecDuplicateItem { return try loadOrCreateKey() }   // lost a creation race
        guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
        return key
    }
}
