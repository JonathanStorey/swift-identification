# Identification

A Swift package for unique identification and checksums built on `UUID`.

## Requirements

- Swift 6.2 or later (Xcode 26 or later)
- macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, or Linux

## Installation

Add the package to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/JonathanStorey/swift-identification.git", branch: "main"),
],
```

Then add the product to your target:

```swift
.target(
    name: "MyTarget",
    dependencies: [
        .product(name: "Identification", package: "swift-identification"),
    ]
),
```

In Xcode, choose **File ▸ Add Package Dependencies…** and enter the repository URL.

## Usage

```swift
import Identification
```

### Checksums

A `Checksum` is the first 16 bytes (128 bits) of SHA-256, so it is the same length as a UUID.
Any `Digestible` value produces one, the way any `Hashable` value produces a hash value, and
Python can reproduce it byte for byte.

```swift
let checksum = "hello world".checksum()
checksum.description    // "a6dc1f38a111301a02f8c66046712cd9"
checksum.uuid   // A6DC1F38-A111-301A-02F8-C66046712CD9
```

`checksum.uuid` keeps all 128 bits, so it is UUID-shaped but not an RFC 9562 UUID. A stored
checksum comes back with `Checksum(rawValue:)` or `Codable`, which writes the `description` hex
string. `Checksum` is `RawRepresentable` as a `UInt128`, the bytes read big-endian (Python:
`int.from_bytes(digest, "big")`), so each one is 16 bytes inline.

Conform your own types like `Hashable`:

```swift
struct Account: Digestible {
    var id: UUID
    var name: String

    func digest(into digester: inout Digester) {
        digester.combine(id)
        digester.combine(name)
    }
}
```

#### Encodings

A `Digester` turns each combined value into bytes in one of two ways.

**`.typed`** (the default) is deterministic CBOR (RFC 8949 Section 4.2). Every value carries
its type and length, so `"5"` differs from `5` and `["ab", "c"]` from `["a", "bc"]`. Numbers
are encoded by value, so `Int32(5)` equals `Int(5)` and `Float(1.5)` equals `1.5`. In Python,
with [`cbor2`](https://pypi.org/project/cbor2/):

```python
import cbor2, hashlib

def checksum(*values):
    data = b"".join(cbor2.dumps(v, canonical=True, datetime_as_timestamp=True) for v in values)
    return hashlib.sha256(data).digest()[:16]

checksum("hello world").hex()   # 'a6dc1f38a111301a02f8c66046712cd9'
```

Each `combine` call is one argument, so `Account(id: id, name: name).checksum()` equals
`checksum(id, name)`.

**`.bytes`** appends each value's plain bytes with no separators, like successive
`h.update(...)` calls. Use it to match a checksum of raw bytes computed anywhere else:

```swift
"hello world".checksum(using: Digester(encoding: .bytes)).description  // "b94d27b9934d3e08a52e52d7da7dabfa"
```

```python
hashlib.sha256("hello world".encode()).digest()[:16].hex()     # 'b94d27b9934d3e08a52e52d7da7dabfa'
```

| Swift | Python for `.typed` | Python bytes for `.bytes` |
| --- | --- | --- |
| `String`, `Substring` | `str` | `s.encode()` |
| `Data`, `[UInt8]` | `bytes` | `b` |
| `UUID` | `uuid.UUID` (CBOR tag 37) | `u.bytes` |
| `Int8` … `UInt64` | `int` | `n.to_bytes(width, "big", signed=...)` |
| `Int`, `UInt` | `int` | `n.to_bytes(8, "big", signed=...)` |
| `Double`, `Float` | `float` | `struct.pack(">d", x)`, `">f"` |
| `Bool` | `bool` | `bytes([b])` |
| `Date` | see [Dates](#dates) | see [Dates](#dates) |
| `[Element]` | `list` | each element in order |
| `[Key: Value]` | `dict` (keys sorted length-first, as cbor2 does) | each key then value, in that order |
| `Optional` | `None` for `nil` | nothing for `nil` |

Floats follow IEEE 754: `0.0` and `-0.0` differ, and every NaN is the same.

#### Dates

The default keeps every distinct `Date` apart. Choose `.microsecondsSince1970` when the same
dates live in Python as `datetime` values.

`dateDigestingStrategy` borrows its names from `JSONEncoder.DateEncodingStrategy`:

| Strategy | Precision | Python for `.typed` |
| --- | --- | --- |
| `.deferredToDate` (default) | every distinct `Date`: its `Double` since 2001 | `float` |
| `.secondsSince1970` | the `Double` since 1970 | `cbor2.CBORTag(1, t)` |
| `.millisecondsSince1970` | nearest millisecond | `datetime` with whole milliseconds |
| `.microsecondsSince1970` | nearest microsecond, like `datetime` | `datetime` (CBOR tag 1) |
| `.iso8601` | nearest microsecond, as `2026-10-26T15:00:00.250000Z` | `datetime` (CBOR tag 0, cbor2's default) |
| `.custom { date, digester in ... }` | whatever the closure combines | |

```swift
let python = Digester(dateDigestingStrategy: .microsecondsSince1970)
date.checksum(using: python)   // equals checksum(dt) for the equivalent UTC datetime
```

`Digester(stringDigestingStrategy: .normalized)` hashes strings in NFC (Python:
`unicodedata.normalize("NFC", s)`), so strings Swift's `==` calls equal, such as precomposed and
decomposed "é", get equal checksums. The default, `.verbatim`, hashes the UTF-8 bytes as given.

### Name-based UUIDs

`UUID(name:namespace:)` is RFC 9562 version 5 and equals Python's `uuid.uuid5(namespace, name)`.
`hash: .sha256` gives an RFC version 8 UUID instead.

## Testing

Tests use [Swift Testing](https://developer.apple.com/documentation/testing) (`@Test`, `@Suite`, `#expect`).

```sh
swift test
```

## License

Apache 2.0. See [LICENSE](LICENSE).
