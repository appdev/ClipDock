#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

version="${APP_VERSION:-0.1.0}"
build="${APP_BUILD:-1}"
app_bundle_name="${APP_BUNDLE_NAME:-ClipShelf}"
bundle_executable_name="${APP_EXECUTABLE_NAME:-ClipShelf}"
app_archs="${APP_ARCHS:-arm64 x86_64}"
create_dmg="${CREATE_DMG:-0}"
artifact_root="${RELEASE_DIR:-.codex/artifacts/release/$version}"
checksums_path="$artifact_root/SHA256SUMS"
manifest_path="$artifact_root/${app_bundle_name}-release-manifest.txt"

case "$artifact_root" in
    /*) ;;
    *) artifact_root="$(pwd)/$artifact_root" ;;
esac

checksums_path="$artifact_root/SHA256SUMS"
manifest_path="$artifact_root/${app_bundle_name}-release-manifest.txt"

mkdir -p "$artifact_root"

normalize_release_arch() {
    case "$1" in
        arm64|aarch64) printf 'arm64' ;;
        x64|x86_64) printf 'x86_64' ;;
        *)
            echo "unsupported release architecture: $1" >&2
            exit 1
            ;;
    esac
}

arch_inputs="${app_archs//,/ }"
release_archs=()

for arch_input in $arch_inputs; do
    arch="$(normalize_release_arch "$arch_input")"
    already_added=0
    if [[ "${#release_archs[@]}" -gt 0 ]]; then
        for existing_arch in "${release_archs[@]}"; do
            if [[ "$existing_arch" == "$arch" ]]; then
                already_added=1
                break
            fi
        done
    fi
    if [[ "$already_added" == "0" ]]; then
        release_archs+=("$arch")
    fi
done

if [[ "${#release_archs[@]}" -eq 0 ]]; then
    echo "no release architectures requested" >&2
    exit 1
fi

rm -f "$checksums_path" "$manifest_path"

: > "$checksums_path"

RUST_DARWIN_TARGETS="${release_archs[*]}" scripts/build-rust-core.sh

{
    printf 'name=%s\n' "$app_bundle_name"
    printf 'version=%s\n' "$version"
    printf 'build=%s\n' "$build"
    printf 'archs=%s\n' "${release_archs[*]}"
    printf 'create_dmg=%s\n' "$create_dmg"
    printf 'bundle_executable=%s\n' "$bundle_executable_name"
    printf 'codesign_identity=%s\n' "${CODESIGN_IDENTITY:--}"
    if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
        printf 'notarization=submitted\n'
    else
        printf 'notarization=skipped\n'
    fi
} > "$manifest_path"

for arch in "${release_archs[@]}"; do
    app_path="$artifact_root/${app_bundle_name}-$version-$arch.app"
    zip_path="$artifact_root/${app_bundle_name}-$version-$arch.zip"
    dmg_path="$artifact_root/${app_bundle_name}-$version-$arch.dmg"

    rm -rf "$app_path"
    rm -f "$zip_path" "$dmg_path"

    APP_VERSION="$version" APP_BUILD="$build" APP_BUNDLE_NAME="$app_bundle_name" APP_EXECUTABLE_NAME="$bundle_executable_name" APP_ARCHS="$arch" SKIP_RUST_CORE_BUILD=1 scripts/package-macos-app.sh "$app_path"

    ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"

    if [[ "$create_dmg" == "1" ]] && command -v hdiutil >/dev/null 2>&1; then
        staging_dir="$artifact_root/dmg-staging-$arch"
        rm -rf "$staging_dir"
        mkdir -p "$staging_dir"
        cp -R "$app_path" "$staging_dir/${app_bundle_name}.app"
        ln -s /Applications "$staging_dir/Applications"
        hdiutil create \
            -volname "ClipShelf $version $arch" \
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

        if [[ "$create_dmg" == "1" && -f "$dmg_path" ]]; then
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
        shasum -a 256 "${app_bundle_name}-$version-$arch.app/Contents/MacOS/${bundle_executable_name}" "${app_bundle_name}-$version-$arch.zip" >> "$checksums_path"
        if [[ "$create_dmg" == "1" && -f "${app_bundle_name}-$version-$arch.dmg" ]]; then
            shasum -a 256 "${app_bundle_name}-$version-$arch.dmg" >> "$checksums_path"
        fi
    )

    {
        printf '\n[%s]\n' "$arch"
        printf 'bundle=%s\n' "$app_path"
        printf 'zip=%s\n' "$zip_path"
        if [[ "$create_dmg" == "1" && -f "$dmg_path" ]]; then
            printf 'dmg=%s\n' "$dmg_path"
        else
            printf 'dmg=not-created\n'
        fi
    } >> "$manifest_path"
done

if [[ -f "$checksums_path" ]]; then
    sort -k 2 "$checksums_path" -o "$checksums_path"
fi

echo "Release artifacts: $artifact_root"
