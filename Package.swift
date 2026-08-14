// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "fx-widget",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "FXCore", targets: ["FXCore"])
    ],
    targets: [
        .target(
            name: "FXCore",
            path: "Sources/FXCore",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "FXCoreTests",
            dependencies: ["FXCore"],
            path: "Tests/FXCoreTests"
        )
    ]
)
