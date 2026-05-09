#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

version="${APP_VERSION:-0.1.0}"
build="${APP_BUILD:-1}"
artifact_root="${RELEASE_DIR:-.codex/artifacts/release/$version}"
app_path="$artifact_root/PasteFloatingDemo.app"
zip_path="$artifact_root/PasteFloatingDemo-$version.zip"
dmg_path="$artifact_root/PasteFloatingDemo-$version.dmg"
checksums_path="$artifact_root/SHA256SUMS"
manifest_path="$artifact_root/release-manifest.txt"

case "$artifact_root" in
    /*) ;;
    *) artifact_root="$(pwd)/$artifact_root" ;;
esac

app_path="$artifact_root/PasteFloatingDemo.app"
zip_path="$artifact_root/PasteFloatingDemo-$version.zip"
dmg_path="$artifact_root/PasteFloatingDemo-$version.dmg"
checksums_path="$artifact_root/SHA256SUMS"
manifest_path="$artifact_root/release-manifest.txt"

mkdir -p "$artifact_root"

APP_VERSION="$version" APP_BUILD="$build" scripts/package-macos-app.sh "$app_path"

rm -f "$zip_path" "$dmg_path" "$checksums_path" "$manifest_path"

ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"

if command -v hdiutil >/dev/null 2>&1; then
    staging_dir="$artifact_root/dmg-staging"
    rm -rf "$staging_dir"
    mkdir -p "$staging_dir"
    cp -R "$app_path" "$staging_dir/"
    ln -s /Applications "$staging_dir/Applications"
    hdiutil create \
        -volname "Clipboard Workbench $version" \
        -srcfolder "$staging_dir" \
        -ov \
        -format UDZO \
        "$dmg_path" >/dev/null
    rm -rf "$staging_dir"
fi

if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
    if [[ "${CODESIGN_IDENTITY:-}" == "" || "${CODESIGN_IDENTITY:-}" == "-" ]]; then
        echo "notarization requires a Developer ID CODESIGN_IDENTITY" >&2
        exit 1
    fi
    if ! command -v xcrun >/dev/null 2>&1; then
        echo "xcrun not found; cannot notarize" >&2
        exit 1
    fi

    xcrun notarytool submit "$zip_path" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_SPECIFIC_PASSWORD" \
        --wait
    xcrun stapler staple "$app_path"
    rm -f "$zip_path"
    ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"

    if [[ -f "$dmg_path" ]]; then
        xcrun notarytool submit "$dmg_path" \
            --apple-id "$APPLE_ID" \
            --team-id "$APPLE_TEAM_ID" \
            --password "$APPLE_APP_SPECIFIC_PASSWORD" \
            --wait
        xcrun stapler staple "$dmg_path"
    fi
fi

(
    cd "$artifact_root"
    shasum -a 256 "PasteFloatingDemo.app/Contents/MacOS/PasteFloatingDemo" "PasteFloatingDemo-$version.zip" > "$checksums_path"
    if [[ -f "PasteFloatingDemo-$version.dmg" ]]; then
        shasum -a 256 "PasteFloatingDemo-$version.dmg" >> "$checksums_path"
    fi
)

{
    printf 'name=PasteFloatingDemo\n'
    printf 'version=%s\n' "$version"
    printf 'build=%s\n' "$build"
    printf 'bundle=%s\n' "$app_path"
    printf 'zip=%s\n' "$zip_path"
    if [[ -f "$dmg_path" ]]; then
        printf 'dmg=%s\n' "$dmg_path"
    else
        printf 'dmg=not-created\n'
    fi
    printf 'codesign_identity=%s\n' "${CODESIGN_IDENTITY:--}"
    if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
        printf 'notarization=submitted\n'
    else
        printf 'notarization=skipped\n'
    fi
} > "$manifest_path"

echo "Release artifacts: $artifact_root"
