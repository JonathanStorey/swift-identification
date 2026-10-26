// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Identification",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .watchOS(.v11),
        .visionOS(.v2),
    ],
    products: [
        .library(
            name: "Identification",
            targets: ["Identification"]
        ),
    ],
    targets: [
        .target(
            name: "Identification"
        ),
        .testTarget(
            name: "IdentificationTests",
            dependencies: ["Identification"]
        ),
    ]
)
