import Foundation
#if canImport(Security)
import Security
import Synchronization

extension UUID {
    /// A UUID created on first use and stored in the Keychain, or `nil` if the Keychain is
    /// unavailable.
    ///
    /// On iOS, tvOS, watchOS and visionOS it survives deleting and reinstalling the app. It stays
    /// on this device: it is not synced through iCloud Keychain or restored to a new device from
    /// a backup. The Keychain is locked after a restart until the first unlock, so this returns
    /// `nil` until then and retries on the next read.
    public static var persistent: UUID? {
        persistentCache.withLock { cached in
            if cached == nil {
                cached = keychainIdentifier(service: "Identification", account: "persistent")
            }
            return cached
        }
    }

    private static let persistentCache = Mutex<UUID?>(nil)

    /// Reads the UUID stored in the Keychain item, creating and storing one if none exists.
    static func keychainIdentifier(service: String, account: String) -> UUID? {
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]

        var lookup = item
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecSuccess {
            guard let data = result as? Data, let string = String(data: data, encoding: .utf8) else { return nil }
            return UUID(uuidString: string)
        }
        guard status == errSecItemNotFound else { return nil }

        let id = UUID.timestamp
        var addition = item
        addition[kSecValueData as String] = Data(id.uuidString.utf8)
        addition[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        switch SecItemAdd(addition as CFDictionary, nil) {
        case errSecSuccess:
            return id
        case errSecDuplicateItem:
            // Another process created it first.
            return keychainIdentifier(service: service, account: account)
        default:
            return nil
        }
    }
}
#endif
