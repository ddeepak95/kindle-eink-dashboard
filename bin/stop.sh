#!/bin/sh

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

ENABLED_FILE="$CACHE_DIR/dashboard.enabled"
PID_FILE="$CACHE_DIR/dashboard.pid"

rm -f "$ENABLED_FILE"

if [ -s "$PID_FILE" ]; then
    daemon_pid=$(sed -n '1p' "$PID_FILE")
    case "$daemon_pid" in
        *[!0-9]*|'') daemon_pid="" ;;
    esac
    if [ -n "$daemon_pid" ] && kill -0 "$daemon_pid" 2>/dev/null; then
        kill "$daemon_pid" 2>/dev/null || true
    fi
fi

rm -f "$PID_FILE" "$CACHE_DIR/next_wake"
set_prevent_sleep 0 || true
restore_rotation || log_message "Could not restore framebuffer rotation"

if command -v initctl >/dev/null 2>&1; then
    initctl start framework >/dev/null 2>&1 || \
        initctl start lab126_gui >/dev/null 2>&1 || true
fi

log_message "Dashboard stopped; native UI requested"
