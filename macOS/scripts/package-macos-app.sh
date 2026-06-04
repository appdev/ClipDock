#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

source scripts/app-metadata.sh

export MACOSX_DEPLOYMENT_TARGET=13.0
export CLANG_MODULE_CACHE_PATH="$(pwd)/.build/clang-module-cache"

mkdir -p "$CLANG_MODULE_CACHE_PATH"

app_bundle_name="${APP_BUNDLE_NAME:-ClipDock}"
bundle_executable_name="${APP_EXECUTABLE_NAME:-ClipDock}"

app_path="${1:-.codex/artifacts/${app_bundle_name}.app}"
if [[ "$app_path" != *.app ]]; then
    app_path="$app_path/${app_bundle_name}.app"
fi

case "$app_path" in
    /*) ;;
    *) app_path="$(pwd)/$app_path" ;;
esac

app_name="$(basename "$app_path" .app)"
contents_dir="$app_path/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
bundle_identifier="${BUNDLE_IDENTIFIER:-com.apkdv.clipdock}"
display_name="${APP_DISPLAY_NAME:-ClipDock}"
app_version="${APP_VERSION:-$(read_release_version "$(read_app_info_value CFBundleShortVersionString 0.1.0)")}"
app_build="${APP_BUILD:-$(read_release_build "$(read_app_info_value CFBundleVersion 1)")}"
codesign_identity="${CODESIGN_IDENTITY:--}"
app_icon_file="${APP_ICON_FILE:-Sources/ClipDock/Resources/AppIcon.icns}"
status_icon_file="${STATUS_ICON_FILE:-Sources/ClipDock/Resources/StatusBarClipboardTemplate.png}"
app_arch_inputs="${APP_ARCHS:-arm64 x86_64}"
app_arch_inputs="${app_arch_inputs//,/ }"
app_archs=()
swift_triples=()
rust_targets=()

normalize_app_arch() {
    case "$1" in
        arm64|aarch64) printf 'arm64' ;;
        x64|x86_64) printf 'x86_64' ;;
        *)
            echo "unsupported app architecture: $1" >&2
            exit 1
            ;;
    esac
}

for app_arch_input in $app_arch_inputs; do
    app_arch="$(normalize_app_arch "$app_arch_input")"
    already_added=0
    if [[ "${#app_archs[@]}" -gt 0 ]]; then
        for existing_arch in "${app_archs[@]}"; do
            if [[ "$existing_arch" == "$app_arch" ]]; then
                already_added=1
                break
            fi
        done
    fi
    if [[ "$already_added" == "1" ]]; then
        continue
    fi

    app_archs+=("$app_arch")
    swift_triples+=("$app_arch-apple-macosx13.0")
    case "$app_arch" in
        arm64) rust_targets+=("aarch64-apple-darwin") ;;
        x86_64) rust_targets+=("x86_64-apple-darwin") ;;
    esac
done

if [[ "${#app_archs[@]}" -eq 0 ]]; then
    echo "no app architectures requested" >&2
    exit 1
fi

join_by_space() {
    local joined=""
    for value in "$@"; do
        if [[ -z "$joined" ]]; then
            joined="$value"
        else
            joined="$joined $value"
        fi
    done
    printf '%s' "$joined"
}

if [[ "${SKIP_RUST_CORE_BUILD:-0}" != "1" ]]; then
    RUST_DARWIN_TARGETS="$(join_by_space "${rust_targets[@]}")" scripts/build-rust-core.sh
fi

built_executables=()
release_bin_dirs=()
for swift_triple in "${swift_triples[@]}"; do
    swift build -c release --product ClipDock --triple "$swift_triple"
    release_bin_dir="$(swift build -c release --triple "$swift_triple" --show-bin-path)"
    arch_executable_path="$release_bin_dir/ClipDock"

    if [[ ! -x "$arch_executable_path" ]]; then
        echo "release executable not found: $arch_executable_path" >&2
        exit 1
    fi

    built_executables+=("$arch_executable_path")
    release_bin_dirs+=("$release_bin_dir")
done

if [[ "${#built_executables[@]}" -eq 1 ]]; then
    executable_path="${built_executables[0]}"
else
    executable_path=".build/universal/$bundle_executable_name"
    mkdir -p "$(dirname "$executable_path")"
    rm -f "$executable_path"
    lipo -create "${built_executables[@]}" -output "$executable_path"
fi

rm -rf "$app_path"
mkdir -p "$macos_dir" "$resources_dir"
cp "$executable_path" "$macos_dir/$bundle_executable_name"
chmod 755 "$macos_dir/$bundle_executable_name"

if [[ -f "$app_icon_file" ]]; then
    cp "$app_icon_file" "$resources_dir/AppIcon.icns"
fi

if [[ -f "$status_icon_file" ]]; then
    cp "$status_icon_file" "$resources_dir/StatusBarClipboardTemplate.png"
fi

for release_bin_dir in "${release_bin_dirs[@]}"; do
    while IFS= read -r -d '' resource_bundle; do
        bundle_name="$(basename "$resource_bundle")"
        if [[ ! -d "$resources_dir/$bundle_name" ]]; then
            cp -R "$resource_bundle" "$resources_dir/$bundle_name"
        fi
    done < <(find "$release_bin_dir" -maxdepth 1 -type d -name 'ClipDock_*.bundle' -print0)
done

cat > "$contents_dir/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleDisplayName</key>
    <string>${display_name}</string>
    <key>CFBundleExecutable</key>
    <string>${bundle_executable_name}</string>
    <key>CFBundleIdentifier</key>
    <string>${bundle_identifier}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleName</key>
    <string>${display_name}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${app_version}</string>
    <key>CFBundleVersion</key>
    <string>${app_build}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

if [[ "${SKIP_CODESIGN:-0}" != "1" ]] && command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign "$codesign_identity" "$app_path" >/dev/null
fi

if command -v lipo >/dev/null 2>&1; then
    lipo "$macos_dir/$bundle_executable_name" -verify_arch "${app_archs[@]}"
fi

"$macos_dir/$bundle_executable_name" --print-ui-diagnostics >/dev/null

echo "Packaged app: $app_path"
