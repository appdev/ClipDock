// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "ClipDock",
    defaultLocalization: "zh-Hans",
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
            path: "Sources/ClipboardPanelApp",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("SystemConfiguration")
            ]
        ),
        .executableTarget(
            name: "ClipDock",
            dependencies: ["ClipboardPanelApp"],
            path: "Sources/ClipDock",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("SystemConfiguration")
            ]
        ),
        .testTarget(
            name: "ClipboardPanelAppTests",
            dependencies: [
                "ClipboardPanelApp",
                "ClipDock"
            ],
            linkerSettings: [
                .linkedFramework("SystemConfiguration")
            ]
        )
    ]
)
