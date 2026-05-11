#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
env_file="${TELEGRAM_ENV_FILE:-$repo_root/.codex/telegram.env}"
api_base="${TELEGRAM_API_BASE:-https://api.telegram.org}"
max_length="${TELEGRAM_MAX_MESSAGE_LENGTH:-4000}"
dry_run="${TELEGRAM_DRY_RUN:-0}"
message_file=""
output_mode="status"

usage() {
    cat <<'USAGE'
Usage: scripts/send-telegram-message.sh [--dry-run] [--file PATH] [--print-message-id] [message...]

Sends a Telegram message with Bot API credentials from environment variables.
If .codex/telegram.env exists, it is loaded automatically before sending.
When no message arguments are provided, the script reads the message from stdin.
USAGE
}

if [[ -f "$env_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            dry_run=1
            shift
            ;;
        --file)
            if [[ $# -lt 2 ]]; then
                echo "--file requires a path" >&2
                exit 1
            fi
            message_file="$2"
            shift 2
            ;;
        --print-message-id)
            output_mode="message-id"
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
    esac
done

if [[ -n "$message_file" ]]; then
    if [[ ! -f "$message_file" ]]; then
        echo "message file not found: $message_file" >&2
        exit 1
    fi
    message="$(cat "$message_file")"
elif [[ $# -gt 0 ]]; then
    message="$*"
else
    message="$(cat)"
fi

if [[ -z "$message" ]]; then
    echo "message is empty" >&2
    exit 1
fi

if (( ${#message} > max_length )); then
    truncation_notice=$'\n\n[message truncated]'
    trim_length=$(( max_length - ${#truncation_notice} ))
    if (( trim_length < 0 )); then
        trim_length=0
    fi
    message="${message:0:trim_length}${truncation_notice}"
fi

if [[ "$dry_run" == "1" ]]; then
    if [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
        token_state="configured"
    else
        token_state="unset"
    fi

    cat <<EOF
Telegram dry run
API base: $api_base
Chat ID: ${TELEGRAM_CHAT_ID:-<unset>}
Bot token: $token_state
Message:
$message
EOF
    exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "curl is required to send Telegram messages" >&2
    exit 1
fi

: "${TELEGRAM_BOT_TOKEN:?Set TELEGRAM_BOT_TOKEN or create .codex/telegram.env}"
: "${TELEGRAM_CHAT_ID:?Set TELEGRAM_CHAT_ID or create .codex/telegram.env}"

response="$(
    curl -fsS -X POST \
    "$api_base/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${message}" \
    --data-urlencode "disable_web_page_preview=true" \
)"

message_id="$(
    RESPONSE="$response" python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["RESPONSE"])
if not payload.get("ok"):
    description = payload.get("description", "unknown Telegram API error")
    raise SystemExit(description)

message_id = payload.get("result", {}).get("message_id")
if message_id is None:
    raise SystemExit("Telegram API response did not include message_id")

print(message_id)
PY
)"

if [[ "$output_mode" == "message-id" ]]; then
    echo "$message_id"
else
    echo "Telegram message sent"
fi
