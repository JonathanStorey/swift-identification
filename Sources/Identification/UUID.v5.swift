import Foundation

extension UUID {
    /// The hash used for a name-based UUID.
    public enum NameHash: Sendable {
        /// UUID version 5 (RFC 9562 Section 5.5). Interoperable with every UUID library.
        case sha1
        /// UUID version 8 using SHA-256, as in RFC 9562 Appendix B.2. A stronger hash,
        /// but other libraries will not generate it by default.
        case sha256
    }

    /// Creates the name-based UUID for `name` in `namespace`.
    ///
    /// The same namespace, name and hash always produce the same UUID, in any language that
    /// implements RFC 9562. It is a fingerprint, not a secret: anyone who can guess the name
    /// can recompute it.
    public init(name: some Sequence<UInt8>, namespace: UUID, hash: NameHash = .sha1) {
        let message = withUnsafeBytes(of: namespace.uuid) { Array($0) } + Array(name)
        var bytes: [UInt8]
        switch hash {
        case .sha1:
            bytes = SHA.sha1(message)
            bytes[6] = bytes[6] & 0x0F | 0x50
        case .sha256:
            bytes = SHA.sha256(message)
            bytes[6] = bytes[6] & 0x0F | 0x80
        }
        bytes[8] = bytes[8] & 0x3F | 0x80

        self.init(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// Creates the name-based UUID for the UTF-8 bytes of `name` in `namespace`.
    public init(name: String, namespace: UUID, hash: NameHash = .sha1) {
        self.init(name: name.utf8, namespace: namespace, hash: hash)
    }

    /// The RFC 9562 namespace for fully qualified domain names.
    public static let dns = UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")!
    /// The RFC 9562 namespace for URLs.
    public static let url = UUID(uuidString: "6BA7B811-9DAD-11D1-80B4-00C04FD430C8")!
    /// The RFC 9562 namespace for ISO object identifiers.
    public static let oid = UUID(uuidString: "6BA7B812-9DAD-11D1-80B4-00C04FD430C8")!
    /// The RFC 9562 namespace for X.500 distinguished names.
    public static let x500 = UUID(uuidString: "6BA7B814-9DAD-11D1-80B4-00C04FD430C8")!
}
