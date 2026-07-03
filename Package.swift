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
    targets: [
        .executableTarget(
            name: "TeleMessEnd"
        ),
        .testTarget(
            name: "TeleMessEndTests",
            dependencies: ["TeleMessEnd"]
        )
    ]
)
