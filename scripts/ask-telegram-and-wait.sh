#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
timeout_seconds="${TELEGRAM_WAIT_TIMEOUT:-600}"
poll_timeout_seconds="${TELEGRAM_POLL_TIMEOUT:-30}"
message_file=""

usage() {
    cat <<'USAGE'
Usage: scripts/ask-telegram-and-wait.sh [options] [message...]

Options:
  --file PATH             Read the outgoing message from a file.
  --timeout SECONDS       Total wait timeout for the reply. Default: 600.
  --poll-timeout SECONDS  Telegram long-poll timeout per request. Default: 30.
  --help                  Show this help message.

This script sends a Telegram message, waits for the user to reply to that exact
message, then prints the reply text to stdout.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --file)
            if [[ $# -lt 2 ]]; then
                echo "--file requires a path" >&2
                exit 1
            fi
            message_file="$2"
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

instruction_note=$'\n\n请直接回复这条消息，我会把你的回复继续传给当前任务。'
sent_message_id="$(
    "$repo_root/scripts/send-telegram-message.sh" \
        --print-message-id \
        "${message}${instruction_note}"
)"

"$repo_root/scripts/wait-for-telegram-reply.sh" \
    --reply-to "$sent_message_id" \
    --timeout "$timeout_seconds" \
    --poll-timeout "$poll_timeout_seconds"
