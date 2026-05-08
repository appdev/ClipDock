#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

export MACOSX_DEPLOYMENT_TARGET=13.0

cargo build --manifest-path rust/Cargo.toml -p clipboard_core_ffi

package_name="ClipboardCoreBridge"
bridge_raw_dir="rust/target/swift-bridge/generated"
bridge_crate_dir="$bridge_raw_dir/clipboard_core_ffi"
package_dir="Generated/$package_name"
headers_dir=".build/swift-bridge-headers"
static_lib="rust/target/debug/libclipboard_core_ffi.a"

mkdir -p "$package_dir/Sources/$package_name" "$headers_dir"

cp "$bridge_raw_dir/SwiftBridgeCore.h" "$headers_dir/SwiftBridgeCore.h"
cp "$bridge_crate_dir/clipboard_core_ffi.h" "$headers_dir/clipboard_core_ffi.h"

cat > "$headers_dir/module.modulemap" <<'MODULEMAP'
module RustXcframework {
    header "SwiftBridgeCore.h"
    header "clipboard_core_ffi.h"
    export *
}
MODULEMAP

{
    printf 'import RustXcframework\n'
    sed 's/\r$//' "$bridge_raw_dir/SwiftBridgeCore.swift"
} > "$package_dir/Sources/$package_name/SwiftBridgeCore.swift"

perl -0pi -e 's/extension RustStr:\s+Identifiable/extension RustStr: \@retroactive Identifiable/g; s/extension RustStr:\s+Equatable/extension RustStr: \@retroactive Equatable/g' "$package_dir/Sources/$package_name/SwiftBridgeCore.swift"

{
    printf 'import RustXcframework\n'
    sed 's/\r$//' "$bridge_crate_dir/clipboard_core_ffi.swift"
} > "$package_dir/Sources/$package_name/ClipboardCoreBridge.swift"

cat > "$package_dir/Package.swift" <<'PACKAGE'
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
            dependencies: ["RustXcframework"]
        )
    ]
)
PACKAGE

rm -rf "$package_dir/RustXcframework.xcframework"
xcodebuild -create-xcframework \
    -library "$static_lib" \
    -headers "$headers_dir" \
    -output "$package_dir/RustXcframework.xcframework" >/dev/null

mkdir -p .build/rust/debug
cp rust/target/debug/libclipboard_core_ffi.a .build/rust/debug/
