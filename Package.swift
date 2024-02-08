// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Transcoding",
    platforms: [.iOS(.v15), .macOS(.v13), .visionOS(.v1), .tvOS(.v15)],
    products: [.library(name: "Transcoding", targets: ["Transcoding"])],
    targets: [
        .target(name: "Transcoding"),
        .testTarget(name: "TranscodingTests", dependencies: ["Transcoding"])
    ]
)
