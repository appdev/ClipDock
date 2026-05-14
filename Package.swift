// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "ClipShelf",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ClipboardPanelApp",
            targets: ["ClipboardPanelApp"]
        ),
        .executable(
            name: "ClipShelf",
            targets: ["ClipShelf"]
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
            path: ".",
            exclude: [
                ".build",
                ".codex",
                "docs",
                "Generated",
                "rust",
                "scripts",
                "Sources/ClipShelf",
                "Tests",
                "README.md",
                "AGENTS.md",
                "verification.md",
                "Package.swift"
            ],
            sources: [
                "Sources/ClipboardPanelApp"
            ]
        ),
        .executableTarget(
            name: "ClipShelf",
            dependencies: ["ClipboardPanelApp"],
            path: "Sources/ClipShelf",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ClipboardPanelAppTests",
            dependencies: [
                "ClipboardPanelApp",
                "ClipShelf"
            ]
        )
    ]
)
