#!/usr/bin/env bash

app_info_plist_path() {
    printf '%s' "${APP_INFO_PLIST:-Sources/ClipDock/Resources/AppInfo.plist}"
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
