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
            targets: ["PasteFloating"]
        ),
        .executable(
            name: "PasteFloating",
            targets: ["PasteFloating"]
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
                "Sources/PasteFloating",
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
            name: "PasteFloating",
            dependencies: ["ClipboardPanelApp"],
            path: "Sources/PasteFloating",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ClipboardPanelAppTests",
            dependencies: [
                "ClipboardPanelApp",
                "PasteFloating"
            ]
        )
    ]
)
