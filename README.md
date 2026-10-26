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

A `Checksum` is the first 16 bytes (128 bits) of SHA-256, so it is the same length as a UUID and
matches Python byte for byte. Any `Digestible` value produces one, the way any `Hashable` value
produces a hash value.

```swift
let checksum = "hello world".checksum()
checksum.hex    // "b94d27b9934d3e08a52e52d7da7dabfa"
checksum.uuid   // B94D27B9-934D-3E08-A52E-52D7DA7DABFA
```

```python
import hashlib, uuid
digest = hashlib.sha256("hello world".encode()).digest()[:16]
digest.hex()              # 'b94d27b9934d3e08a52e52d7da7dabfa'
uuid.UUID(bytes=digest)   # UUID('b94d27b9-934d-3e08-a52e-52d7da7dabfa')
```

`checksum.uuid` keeps all 128 bits, so it is UUID-shaped but not an RFC 9562 UUID.

Each built-in conformance has a one-line Python equivalent:

| Swift | Bytes | Python |
| --- | --- | --- |
| `String`, `Substring` | UTF-8 as given | `s.encode()` |
| `Data`, `[UInt8]` | as given | `b` |
| `UUID` | 16 bytes | `u.bytes` |
| `Int8` … `UInt64` | big-endian, own width | `n.to_bytes(width, "big", signed=...)` |
| `Int`, `UInt` | big-endian, always 8 bytes | `n.to_bytes(8, "big", signed=...)` |
| `Double`, `Float` | IEEE 754, big-endian | `struct.pack(">d", x)`, `">f"` |
| `Bool` | one byte | `bytes([b])` |
| `[Element]` | each element in order | one `update` per element |

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

A `Digester` appends bytes with no separators, like successive `h.update(...)` calls on one
`hashlib.sha256()`, so `["ab", "c"]` and `["a", "bc"]` match. Combine a length first when that
matters. `Digester(normalization: .nfc)` hashes strings in NFC (Python:
`unicodedata.normalize("NFC", s)`) for text that may arrive precomposed or decomposed:

```swift
let checksum = name.checksum(using: Digester(normalization: .nfc))
```

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
