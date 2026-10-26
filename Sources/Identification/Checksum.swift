import Foundation

/// A 128-bit checksum: the first 16 bytes of the SHA-256 digest, as permitted by NIST SP 800-107.
///
/// Produce one with `value.checksum()` or a `Digester`. It matches Python byte for byte:
/// `hashlib.sha256(data).digest()[:16]`. It is a fingerprint, not a secret or a signature.
public struct Checksum: Hashable, Sendable, CustomStringConvertible {
    /// The 16 checksum bytes.
    public let bytes: [UInt8]

    init(sha256 digest: [UInt8]) {
        bytes = Array(digest.prefix(16))
    }

    /// The checksum as 32 lowercase hexadecimal digits, like Python's `.hex()`.
    public var hex: String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// The checksum bytes stored unchanged in a `UUID`, like Python's `uuid.UUID(bytes=digest)`.
    ///
    /// Every one of the 128 bits is kept, so this is not an RFC 9562 UUID: its version and
    /// variant fields hold hash bits. For a valid version 8 UUID, which gives up 6 bits, use
    /// `UUID(name:namespace:hash: .sha256)` instead. The two will not be equal.
    public var uuid: UUID {
        UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    public var description: String { hex }
}
