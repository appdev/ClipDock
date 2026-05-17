#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

export MACOSX_DEPLOYMENT_TARGET=13.0

default_rust_target() {
    case "$(uname -m)" in
        arm64|aarch64) printf 'aarch64-apple-darwin' ;;
        x86_64) printf 'x86_64-apple-darwin' ;;
        *)
            echo "unsupported host architecture: $(uname -m)" >&2
            exit 1
            ;;
    esac
}

normalize_rust_target() {
    case "$1" in
        arm64|aarch64|aarch64-apple-darwin) printf 'aarch64-apple-darwin' ;;
        x64|x86_64|x86_64-apple-darwin) printf 'x86_64-apple-darwin' ;;
        *)
            echo "unsupported Rust target or architecture: $1" >&2
            exit 1
            ;;
    esac
}

target_inputs="${RUST_DARWIN_TARGETS:-$(default_rust_target)}"
target_inputs="${target_inputs//,/ }"
rust_targets=()

for target_input in $target_inputs; do
    target="$(normalize_rust_target "$target_input")"
    already_added=0
    if [[ "${#rust_targets[@]}" -gt 0 ]]; then
        for existing_target in "${rust_targets[@]}"; do
            if [[ "$existing_target" == "$target" ]]; then
                already_added=1
                break
            fi
        done
    fi
    if [[ "$already_added" == "0" ]]; then
        rust_targets+=("$target")
    fi
done

if [[ "${#rust_targets[@]}" -eq 0 ]]; then
    echo "no Rust targets requested" >&2
    exit 1
fi

for target in "${rust_targets[@]}"; do
    if command -v rustup >/dev/null 2>&1 && ! rustup target list --installed | grep -qx "$target"; then
        rustup target add "$target"
    fi

    cargo build --manifest-path rust/Cargo.toml -p clipboard_core_ffi --release --target "$target"
done

package_name="ClipboardCoreBridge"
bridge_raw_dir="rust/target/swift-bridge/generated"
bridge_crate_dir="$bridge_raw_dir/clipboard_core_ffi"
package_dir="Generated/$package_name"
headers_dir=".build/swift-bridge-headers"
universal_lib_dir=".build/rust/universal"
static_libs=()

for target in "${rust_targets[@]}"; do
    static_lib="rust/target/$target/release/libclipboard_core_ffi.a"
    if [[ ! -f "$static_lib" ]]; then
        echo "Rust static library not found: $static_lib" >&2
        exit 1
    fi
    static_libs+=("$static_lib")
done

mkdir -p "$package_dir/Sources/$package_name" "$headers_dir" "$universal_lib_dir"

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

xcframework_lib="${static_libs[0]}"
if [[ "${#static_libs[@]}" -gt 1 ]]; then
    xcframework_lib="$universal_lib_dir/libclipboard_core_ffi.a"
    rm -f "$xcframework_lib"
    lipo -create "${static_libs[@]}" -output "$xcframework_lib"
fi

xcodebuild -create-xcframework \
    -library "$xcframework_lib" \
    -headers "$headers_dir" \
    -output "$package_dir/RustXcframework.xcframework" >/dev/null

mkdir -p .build/rust/release
cp "$xcframework_lib" .build/rust/release/
