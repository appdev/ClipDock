// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "ClipDock",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ClipboardPanelApp",
            targets: ["ClipboardPanelApp"]
        ),
        .executable(
            name: "ClipDock",
            targets: ["ClipDock"]
        )
    ],
    dependencies: [
        .package(path: "Generated/ClipboardCoreBridge")
    ],
    targets: [
        .target(
            name: "ClipboardPanelApp",
            dependencies: [
                .product(name: "ClipboardCoreBridge", package: "ClipboardCoreBridge")
            ],
            path: "Sources/ClipboardPanelApp"
        ),
        .executableTarget(
            name: "ClipDock",
            dependencies: ["ClipboardPanelApp"],
            path: "Sources/ClipDock",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ClipboardPanelAppTests",
            dependencies: [
                "ClipboardPanelApp",
                "ClipDock"
            ]
        )
    ]
)
