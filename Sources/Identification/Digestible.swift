import Foundation

/// A type that can be fed into a `Digester` to produce a reproducible `Checksum`.
///
/// Conform the way you would to `Hashable`: combine the fields that define the value.
///
/// ```swift
/// struct Account: Digestible {
///     var id: UUID
///     var name: String
///
///     func digest(into digester: inout Digester) {
///         digester.combine(id)
///         digester.combine(name)
///     }
/// }
/// ```
///
/// Unlike a hash value, a checksum is stable across launches, platforms and languages, so it
/// can be stored or compared with one computed elsewhere.
public protocol Digestible {
    /// Adds this value's bytes to `digester`.
    func digest(into digester: inout Digester)

    /// The checksum of this value alone.
    func checksum() -> Checksum
}

extension Digestible {
    public func checksum() -> Checksum {
        checksum(using: Digester())
    }

    /// The checksum of this value, combined into `digester` after anything it already holds.
    public func checksum(using digester: Digester) -> Checksum {
        var digester = digester
        digester.combine(self)
        return digester.finalize()
    }
}

// MARK: - Standard library and Foundation

/// UTF-8, normalized as the digester specifies. Python: `s.encode()`.
extension String: Digestible {
    public func digest(into digester: inout Digester) {
        switch digester.normalization {
        case .none: digester.combine(bytes: utf8)
        case .nfc: digester.combine(bytes: precomposedStringWithCanonicalMapping.utf8)
        }
    }
}

/// The same bytes as the equivalent `String`.
extension Substring: Digestible {
    public func digest(into digester: inout Digester) {
        String(self).digest(into: &digester)
    }
}

/// The bytes as given. Python: `b`.
extension Data: Digestible {
    public func digest(into digester: inout Digester) {
        digester.combine(bytes: self)
    }
}

/// The 16 bytes in RFC order. Python: `u.bytes`.
extension UUID: Digestible {
    public func digest(into digester: inout Digester) {
        withUnsafeBytes(of: uuid) { digester.combine(bytes: $0) }
    }
}

/// Each element in order, with no separators, so `[UInt8]` digests as its raw bytes.
extension Array: Digestible where Element: Digestible {
    public func digest(into digester: inout Digester) {
        for element in self {
            digester.combine(element)
        }
    }
}

/// One byte, 1 or 0. Python: `bytes([b])`.
extension Bool: Digestible {
    public func digest(into digester: inout Digester) {
        digester.combine(bytes: [UInt8(self ? 1 : 0)])
    }
}

/// Big-endian, at the type's own width. Python: `n.to_bytes(width, "big", signed=...)`.
extension Digestible where Self: FixedWidthInteger {
    public func digest(into digester: inout Digester) {
        withUnsafeBytes(of: bigEndian) { digester.combine(bytes: $0) }
    }
}

extension Int8: Digestible {}
extension Int16: Digestible {}
extension Int32: Digestible {}
extension Int64: Digestible {}
extension UInt8: Digestible {}
extension UInt16: Digestible {}
extension UInt32: Digestible {}
extension UInt64: Digestible {}

/// Always 8 bytes, as `Int64`, so the checksum is the same on 32-bit platforms.
extension Int: Digestible {
    public func digest(into digester: inout Digester) {
        digester.combine(Int64(self))
    }
}

/// Always 8 bytes, as `UInt64`, so the checksum is the same on 32-bit platforms.
extension UInt: Digestible {
    public func digest(into digester: inout Digester) {
        digester.combine(UInt64(self))
    }
}

/// IEEE 754, big-endian. Python: `struct.pack(">d", x)`. `0.0` and `-0.0` differ.
extension Double: Digestible {
    public func digest(into digester: inout Digester) {
        digester.combine(bitPattern)
    }
}

/// IEEE 754, big-endian. Python: `struct.pack(">f", x)`. `0.0` and `-0.0` differ.
extension Float: Digestible {
    public func digest(into digester: inout Digester) {
        digester.combine(bitPattern)
    }
}
