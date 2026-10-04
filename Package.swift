// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "spatial-photo-extractor",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .visionOS(.v2),
    ],
    products: [
        .library(name: "SpatialPhotoKit", targets: ["SpatialPhotoKit"]),
        .executable(name: "spatial-photo-extractor", targets: ["SpatialPhotoExtractorCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(name: "SpatialPhotoKit"),
        .executableTarget(
            name: "SpatialPhotoExtractorCLI",
            dependencies: [
                "SpatialPhotoKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "SpatialPhotoKitTests",
            dependencies: ["SpatialPhotoKit"]
        ),
    ]
)
