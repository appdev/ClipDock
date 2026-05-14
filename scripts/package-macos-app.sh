#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

export MACOSX_DEPLOYMENT_TARGET=13.0
export CLANG_MODULE_CACHE_PATH="$(pwd)/.build/clang-module-cache"

mkdir -p "$CLANG_MODULE_CACHE_PATH"

app_bundle_name="${APP_BUNDLE_NAME:-ClipShelf}"
bundle_executable_name="${APP_EXECUTABLE_NAME:-ClipShelf}"

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
bundle_identifier="${BUNDLE_IDENTIFIER:-com.apkdv.clipshelf}"
display_name="${APP_DISPLAY_NAME:-ClipShelf}"
app_version="${APP_VERSION:-0.1.0}"
app_build="${APP_BUILD:-1}"
codesign_identity="${CODESIGN_IDENTITY:--}"
app_icon_file="${APP_ICON_FILE:-Sources/ClipShelf/Resources/AppIcon.icns}"
status_icon_file="${STATUS_ICON_FILE:-Sources/ClipShelf/Resources/StatusBarClipboardTemplate.png}"

scripts/build-rust-core.sh
swift build -c release --product ClipShelf

release_bin_dir="$(swift build -c release --show-bin-path)"
executable_path="$release_bin_dir/ClipShelf"

if [[ ! -x "$executable_path" ]]; then
    echo "release executable not found: $executable_path" >&2
    exit 1
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
    <string>${app_name}</string>
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
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

if [[ "${SKIP_CODESIGN:-0}" != "1" ]] && command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign "$codesign_identity" "$app_path" >/dev/null
fi

"$macos_dir/$bundle_executable_name" --print-ui-diagnostics >/dev/null

echo "Packaged app: $app_path"
