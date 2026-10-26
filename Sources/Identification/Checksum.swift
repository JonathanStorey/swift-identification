import Foundation

/// A 128-bit checksum: the first 16 bytes of the SHA-256 digest, as permitted by NIST SP 800-107.
///
/// Produce one with `value.checksum()` or a `Digester`. It matches Python byte for byte:
/// `hashlib.sha256(data).digest()[:16]`. It is a fingerprint, not a secret or a signature.
public struct Checksum: Hashable, Sendable, CustomStringConvertible, Codable {
    /// The 16 checksum bytes.
    public let bytes: [UInt8]

    init(sha256 digest: [UInt8]) {
        bytes = Array(digest.prefix(16))
    }

    /// Restores a checksum from its 32 hexadecimal digits, in either case.
    public init?(hex: String) {
        let digits = Array(hex.utf8)
        guard digits.count == 32 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(16)
        for index in stride(from: 0, to: 32, by: 2) {
            guard let high = Self.value(ofHexDigit: digits[index]),
                  let low = Self.value(ofHexDigit: digits[index + 1])
            else { return nil }
            bytes.append(high << 4 | low)
        }
        self.bytes = bytes
    }

    /// Restores a checksum from the `UUID` its `uuid` property produced.
    public init(uuid: UUID) {
        bytes = withUnsafeBytes(of: uuid.uuid) { Array($0) }
    }

    /// Decodes a checksum stored as its hexadecimal string.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let hex = try container.decode(String.self)
        guard let checksum = Checksum(hex: hex) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected 32 hexadecimal digits, found \"\(hex)\"."
            )
        }
        self = checksum
    }

    /// Encodes the checksum as its hexadecimal string.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }

    private static func value(ofHexDigit digit: UInt8) -> UInt8? {
        switch digit {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): digit - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): digit - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): digit - UInt8(ascii: "A") + 10
        default: nil
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
