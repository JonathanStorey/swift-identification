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

// Each conformance names its Python equivalent for both encodings. Typed values match
// `cbor2.dumps(v, canonical=True)` and bytes values match `hashlib` input.

/// Typed: a CBOR text string. Bytes: UTF-8, like `s.encode()`. Both follow the digester's
/// `stringDigestingStrategy`.
extension String: Digestible {
    public func digest(into digester: inout Digester) {
        let bytes = switch digester.stringDigestingStrategy {
        case .verbatim: Array(utf8)
        case .normalized: Array(precomposedStringWithCanonicalMapping.utf8)
        }
        if digester.encoding == .typed {
            digester.appendHead(.textString, UInt64(bytes.count))
        }
        digester.append(bytes)
    }
}

/// The same as the equivalent `String`.
extension Substring: Digestible {
    public func digest(into digester: inout Digester) {
        String(self).digest(into: &digester)
    }
}

/// Typed: a CBOR byte string, like Python `bytes`. Bytes: the bytes as given.
extension Data: Digestible {
    public func digest(into digester: inout Digester) {
        digester.appendByteString(self)
    }
}

/// Typed: CBOR tag 37 around the 16 bytes, as `cbor2` encodes `uuid.UUID`. Bytes: `u.bytes`.
extension UUID: Digestible {
    public func digest(into digester: inout Digester) {
        if digester.encoding == .typed {
            digester.appendHead(.tag, 37)
            digester.appendHead(.byteString, 16)
        }
        withUnsafeBytes(of: uuid) { digester.append($0) }
    }
}

/// Typed: a CBOR array, like a Python `list`. Bytes: each element in order, with no separators.
///
/// `[UInt8]` is the exception: it is a byte string, the same as `Data`.
extension Array: Digestible where Element: Digestible {
    public func digest(into digester: inout Digester) {
        if let bytes = self as? [UInt8] {
            digester.appendByteString(bytes)
            return
        }
        if digester.encoding == .typed {
            digester.appendHead(.array, UInt64(count))
        }
        for element in self {
            digester.combine(element)
        }
    }
}

/// Typed: a CBOR map, like a Python `dict`. Bytes: each key then its value, with no separators.
///
/// Entries are sorted by their keys' encodings, shorter first and then bytewise: the
/// length-first order of RFC 8949 Section 4.2.3, which `cbor2.dumps(d, canonical=True)` uses.
extension Dictionary: Digestible where Key: Digestible, Value: Digestible {
    public func digest(into digester: inout Digester) {
        let entries = map { (key: digester.encoded($0.key), value: digester.encoded($0.value)) }
            .sorted { first, second in
                first.key.count != second.key.count
                    ? first.key.count < second.key.count
                    : first.key.lexicographicallyPrecedes(second.key)
            }
        if digester.encoding == .typed {
            digester.appendHead(.map, UInt64(count))
        }
        for entry in entries {
            digester.append(entry.key)
            digester.append(entry.value)
        }
    }
}

/// Typed: `nil` is CBOR null, like Python `None`. Bytes: `nil` adds nothing. Either way, a
/// wrapped value is the same as the value itself.
extension Optional: Digestible where Wrapped: Digestible {
    public func digest(into digester: inout Digester) {
        switch self {
        case .some(let value):
            digester.combine(value)
        case .none:
            if digester.encoding == .typed {
                digester.append([0xF6])
            }
        }
    }
}

/// Typed: CBOR `true` or `false`. Bytes: one byte, like `bytes([b])`.
extension Bool: Digestible {
    public func digest(into digester: inout Digester) {
        switch digester.encoding {
        case .typed: digester.append([UInt8(self ? 0xF5 : 0xF4)])
        case .bytes: digester.append([UInt8(self ? 1 : 0)])
        }
    }
}

/// Typed: a CBOR integer, by value. Bytes: big-endian at the type's own width, like
/// `n.to_bytes(width, "big", signed=...)`.
extension Digestible where Self: FixedWidthInteger {
    public func digest(into digester: inout Digester) {
        switch digester.encoding {
        case .typed: digester.appendInteger(self)
        case .bytes: digester.appendBigEndian(self)
        }
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

/// As `Int64`, so the bytes encoding is always 8 bytes, even on 32-bit platforms.
extension Int: Digestible {
    public func digest(into digester: inout Digester) {
        digester.combine(Int64(self))
    }
}

/// As `UInt64`, so the bytes encoding is always 8 bytes, even on 32-bit platforms.
extension UInt: Digestible {
    public func digest(into digester: inout Digester) {
        digester.combine(UInt64(self))
    }
}

/// Typed: the shortest CBOR float that keeps the exact value, like a Python `float`.
/// Bytes: IEEE 754 big-endian, like `struct.pack(">d", x)`. `0.0` and `-0.0` differ.
extension Double: Digestible {
    public func digest(into digester: inout Digester) {
        switch digester.encoding {
        case .typed: digester.appendFloat(self)
        case .bytes: digester.appendBigEndian(bitPattern)
        }
    }
}

/// Typed: the same as the equal `Double`. Bytes: IEEE 754 big-endian, like
/// `struct.pack(">f", x)`. `0.0` and `-0.0` differ.
extension Float: Digestible {
    public func digest(into digester: inout Digester) {
        switch digester.encoding {
        case .typed: digester.appendFloat(self)
        case .bytes: digester.appendBigEndian(bitPattern)
        }
    }
}

/// As the digester's `dateDigestingStrategy` specifies.
extension Date: Digestible {
    public func digest(into digester: inout Digester) {
        switch digester.dateDigestingStrategy {
        case .deferredToDate:
            digester.combine(timeIntervalSinceReferenceDate)
        case .secondsSince1970:
            switch digester.encoding {
            case .typed:
                digester.appendHead(.tag, 1)
                digester.appendFloat(timeIntervalSince1970)
            case .bytes:
                digester.appendBigEndian(timeIntervalSince1970.bitPattern)
            }
        case .millisecondsSince1970:
            digestRounded(into: &digester, unitsPerSecond: 1_000)
        case .microsecondsSince1970:
            digestRounded(into: &digester, unitsPerSecond: 1_000_000)
        case .iso8601:
            if digester.encoding == .typed {
                digester.appendHead(.tag, 0)
            }
            digester.combine(iso8601String)
        case .custom(let closure):
            closure(self, &digester)
        }
    }

    private func digestRounded(into digester: inout Digester, unitsPerSecond: Int64) {
        let units = Int64((timeIntervalSince1970 * Double(unitsPerSecond)).rounded())
        switch digester.encoding {
        case .typed:
            // The same arithmetic as cbor2: whole seconds, plus microseconds / 1_000_000.
            let (seconds, fraction) = floorDivision(units, unitsPerSecond)
            digester.appendHead(.tag, 1)
            if fraction == 0 {
                digester.appendInteger(seconds)
            } else {
                let microseconds = fraction * (1_000_000 / unitsPerSecond)
                digester.appendFloat(Double(seconds) + Double(microseconds) / 1_000_000)
            }
        case .bytes:
            digester.appendBigEndian(units)
        }
    }

    /// The RFC 3339 form that Python's `datetime.isoformat()` writes for UTC, with `Z`.
    ///
    /// Formatted by hand so it never depends on a locale, a calendar or a formatter's options.
    private var iso8601String: String {
        let microseconds = Int64((timeIntervalSince1970 * 1_000_000).rounded())
        let (seconds, fraction) = floorDivision(microseconds, 1_000_000)
        let (days, secondOfDay) = floorDivision(seconds, 86_400)

        // Civil date from days since 1970 (Howard Hinnant, "chrono-Compatible Low-Level Date Algorithms").
        let shifted = days + 719_468
        let era = floorDivision(shifted, 146_097).quotient
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
        let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)

        var text = String(
            format: "%04lld-%02lld-%02lldT%02lld:%02lld:%02lld",
            year, month, day, secondOfDay / 3_600, secondOfDay / 60 % 60, secondOfDay % 60
        )
        if fraction != 0 {
            text += String(format: ".%06lld", fraction)
        }
        return text + "Z"
    }
}

/// Division that rounds toward negative infinity, so the remainder is never negative.
private func floorDivision(_ dividend: Int64, _ divisor: Int64) -> (quotient: Int64, remainder: Int64) {
    let (quotient, remainder) = dividend.quotientAndRemainder(dividingBy: divisor)
    return remainder < 0 ? (quotient - 1, remainder + divisor) : (quotient, remainder)
}
