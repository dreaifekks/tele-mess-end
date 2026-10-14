// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TeleMessEnd",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TeleMessEnd", targets: ["TeleMessEnd"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0")
    ],
    targets: [
        .executableTarget(
            name: "TeleMessEnd",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")]
        ),
        .testTarget(
            name: "TeleMessEndTests",
            dependencies: ["TeleMessEnd"]
        )
    ]
)
