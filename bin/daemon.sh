#!/bin/sh

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

ENABLED_FILE="$CACHE_DIR/dashboard.enabled"
PID_FILE="$CACHE_DIR/dashboard.pid"
NEXT_WAKE_FILE="$CACHE_DIR/next_wake"
EFFECTIVE_INTERVAL="${DASHBOARD_INTERVAL_OVERRIDE:-$REFRESH_INTERVAL_SECONDS}"

validate_interval() {
    case "$EFFECTIVE_INTERVAL" in
        *[!0-9]*|'') return 1 ;;
    esac
    [ "$EFFECTIVE_INTERVAL" -ge 300 ]
}

stop_native_ui() {
    command -v initctl >/dev/null 2>&1 || return 1

    # Stopping the framework prevents its blanket/screensaver renderer from
    # replacing the dashboard immediately before suspend.
    initctl stop framework >/dev/null 2>&1 || \
        initctl stop lab126_gui >/dev/null 2>&1 || return 1
    log_message "Native UI stopped for dashboard mode"
}

start_native_ui() {
    command -v initctl >/dev/null 2>&1 || return 0
    initctl start framework >/dev/null 2>&1 || \
        initctl start lab126_gui >/dev/null 2>&1 || true
    log_message "Native UI start requested"
}

arm_rtc() {
    seconds="$1"
    target="$2"

    if [ -w /sys/devices/platform/mxc_rtc.0/wakeup_enable ]; then
        printf '%s' "$seconds" > /sys/devices/platform/mxc_rtc.0/wakeup_enable && return 0
    fi

    if command -v rtcwake >/dev/null 2>&1; then
        for rtc_device in /dev/rtc1 /dev/rtc0; do
            if [ -e "$rtc_device" ] && rtcwake -d "$rtc_device" -m no -s "$seconds" >/dev/null 2>&1; then
                return 0
            fi
        done
    fi

    for alarm in /sys/class/rtc/rtc1/wakealarm /sys/class/rtc/rtc0/wakealarm; do
        if [ -w "$alarm" ]; then
            printf '0\n' > "$alarm" 2>/dev/null || true
            if printf '%s\n' "$target" > "$alarm" 2>/dev/null; then
                return 0
            fi
        fi
    done

    return 1
}

suspend_until_next_cycle() {
    now=$(date +%s)
    target=$((now + EFFECTIVE_INTERVAL))
    printf '%s\n' "$target" > "$NEXT_WAKE_FILE"

    if ! arm_rtc "$EFFECTIVE_INTERVAL" "$target"; then
        log_message "No working RTC wake interface was found"
        return 1
    fi

    if [ ! -w /sys/power/state ]; then
        log_message "/sys/power/state is not writable"
        return 1
    fi

    log_message "Suspending until approximately $target"
    sync
    sleep 3
    printf 'mem\n' > /sys/power/state
    log_message "Resumed from suspend"

    # An RTC wake should occur close to the armed target. A substantially early
    # wake is normally the power button, so treat it as the user's exit action.
    resumed_at=$(date +%s)
    early_cutoff=$((target - 90))
    if [ "$resumed_at" -lt "$early_cutoff" ]; then
        log_message "Early wake detected; leaving dashboard mode"
        return 1
    fi
    return 0
}

cleanup_daemon() {
    trap - 0 1 2 15
    rm -f "$ENABLED_FILE" "$PID_FILE" "$NEXT_WAKE_FILE"
    set_prevent_sleep 0 || true
    restore_rotation || log_message "Could not restore framebuffer rotation"
    start_native_ui
    log_message "Low-power dashboard daemon exited"
}

if ! validate_interval; then
    notify_error "The refresh interval must be at least 300 seconds."
    exit 1
fi

trap '' 15
if ! set_prevent_sleep 1; then
    notify_error "Could not reserve the display for dashboard mode."
    exit 1
fi
if ! stop_native_ui; then
    set_prevent_sleep 0 || true
    notify_error "Could not pause the native Kindle interface."
    exit 1
fi
if ! set_landscape; then
    set_prevent_sleep 0 || true
    start_native_ui
    notify_error "Could not switch the display to landscape."
    exit 1
fi
trap cleanup_daemon 0 1 2 15

while [ -f "$ENABLED_FILE" ]; do
    if "$SCRIPT_DIR/fetch.sh" 1; then
        "$SCRIPT_DIR/render.sh" || break
    elif [ -s "$WEATHER_CACHE" ]; then
        "$SCRIPT_DIR/render.sh" || break
    else
        break
    fi

    [ -f "$ENABLED_FILE" ] || break
    suspend_until_next_cycle || break
    sleep "$WAKE_SETTLE_SECONDS"
done

exit 0
