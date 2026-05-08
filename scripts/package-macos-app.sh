#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

export MACOSX_DEPLOYMENT_TARGET=13.0
export CLANG_MODULE_CACHE_PATH="$(pwd)/.build/clang-module-cache"

mkdir -p "$CLANG_MODULE_CACHE_PATH"

app_path="${1:-.codex/artifacts/PasteFloatingDemo.app}"
if [[ "$app_path" != *.app ]]; then
    app_path="$app_path/PasteFloatingDemo.app"
fi

case "$app_path" in
    /*) ;;
    *) app_path="$(pwd)/$app_path" ;;
esac

app_name="$(basename "$app_path" .app)"
contents_dir="$app_path/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"

scripts/build-rust-core.sh
swift build -c release --product PasteFloatingDemo

release_bin_dir="$(swift build -c release --show-bin-path)"
executable_path="$release_bin_dir/PasteFloatingDemo"

if [[ ! -x "$executable_path" ]]; then
    echo "release executable not found: $executable_path" >&2
    exit 1
fi

rm -rf "$app_path"
mkdir -p "$macos_dir" "$resources_dir"
cp "$executable_path" "$macos_dir/PasteFloatingDemo"
chmod 755 "$macos_dir/PasteFloatingDemo"

cat > "$contents_dir/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleDisplayName</key>
    <string>剪贴板工作台</string>
    <key>CFBundleExecutable</key>
    <string>PasteFloatingDemo</string>
    <key>CFBundleIdentifier</key>
    <string>dev.codex.clipboard-workbench-demo</string>
    <key>CFBundleName</key>
    <string>${app_name}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$app_path" >/dev/null
fi

"$macos_dir/PasteFloatingDemo" --print-ui-diagnostics >/dev/null

echo "Packaged app: $app_path"
