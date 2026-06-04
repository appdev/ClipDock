#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

binary_name="clipdock-sync-server"
profile="release"
target=""
version=""
output_dir=""
skip_build=0

usage() {
    cat <<'USAGE'
Usage: scripts/package-server.sh [options]

Options:
  --target <rust-target>    Rust target triple. Defaults to the host target.
  --version <version>      Release version. Defaults to root version.properties.
  --output-dir <dir>       Output directory. Defaults to .codex/artifacts/server/<version>.
  --profile <profile>      Cargo profile to build. Defaults to release.
  --skip-build             Package an already-built binary.
  -h, --help               Show this help.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)
            target="${2:?missing value for --target}"
            shift 2
            ;;
        --version)
            version="${2:?missing value for --version}"
            shift 2
            ;;
        --output-dir)
            output_dir="${2:?missing value for --output-dir}"
            shift 2
            ;;
        --profile)
            profile="${2:?missing value for --profile}"
            shift 2
            ;;
        --skip-build)
            skip_build=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

find_python() {
    if [[ -n "${PYTHON:-}" ]]; then
        printf '%s' "$PYTHON"
        return
    fi
    if command -v python3 >/dev/null 2>&1; then
        command -v python3
        return
    fi
    if command -v python >/dev/null 2>&1; then
        command -v python
        return
    fi
    echo "python3 or python is required" >&2
    exit 1
}

python_bin="$(find_python)"

if [[ -z "$target" ]]; then
    target="$(rustc -vV | awk '/^host:/ { print $2 }')"
fi

if [[ -z "$target" ]]; then
    echo "could not resolve Rust target triple" >&2
    exit 1
fi

if [[ -z "$version" ]]; then
    version="$("$python_bin" - <<'PY'
from pathlib import Path

metadata_path = Path("../version.properties")
fallback = "0.1.0"
if not metadata_path.exists():
    print(fallback)
    raise SystemExit

properties = {}
for raw_line in metadata_path.read_text(encoding="utf-8").splitlines():
    line = raw_line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    key, value = line.split("=", 1)
    properties[key.strip()] = value.strip()

print(properties.get("VERSION_NAME") or fallback)
PY
)"
fi

if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
    echo "version must be numeric, such as 0.1.7" >&2
    exit 1
fi

platform_label=""
archive_ext="tar.gz"
exe_suffix=""

case "$target" in
    x86_64-unknown-linux-gnu)
        platform_label="linux-x86_64"
        ;;
    aarch64-unknown-linux-gnu)
        platform_label="linux-arm64"
        ;;
    x86_64-apple-darwin)
        platform_label="macos-x86_64"
        ;;
    aarch64-apple-darwin)
        platform_label="macos-arm64"
        ;;
    x86_64-pc-windows-msvc)
        platform_label="windows-x86_64"
        archive_ext="zip"
        exe_suffix=".exe"
        ;;
    aarch64-pc-windows-msvc)
        platform_label="windows-arm64"
        archive_ext="zip"
        exe_suffix=".exe"
        ;;
    *)
        echo "unsupported target: $target" >&2
        exit 1
        ;;
esac

if [[ -z "$output_dir" ]]; then
    output_dir=".codex/artifacts/server/$version"
fi

case "$output_dir" in
    /*|[A-Za-z]:/*|[A-Za-z]:\\*) ;;
    *) output_dir="$(pwd)/$output_dir" ;;
esac

if [[ "$skip_build" != "1" ]]; then
    cargo build --locked --profile "$profile" --target "$target"
fi

profile_dir="$profile"
if [[ "$profile" == "dev" ]]; then
    profile_dir="debug"
fi

binary_path="target/$target/$profile_dir/$binary_name$exe_suffix"
if [[ ! -f "$binary_path" ]]; then
    echo "server binary not found: $binary_path" >&2
    exit 1
fi

package_name="ClipDock-Server-$version-$platform_label"
staging_root="$output_dir/.staging"
staging_dir="$staging_root/$package_name"
archive_path="$output_dir/$package_name.$archive_ext"
checksum_path="$archive_path.sha256"
manifest_path="$output_dir/$package_name.manifest.txt"

rm -rf "$staging_dir"
mkdir -p "$staging_dir/docs" "$output_dir"

cp "$binary_path" "$staging_dir/$binary_name$exe_suffix"
cp README.md "$staging_dir/README.md"
cp docs/protocol-v2.md "$staging_dir/docs/protocol-v2.md"

cat > "$staging_dir/$package_name.manifest.txt" <<MANIFEST
name=ClipDock Sync Server
package=$package_name
version=$version
target=$target
platform=$platform_label
profile=$profile
binary=$binary_name$exe_suffix
archive_format=$archive_ext
MANIFEST

cp "$staging_dir/$package_name.manifest.txt" "$manifest_path"

rm -f "$archive_path" "$checksum_path"

"$python_bin" - "$staging_dir" "$archive_path" "$archive_ext" "$package_name" <<'PY'
import sys
import tarfile
import zipfile
from pathlib import Path

staging_dir = Path(sys.argv[1])
archive_path = Path(sys.argv[2])
archive_ext = sys.argv[3]
package_name = sys.argv[4]

files = [path for path in sorted(staging_dir.rglob("*")) if path.is_file()]

if archive_ext == "zip":
    with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in files:
            archive.write(path, Path(package_name) / path.relative_to(staging_dir))
elif archive_ext == "tar.gz":
    with tarfile.open(archive_path, "w:gz") as archive:
        for path in files:
            archive.add(path, arcname=Path(package_name) / path.relative_to(staging_dir))
else:
    raise SystemExit(f"unsupported archive extension: {archive_ext}")
PY

"$python_bin" - "$archive_path" "$checksum_path" <<'PY'
import hashlib
import sys
from pathlib import Path

archive_path = Path(sys.argv[1])
checksum_path = Path(sys.argv[2])
digest = hashlib.sha256(archive_path.read_bytes()).hexdigest()
checksum_path.write_text(f"{digest}  {archive_path.name}\n", encoding="utf-8")
PY

rm -rf "$staging_root"

echo "Packaged server: $archive_path"
echo "Checksum: $checksum_path"
echo "Manifest: $manifest_path"
