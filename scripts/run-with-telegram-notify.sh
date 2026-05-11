#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
project_name="$(basename "$repo_root")"
title="Task finished"
notify_on="${TELEGRAM_NOTIFY_ON:-always}"
log_lines="${TELEGRAM_NOTIFY_LOG_LINES:-20}"

usage() {
    cat <<'USAGE'
Usage: scripts/run-with-telegram-notify.sh [options] -- <command> [args...]

Options:
  --title TITLE         Title shown in the Telegram summary.
  --notify-on MODE      Notification policy: always, success, failure, never.
  --log-lines COUNT     Number of trailing log lines to include in the summary.
  --help                Show this help message.

The wrapped command keeps its original exit code. Notification failures are
reported to stderr but do not overwrite the wrapped command result.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --title)
            if [[ $# -lt 2 ]]; then
                echo "--title requires a value" >&2
                exit 1
            fi
            title="$2"
            shift 2
            ;;
        --notify-on)
            if [[ $# -lt 2 ]]; then
                echo "--notify-on requires a value" >&2
                exit 1
            fi
            notify_on="$2"
            shift 2
            ;;
        --log-lines)
            if [[ $# -lt 2 ]]; then
                echo "--log-lines requires a value" >&2
                exit 1
            fi
            log_lines="$2"
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

if [[ $# -eq 0 ]]; then
    echo "missing command to run" >&2
    usage >&2
    exit 1
fi

case "$notify_on" in
    always|success|failure|never) ;;
    *)
        echo "unsupported notify mode: $notify_on" >&2
        exit 1
        ;;
esac

if ! [[ "$log_lines" =~ ^[0-9]+$ ]] || (( log_lines < 0 )); then
    echo "--log-lines must be a non-negative integer" >&2
    exit 1
fi

log_file="$(mktemp)"
summary_file="$(mktemp)"
cleanup() {
    rm -f "$log_file" "$summary_file"
}
trap cleanup EXIT

command_cwd="$(pwd)"
started_at="$(date '+%Y-%m-%d %H:%M:%S %z')"
printf -v command_line '%q ' "$@"
command_line="${command_line% }"

set +e
"$@" 2>&1 | tee "$log_file"
exit_code=${PIPESTATUS[0]}
set -e

if (( exit_code == 0 )); then
    status_label="SUCCESS"
else
    status_label="FAILED (exit $exit_code)"
fi

should_notify=0
case "$notify_on" in
    always)
        should_notify=1
        ;;
    success)
        if (( exit_code == 0 )); then
            should_notify=1
        fi
        ;;
    failure)
        if (( exit_code != 0 )); then
            should_notify=1
        fi
        ;;
    never)
        should_notify=0
        ;;
esac

if (( should_notify == 1 )); then
    if [[ -s "$log_file" ]]; then
        recent_log="$(tail -n "$log_lines" "$log_file")"
    else
        recent_log="<no command output>"
    fi

    {
        printf '[%s] %s\n' "$project_name" "$title"
        printf 'Status: %s\n' "$status_label"
        printf 'Started: %s\n' "$started_at"
        printf 'Finished: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
        printf 'Directory: %s\n' "$command_cwd"
        printf 'Command: %s\n' "$command_line"
        printf '\nRecent log:\n%s\n' "$recent_log"
    } > "$summary_file"

    if ! "$repo_root/scripts/send-telegram-message.sh" --file "$summary_file"; then
        echo "Telegram notification failed" >&2
    fi
fi

exit "$exit_code"
