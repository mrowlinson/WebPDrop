// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WebPDrop",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/ainame/Swift-WebP.git", from: "0.6.0")
    ],
    targets: [
        .executableTarget(
            name: "WebPDrop",
            dependencies: [.product(name: "WebP", package: "Swift-WebP")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
