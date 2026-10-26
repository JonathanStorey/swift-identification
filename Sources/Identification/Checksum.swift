import Foundation

/// A 128-bit checksum: the first 16 bytes of the SHA-256 digest, as permitted by NIST SP 800-107.
///
/// Produce one with `value.checksum()` or a `Digester`. It matches Python byte for byte:
/// `hashlib.sha256(data).digest()[:16]`. It is a fingerprint, not a secret or a signature.
///
/// The raw value is those 16 bytes read as a big-endian integer, like Python's
/// `int.from_bytes(digest, "big")`, so a checksum is 16 bytes inline with no allocation.
public struct Checksum: RawRepresentable, Hashable, Sendable, CustomStringConvertible, Codable {
    /// The checksum bytes as a big-endian integer.
    public let rawValue: UInt128

    /// Creates the checksum whose bytes are `rawValue` in big-endian order.
    public init(rawValue: UInt128) {
        self.rawValue = rawValue
    }

    init(sha256 digest: [UInt8]) {
        self.init(bigEndianBytes: digest.prefix(16))
    }

    private init(bigEndianBytes bytes: some Sequence<UInt8>) {
        rawValue = bytes.reduce(0) { $0 << 8 | UInt128($1) }
    }

    /// Restores a checksum from its 32 hexadecimal digits, in either case.
    public init?(hex: String) {
        let digits = Array(hex.utf8)
        guard digits.count == 32 else { return nil }
        var rawValue: UInt128 = 0
        for digit in digits {
            guard let value = Self.value(ofHexDigit: digit) else { return nil }
            rawValue = rawValue << 4 | UInt128(value)
        }
        self.init(rawValue: rawValue)
    }

    /// Restores a checksum from the `UUID` its `uuid` property produced.
    public init(uuid: UUID) {
        self = withUnsafeBytes(of: uuid.uuid) { Checksum(bigEndianBytes: $0) }
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

    /// The 16 checksum bytes, like Python's `digest[:16]`.
    public var bytes: [UInt8] {
        (0..<16).map { UInt8(truncatingIfNeeded: rawValue >> (120 - 8 * $0)) }
    }

    /// The checksum as 32 lowercase hexadecimal digits, like Python's `.hex()`.
    public var hex: String {
        let digits = String(rawValue, radix: 16)
        return String(repeating: "0", count: 32 - digits.count) + digits
    }

    /// The checksum bytes stored unchanged in a `UUID`, like Python's `uuid.UUID(bytes=digest)`.
    ///
    /// Every one of the 128 bits is kept, so this is not an RFC 9562 UUID: its version and
    /// variant fields hold hash bits. For a valid version 8 UUID, which gives up 6 bits, use
    /// `UUID(name:namespace:hash: .sha256)` instead. The two will not be equal.
    public var uuid: UUID {
        let bytes = bytes
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    public var description: String { hex }
}
