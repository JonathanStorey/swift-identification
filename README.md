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

`Checksum` is the first 16 bytes (128 bits) of SHA-256, so it is the same length as a UUID and
matches Python byte for byte.

```swift
let checksum = Checksum("hello world")
checksum.hex    // "b94d27b9934d3e08a52e52d7da7dabfa"
checksum.uuid   // B94D27B9-934D-3E08-A52E-52D7DA7DABFA
```

```python
import hashlib, uuid
digest = hashlib.sha256("hello world".encode()).digest()[:16]
digest.hex()              # 'b94d27b9934d3e08a52e52d7da7dabfa'
uuid.UUID(bytes=digest)   # UUID('b94d27b9-934d-3e08-a52e-52d7da7dabfa')
```

Strings are hashed as their UTF-8 bytes exactly as given. Pass `normalization: .nfc` (Python:
`unicodedata.normalize("NFC", s)`) when the same text may arrive precomposed or decomposed.
`checksum.uuid` keeps all 128 bits, so it is UUID-shaped but not an RFC 9562 UUID.

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
