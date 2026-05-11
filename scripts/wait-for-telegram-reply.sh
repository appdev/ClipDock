#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
env_file="${TELEGRAM_ENV_FILE:-$repo_root/.codex/telegram.env}"
api_base="${TELEGRAM_API_BASE:-https://api.telegram.org}"
timeout_seconds="${TELEGRAM_WAIT_TIMEOUT:-600}"
poll_timeout_seconds="${TELEGRAM_POLL_TIMEOUT:-30}"
reply_to_message_id=""
started_at_epoch="$(date +%s)"

usage() {
    cat <<'USAGE'
Usage: scripts/wait-for-telegram-reply.sh --reply-to MESSAGE_ID [options]

Options:
  --reply-to MESSAGE_ID    Wait for a reply to this bot message ID.
  --timeout SECONDS        Total wait timeout. Default: 600.
  --poll-timeout SECONDS   Telegram long-poll timeout per request. Default: 30.
  --help                   Show this help message.

The script prints the reply text to stdout and exits 0 when a matching reply
arrives. It exits non-zero on timeout or API errors.
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
        --reply-to)
            if [[ $# -lt 2 ]]; then
                echo "--reply-to requires a value" >&2
                exit 1
            fi
            reply_to_message_id="$2"
            shift 2
            ;;
        --timeout)
            if [[ $# -lt 2 ]]; then
                echo "--timeout requires a value" >&2
                exit 1
            fi
            timeout_seconds="$2"
            shift 2
            ;;
        --poll-timeout)
            if [[ $# -lt 2 ]]; then
                echo "--poll-timeout requires a value" >&2
                exit 1
            fi
            poll_timeout_seconds="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "unsupported option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ -z "$reply_to_message_id" ]]; then
    echo "--reply-to is required" >&2
    usage >&2
    exit 1
fi

if ! [[ "$timeout_seconds" =~ ^[0-9]+$ ]] || (( timeout_seconds <= 0 )); then
    echo "--timeout must be a positive integer" >&2
    exit 1
fi

if ! [[ "$poll_timeout_seconds" =~ ^[0-9]+$ ]] || (( poll_timeout_seconds <= 0 )); then
    echo "--poll-timeout must be a positive integer" >&2
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "curl is required to read Telegram replies" >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required to parse Telegram replies" >&2
    exit 1
fi

: "${TELEGRAM_BOT_TOKEN:?Set TELEGRAM_BOT_TOKEN or create .codex/telegram.env}"
: "${TELEGRAM_CHAT_ID:?Set TELEGRAM_CHAT_ID or create .codex/telegram.env}"

offset=""

while true; do
    now_epoch="$(date +%s)"
    elapsed=$(( now_epoch - started_at_epoch ))
    remaining=$(( timeout_seconds - elapsed ))
    if (( remaining <= 0 )); then
        echo "timed out waiting for Telegram reply to message ${reply_to_message_id}" >&2
        exit 1
    fi

    effective_poll_timeout="$poll_timeout_seconds"
    if (( remaining < effective_poll_timeout )); then
        effective_poll_timeout="$remaining"
    fi

    updates="$(
        if [[ -n "$offset" ]]; then
            curl -fsS -X POST \
                "$api_base/bot${TELEGRAM_BOT_TOKEN}/getUpdates" \
                --data-urlencode "offset=${offset}" \
                --data-urlencode "timeout=${effective_poll_timeout}" \
                --data-urlencode 'allowed_updates=["message"]'
        else
            curl -fsS -X POST \
                "$api_base/bot${TELEGRAM_BOT_TOKEN}/getUpdates" \
                --data-urlencode "timeout=${effective_poll_timeout}" \
                --data-urlencode 'allowed_updates=["message"]'
        fi
    )"

    parse_result="$(
        RESPONSE="$updates" \
        TARGET_CHAT_ID="${TELEGRAM_CHAT_ID}" \
        TARGET_REPLY_TO="${reply_to_message_id}" \
        STARTED_AT="${started_at_epoch}" \
        python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["RESPONSE"])
if not payload.get("ok"):
    description = payload.get("description", "unknown Telegram API error")
    raise SystemExit(description)

target_chat_id = str(os.environ["TARGET_CHAT_ID"])
target_reply_to = int(os.environ["TARGET_REPLY_TO"])
started_at = int(os.environ["STARTED_AT"])

updates = payload.get("result", [])
max_update_id = None
matched_text = None

for item in updates:
    update_id = item.get("update_id")
    if update_id is not None:
        if max_update_id is None or update_id > max_update_id:
            max_update_id = update_id

    message = item.get("message")
    if not isinstance(message, dict):
        continue

    chat = message.get("chat", {})
    if str(chat.get("id")) != target_chat_id:
        continue

    if int(message.get("date", 0)) < started_at:
        continue

    reply_to = message.get("reply_to_message", {})
    if reply_to.get("message_id") != target_reply_to:
        continue

    text = message.get("text") or message.get("caption")
    if not text:
        continue

    matched_text = text
    break

if max_update_id is None:
    print("OFFSET=")
else:
    print(f"OFFSET={max_update_id + 1}")

print("MATCH<<'EOF'")
if matched_text is not None:
    print(matched_text)
print("EOF")
PY
    )"

    offset="$(printf '%s\n' "$parse_result" | sed -n 's/^OFFSET=//p' | head -n 1)"
    reply_text="$(printf '%s\n' "$parse_result" | sed -n "/^MATCH<<'EOF'$/,/^EOF$/p" | sed '1d;$d')"

    if [[ -n "$reply_text" ]]; then
        printf '%s\n' "$reply_text"
        exit 0
    fi
done
