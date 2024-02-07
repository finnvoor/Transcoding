// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Transcoding",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "Transcoding", targets: ["Transcoding"])],
    targets: [
        .target(name: "Transcoding"),
        .testTarget(name: "TranscodingTests", dependencies: ["Transcoding"])
    ]
)
