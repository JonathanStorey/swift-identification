# Identification

A Swift package for unique identification and checksums built on `UUID`.

> **Status:** early skeleton. The public API is not yet defined.

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

## Testing

Tests use [Swift Testing](https://developer.apple.com/documentation/testing) (`@Test`, `@Suite`, `#expect`).

```sh
swift test
```

## License

Apache 2.0. See [LICENSE](LICENSE).
