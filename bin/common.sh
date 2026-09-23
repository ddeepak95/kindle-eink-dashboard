#!/bin/sh

: "${SCRIPT_DIR:=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}"
EXTENSION_DIR=$(dirname "$SCRIPT_DIR")
CACHE_DIR="$EXTENSION_DIR/cache"
WEATHER_CACHE="$CACHE_DIR/weather.json"
QUOTE_CACHE="$CACHE_DIR/quote.txt"
STAMP_FILE="$CACHE_DIR/last_refresh"
LOG_FILE="$CACHE_DIR/dashboard.log"
ROTATION_FILE="$CACHE_DIR/original_rotation"

# shellcheck source=../config.sh
. "$EXTENSION_DIR/config.sh"

mkdir -p "$CACHE_DIR"

log_message() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

notify_error() {
    log_message "ERROR: $*"
    if command -v eips >/dev/null 2>&1; then
        eips -c >/dev/null 2>&1 || true
        eips 2 4 "Dashboard" >/dev/null 2>&1 || true
        eips 2 7 "$*" >/dev/null 2>&1 || true
    fi
}

find_fbink() {
    if [ -n "$FBINK_PATH" ] && [ -x "$FBINK_PATH" ]; then
        printf '%s\n' "$FBINK_PATH"
        return 0
    fi

    for candidate in \
        /mnt/us/extensions/FBInk/bin/FBInk \
        /mnt/us/extensions/FBInk/bin/fbink \
        /mnt/us/extensions/fbink/bin/fbink \
        /mnt/us/extensions/fbink/fbink
    do
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    if command -v fbink >/dev/null 2>&1; then
        command -v fbink
        return 0
    fi
    return 1
}

find_fbdepth() {
    if [ -n "$FBDEPTH_PATH" ] && [ -x "$FBDEPTH_PATH" ]; then
        printf '%s\n' "$FBDEPTH_PATH"
        return 0
    fi
    for candidate in \
        "$EXTENSION_DIR/bin/fbdepth" \
        /mnt/us/extensions/FBInk/bin/fbdepth \
        /mnt/us/extensions/fbink/bin/fbdepth \
        /mnt/us/libkh/bin/fbdepth
    do
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    command -v fbdepth 2>/dev/null || return 1
}

set_landscape() {
    FBDEPTH=$(find_fbdepth) || {
        log_message "fbdepth was not found; landscape mode is unavailable"
        return 1
    }
    if [ ! -s "$ROTATION_FILE" ]; then
        original=$($FBDEPTH -o 2>/dev/null)
        case "$original" in
            0|1|2|3) printf '%s\n' "$original" > "$ROTATION_FILE" ;;
            *) log_message "Could not read the original framebuffer rotation"; return 1 ;;
        esac
    fi
    original=$(sed -n '1p' "$ROTATION_FILE")
    case "$original" in
        0|1|2|3) landscape_rotation=$(((original + 1) % 4)) ;;
        *) log_message "Saved framebuffer rotation is invalid"; return 1 ;;
    esac
    if ! "$FBDEPTH" -q -r "$landscape_rotation" >/dev/null 2>&1; then
        log_message "Could not rotate framebuffer from $original to $landscape_rotation"
        return 1
    fi
    actual_rotation=$($FBDEPTH -o 2>/dev/null)
    log_message "Framebuffer rotation: native=$original landscape=$landscape_rotation actual=$actual_rotation"
}

restore_rotation() {
    [ -s "$ROTATION_FILE" ] || return 0
    FBDEPTH=$(find_fbdepth) || return 1
    original=$(sed -n '1p' "$ROTATION_FILE")
    case "$original" in
        0|1|2|3) "$FBDEPTH" -q -r "$original" >/dev/null 2>&1 || return 1 ;;
        *) return 1 ;;
    esac
    rm -f "$ROTATION_FILE"
}

set_wifi() {
    desired="$1"
    command -v lipc-set-prop >/dev/null 2>&1 || return 0
    lipc-set-prop -i com.lab126.cmd wirelessEnable "$desired" >/dev/null 2>&1 || \
        lipc-set-prop -i com.lab126.wifid enable "$desired" >/dev/null 2>&1 || true
}

set_prevent_sleep() {
    sleep_setting="$1"
    if ! command -v lipc-set-prop >/dev/null 2>&1; then
        log_message "lipc-set-prop is unavailable; cannot change sleep state"
        return 1
    fi

    if lipc-set-prop -i com.lab126.powerd preventScreenSaver "$sleep_setting" >/dev/null 2>&1; then
        log_message "preventScreenSaver set to $sleep_setting"
        return 0
    fi

    log_message "Could not set preventScreenSaver to $sleep_setting"
    return 1
}

cache_is_fresh() {
    [ -s "$WEATHER_CACHE" ] || return 1
    [ -s "$STAMP_FILE" ] || return 1

    now=$(date +%s)
    last=$(sed -n '1p' "$STAMP_FILE")
    case "$last" in
        *[!0-9]*|'') return 1 ;;
    esac
    [ $((now - last)) -lt "$MIN_REFRESH_SECONDS" ]
}

weather_description() {
    case "$1" in
        0) printf '%s' "Clear sky" ;;
        1) printf '%s' "Mostly clear" ;;
        2) printf '%s' "Partly cloudy" ;;
        3) printf '%s' "Overcast" ;;
        45|48) printf '%s' "Fog" ;;
        51|53|55) printf '%s' "Drizzle" ;;
        56|57) printf '%s' "Freezing drizzle" ;;
        61|63|65) printf '%s' "Rain" ;;
        66|67) printf '%s' "Freezing rain" ;;
        71|73|75|77) printf '%s' "Snow" ;;
        80|81|82) printf '%s' "Rain showers" ;;
        85|86) printf '%s' "Snow showers" ;;
        95) printf '%s' "Thunderstorms" ;;
        96|99) printf '%s' "Storms with hail" ;;
        *) printf '%s' "Conditions unavailable" ;;
    esac
}

current_value() {
    key="$1"
    sed -n "s/.*\"current\":{[^}]*\"$key\":\([-0-9.]*\).*/\1/p" "$WEATHER_CACHE" | head -n 1
}

current_text_value() {
    key="$1"
    sed -n "s/.*\"current\":{[^}]*\"$key\":\"\([^\"]*\)\".*/\1/p" "$WEATHER_CACHE" | head -n 1
}

array_value() {
    key="$1"
    position="$2"
    raw=$(sed -n "s/.*\"$key\":\[\([^]]*\)\].*/\1/p" "$WEATHER_CACHE" | head -n 1)
    printf '%s\n' "$raw" | awk -F, -v n="$position" '{gsub(/^ *"|" *$/, "", $n); print $n}'
}

object_array_value() {
    object="$1"
    key="$2"
    position="$3"
    section=$(sed -n "s/.*\"$object\":{\([^}]*\)}.*/\1/p" "$WEATHER_CACHE" | head -n 1)
    raw=$(printf '%s\n' "$section" | sed -n "s/.*\"$key\":\[\([^]]*\)\].*/\1/p")
    printf '%s\n' "$raw" | awk -F, -v n="$position" '{gsub(/^ *"|" *$/, "", $n); print $n}'
}

daily_array_value() {
    object_array_value daily "$1" "$2"
}

hourly_array_value() {
    object_array_value hourly "$1" "$2"
}

weather_icon_name() {
    case "$1" in
        0|1) printf '%s' clear ;;
        2) printf '%s' partly-cloudy ;;
        3) printf '%s' cloudy ;;
        45|48) printf '%s' fog ;;
        51|53|55|56|57|61|63|65|66|67|80|81|82) printf '%s' rain ;;
        71|73|75|77|85|86) printf '%s' snow ;;
        95|96|99) printf '%s' storm ;;
        *) printf '%s' cloudy ;;
    esac
}

hour_label() {
    hour=${1#*T}
    hour=${hour%%:*}
    case "$hour" in
        00) printf '%s' '12 AM' ;;
        0[1-9]) printf '%s AM' "${hour#0}" ;;
        10|11) printf '%s AM' "$hour" ;;
        12) printf '%s' '12 PM' ;;
        13) printf '%s' '1 PM' ;;
        14) printf '%s' '2 PM' ;;
        15) printf '%s' '3 PM' ;;
        16) printf '%s' '4 PM' ;;
        17) printf '%s' '5 PM' ;;
        18) printf '%s' '6 PM' ;;
        19) printf '%s' '7 PM' ;;
        20) printf '%s' '8 PM' ;;
        21) printf '%s' '9 PM' ;;
        22) printf '%s' '10 PM' ;;
        23) printf '%s' '11 PM' ;;
        *) printf '%s' "$hour" ;;
    esac
}

round_number() {
    value="$1"
    awk -v n="$value" 'BEGIN { if (n == "") print "--"; else printf "%.0f", n }'
}

temperature_suffix() {
    if [ "$TEMPERATURE_UNIT" = "celsius" ]; then
        printf '%s' "C"
    else
        printf '%s' "F"
    fi
}

wind_suffix() {
    case "$WIND_SPEED_UNIT" in
        kmh) printf '%s' "km/h" ;;
        ms) printf '%s' "m/s" ;;
        kn) printf '%s' "kn" ;;
        *) printf '%s' "mph" ;;
    esac
}
