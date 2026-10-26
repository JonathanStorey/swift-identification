/// Feeds values into a `Checksum`, the way `Hasher` feeds a hash value.
///
/// A digester is a byte stream: each `combine` appends bytes and `finalize()` hashes them all,
/// exactly like Python's `h = hashlib.sha256()`, `h.update(...)`, `h.digest()[:16]`.
///
/// Values are appended without separators, so `"ab"` then `"c"` digests the same as `"abc"`.
/// When a type combines several variable-length fields, combine a length or a fixed-width tag
/// first if different values must never collide.
public struct Digester: Sendable {
    /// How strings are turned into bytes.
    public enum Normalization: Sendable {
        /// The UTF-8 bytes exactly as given, like Python's `s.encode()`.
        case none
        /// The UTF-8 bytes of the NFC form, like `unicodedata.normalize("NFC", s).encode()`.
        /// Use it when the same text may arrive precomposed ("é") or decomposed ("e" + "◌́").
        case nfc
    }

    /// How strings combined into this digester are turned into bytes.
    public let normalization: Normalization

    private var message: [UInt8] = []

    /// Creates an empty digester.
    public init(normalization: Normalization = .none) {
        self.normalization = normalization
    }

    /// Adds `value` to the digester.
    public mutating func combine(_ value: some Digestible) {
        value.digest(into: &self)
    }

    /// Adds raw bytes to the digester, like Python's `h.update(data)`.
    public mutating func combine(bytes: some Sequence<UInt8>) {
        message.append(contentsOf: bytes)
    }

    /// Returns the checksum of everything combined so far.
    public consuming func finalize() -> Checksum {
        Checksum(sha256: SHA.sha256(message))
    }
}
