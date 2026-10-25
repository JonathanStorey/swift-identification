import Foundation

extension UUID {
    /// A UUID created on first use and stored in `UserDefaults`.
    ///
    /// It stays the same across launches and updates, and is replaced when the app is
    /// deleted and reinstalled. It is a `UUID.timestamp`, so `Date(from: .installation)`
    /// returns when it was created.
    public static let installation: UUID = storedIdentifier(forKey: "Identification.installation", in: .standard)

    /// Reads the UUID stored under `key`, creating and storing one if none exists.
    static func storedIdentifier(forKey key: String, in defaults: UserDefaults) -> UUID {
        if let string = defaults.string(forKey: key), let id = UUID(uuidString: string) {
            return id
        }
        let id = UUID.timestamp
        defaults.set(id.uuidString, forKey: key)
        return id
    }
}
