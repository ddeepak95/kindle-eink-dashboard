#!/bin/sh

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

ENABLED_FILE="$CACHE_DIR/dashboard.enabled"
PID_FILE="$CACHE_DIR/dashboard.pid"

if [ -n "${1:-}" ]; then
    case "$1" in
        *[!0-9]*|'') notify_error "Refresh interval must be a number of seconds."; exit 1 ;;
    esac
    if [ "$1" -lt 300 ]; then
        notify_error "Refresh interval must be at least 300 seconds."
        exit 1
    fi
    DASHBOARD_INTERVAL_OVERRIDE="$1"
    export DASHBOARD_INTERVAL_OVERRIDE
fi

if [ -s "$PID_FILE" ]; then
    old_pid=$(sed -n '1p' "$PID_FILE")
    case "$old_pid" in
        *[!0-9]*|'') old_pid="" ;;
    esac
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
        log_message "Dashboard daemon is already running as PID $old_pid"
        exit 0
    fi
fi

touch "$ENABLED_FILE"

if command -v nohup >/dev/null 2>&1; then
    nohup "$SCRIPT_DIR/daemon.sh" >> "$LOG_FILE" 2>&1 &
else
    "$SCRIPT_DIR/daemon.sh" >> "$LOG_FILE" 2>&1 &
fi

daemon_pid=$!
printf '%s\n' "$daemon_pid" > "$PID_FILE"
log_message "Started low-power dashboard as PID $daemon_pid (interval ${DASHBOARD_INTERVAL_OVERRIDE:-$REFRESH_INTERVAL_SECONDS}s)"
exit 0
