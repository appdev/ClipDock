// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "ClipboardCoreBridge",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ClipboardCoreBridge",
            targets: ["ClipboardCoreBridge"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "RustXcframework",
            path: "RustXcframework.xcframework"
        ),
        .target(
            name: "ClipboardCoreBridge",
            dependencies: ["RustXcframework"],
            linkerSettings: [
                .linkedFramework("SystemConfiguration")
            ]
        )
    ]
)
