#!/usr/bin/env bash

release_metadata_path() {
    if [[ -n "${RELEASE_METADATA:-}" ]]; then
        printf '%s' "$RELEASE_METADATA"
        return
    fi

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    printf '%s' "$script_dir/../../version.properties"
}

app_info_plist_path() {
    printf '%s' "${APP_INFO_PLIST:-Sources/ClipDock/Resources/AppInfo.plist}"
}

read_release_property() {
    local key="$1"
    local metadata_path
    local value

    metadata_path="$(release_metadata_path)"

    if [[ -f "$metadata_path" ]]; then
        value="$(awk -v target="$key" '
            function trim(value) {
                gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", value)
                return value
            }

            /^[ \t]*(#|$)/ {
                next
            }

            {
                separator = index($0, "=")
                if (separator == 0) {
                    next
                }
                property_key = trim(substr($0, 1, separator - 1))
                property_value = trim(substr($0, separator + 1))
                if (property_key == target) {
                    print property_value
                    exit
                }
            }
        ' "$metadata_path")"
    else
        value=""
    fi

    printf '%s' "$value"
}

read_release_version() {
    local fallback="$1"
    local value

    value="$(read_release_property VERSION_NAME)"

    if [[ -n "$value" ]]; then
        printf '%s' "$value"
    else
        printf '%s' "$fallback"
    fi
}

read_release_build() {
    local fallback="$1"
    local value

    value="$(read_release_property VERSION_CODE)"

    if [[ -n "$value" ]]; then
        printf '%s' "$value"
    else
        printf '%s' "$fallback"
    fi
}

read_app_info_value() {
    local key="$1"
    local fallback="$2"
    local plist_path
    local value

    plist_path="$(app_info_plist_path)"

    if [[ -f "$plist_path" ]] && [[ -x /usr/libexec/PlistBuddy ]]; then
        value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist_path" 2>/dev/null || true)"
    else
        value=""
    fi

    if [[ -n "$value" ]]; then
        printf '%s' "$value"
    else
        printf '%s' "$fallback"
    fi
}
