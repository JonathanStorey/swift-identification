import Foundation

/// A 128-bit checksum: the first 16 bytes of the SHA-256 digest, as permitted by NIST SP 800-107.
///
/// It matches Python byte for byte: `hashlib.sha256(data).digest()[:16]`, and for a string,
/// `hashlib.sha256(s.encode()).digest()[:16]`. It is a fingerprint, not a secret or a signature.
public struct Checksum: Hashable, Sendable, CustomStringConvertible {
    /// How a string is turned into bytes before hashing.
    public enum Normalization: Sendable {
        /// Hash the UTF-8 bytes exactly as given, like Python's `s.encode()`.
        case none
        /// Hash the UTF-8 bytes of the NFC form, like `unicodedata.normalize("NFC", s).encode()`.
        /// Use it when the same text may arrive precomposed ("é") or decomposed ("e" + "◌́").
        case nfc
    }

    /// The 16 checksum bytes.
    public let bytes: [UInt8]

    /// Creates the checksum of `data`.
    public init(_ data: some Sequence<UInt8>) {
        bytes = Array(SHA.sha256(Array(data)).prefix(16))
    }

    /// Creates the checksum of the UTF-8 bytes of `string`.
    public init(_ string: String, normalization: Normalization = .none) {
        switch normalization {
        case .none: self.init(string.utf8)
        case .nfc: self.init(string.precomposedStringWithCanonicalMapping.utf8)
        }
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
