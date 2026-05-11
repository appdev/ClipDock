// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "ClipboardWorkbench",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ClipboardPanelApp",
            targets: ["ClipboardPanelApp"]
        ),
        .executable(
            name: "ClipboardWorkbenchApp",
            targets: ["PasteFloatingDemo"]
        ),
        .executable(
            name: "PasteFloatingDemo",
            targets: ["PasteFloatingDemo"]
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
                "Sources/PasteFloatingDemo",
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
            name: "PasteFloatingDemo",
            dependencies: ["ClipboardPanelApp"]
        ),
        .testTarget(
            name: "ClipboardPanelAppTests",
            dependencies: [
                "ClipboardPanelApp",
                "PasteFloatingDemo"
            ]
        )
    ]
)
