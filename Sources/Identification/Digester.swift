/// Feeds values into a `Checksum`, the way `Hasher` feeds a hash value.
///
/// `combine` appends each value's encoding to a byte stream and `finalize()` hashes it, like
/// Python's `h = hashlib.sha256()`, `h.update(...)`, `h.digest()[:16]`. The encoding decides
/// which bytes a value contributes.
public struct Digester: Sendable {
    /// How values are turned into bytes.
    public enum Encoding: Sendable {
        /// Deterministic CBOR (RFC 8949 Section 4.2), one data item per `combine`.
        ///
        /// Every value carries its type and length, so `"5"` differs from `5` and
        /// `["ab", "c"]` from `["a", "bc"]`. Numbers are encoded by value, not width, so
        /// `Int32(5)` equals `Int(5)` and `Float(1.5)` equals `1.5`. In Python:
        /// `b"".join(cbor2.dumps(v, canonical=True, datetime_as_timestamp=True) for v in values)`.
        case typed
        /// Each value's plain bytes, appended without separators, so `"ab"` then `"c"` equals
        /// `"abc"`. Use it to match a checksum of raw bytes computed elsewhere, such as Python's
        /// `hashlib.sha256(s.encode()).digest()[:16]`.
        case bytes
    }

    /// How strings are turned into bytes.
    public enum Normalization: Sendable {
        /// The UTF-8 bytes exactly as given, like Python's `s.encode()`.
        case none
        /// The UTF-8 bytes of the NFC form, like `unicodedata.normalize("NFC", s).encode()`.
        /// Use it when the same text may arrive precomposed ("é") or decomposed ("e" + "◌́").
        case nfc
    }

    /// How values combined into this digester are turned into bytes.
    public let encoding: Encoding

    /// How strings combined into this digester are turned into bytes.
    public let normalization: Normalization

    private var message: [UInt8] = []

    /// Creates an empty digester.
    public init(encoding: Encoding = .typed, normalization: Normalization = .none) {
        self.encoding = encoding
        self.normalization = normalization
    }

    /// Adds `value` to the digester.
    public mutating func combine(_ value: some Digestible) {
        value.digest(into: &self)
    }

    /// Adds a byte string to the digester: a CBOR byte string when typed, like Python's
    /// `cbor2.dumps(b)`, or the bytes themselves, like `h.update(b)`.
    public mutating func combine(bytes: some Sequence<UInt8>) {
        switch encoding {
        case .typed:
            let bytes = Array(bytes)
            appendHead(.byteString, UInt64(bytes.count))
            append(bytes)
        case .bytes:
            append(bytes)
        }
    }

    /// Returns the checksum of everything combined so far.
    public consuming func finalize() -> Checksum {
        Checksum(sha256: SHA.sha256(message))
    }

    /// Appends bytes exactly as given, whatever the encoding.
    mutating func append(_ bytes: some Sequence<UInt8>) {
        message.append(contentsOf: bytes)
    }
}

// MARK: - Deterministic CBOR

extension Digester {
    /// The CBOR major types this package writes.
    enum MajorType: UInt8 {
        case unsigned = 0
        case negative = 1
        case byteString = 2
        case textString = 3
        case array = 4
        case tag = 6
        case simple = 7
    }

    /// Appends a data item's head with its argument in the shortest form (RFC 8949 Section 4.2.1).
    mutating func appendHead(_ type: MajorType, _ argument: UInt64) {
        let major = type.rawValue << 5
        switch argument {
        case 0..<24:
            append([major | UInt8(argument)])
        case 24...0xFF:
            append([major | 24, UInt8(argument)])
        case 0x100...0xFFFF:
            append([major | 25])
            appendBigEndian(UInt16(argument))
        case 0x1_0000...0xFFFF_FFFF:
            append([major | 26])
            appendBigEndian(UInt32(argument))
        default:
            append([major | 27])
            appendBigEndian(argument)
        }
    }

    /// Appends an integer as CBOR major type 0 or 1.
    mutating func appendInteger<T: BinaryInteger>(_ value: T) {
        if value < 0 {
            appendHead(.negative, UInt64(~value))
        } else {
            appendHead(.unsigned, UInt64(value))
        }
    }

    /// Appends a float in the shortest of half, single and double precision that keeps its
    /// exact value, with every NaN as the canonical half-precision NaN.
    mutating func appendFloat(_ value: Double) {
        if value.isNaN {
            append([0xF9, 0x7E, 0x00])
        } else if Double(Float(value)).bitPattern == value.bitPattern {
            appendFloat(Float(value))
        } else {
            append([MajorType.simple.rawValue << 5 | 27])
            appendBigEndian(value.bitPattern)
        }
    }

    /// Appends a float in the shortest of half and single precision that keeps its exact value.
    mutating func appendFloat(_ value: Float) {
        if value.isNaN {
            append([0xF9, 0x7E, 0x00])
        } else if let half = Self.halfBits(value) {
            append([MajorType.simple.rawValue << 5 | 25])
            appendBigEndian(half)
        } else {
            append([MajorType.simple.rawValue << 5 | 26])
            appendBigEndian(value.bitPattern)
        }
    }

    /// Appends a fixed-width integer as its big-endian bytes.
    mutating func appendBigEndian(_ value: some FixedWidthInteger) {
        withUnsafeBytes(of: value.bigEndian) { append($0) }
    }

    /// The IEEE 754 half-precision bits for `value`, or nil if it would lose precision.
    ///
    /// Written out by hand because `Float16` is unavailable on Intel Macs.
    static func halfBits(_ value: Float) -> UInt16? {
        let bits = value.bitPattern
        let sign = UInt16(truncatingIfNeeded: bits >> 16) & 0x8000
        let exponent = Int(bits >> 23 & 0xFF)
        let mantissa = bits & 0x7F_FFFF

        if exponent == 0xFF { return mantissa == 0 ? sign | 0x7C00 : nil }
        if exponent == 0 { return mantissa == 0 ? sign : nil }

        let power = exponent - 127
        if power > 15 { return nil }
        if power >= -14 {
            guard mantissa & 0x1FFF == 0 else { return nil }
            return sign | UInt16(power + 15) << 10 | UInt16(mantissa >> 13)
        }

        // Half-precision subnormals are multiples of 2^-24.
        let shift = -(power + 1)
        guard shift < 24 else { return nil }
        let significand = mantissa | 0x80_0000
        guard significand & ((1 << shift) - 1) == 0 else { return nil }
        return sign | UInt16(significand >> shift)
    }
}
