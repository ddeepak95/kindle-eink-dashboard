#!/bin/sh
# Local update controller. Remote releases never replace this file.
UPDATE_DIR="$CACHE_DIR/layout-updates"
mkdir -p "$UPDATE_DIR"
layout_files="render.sh quotes.txt icons/clear.png icons/cloudy.png icons/fog.png icons/partly-cloudy.png icons/rain.png icons/snow.png icons/storm.png"

acquire_update_lock() {
    lock_path="$UPDATE_DIR/$1.lock"
    if ! mkdir "$lock_path" 2>/dev/null; then
        owner=$(cat "$lock_path/pid" 2>/dev/null)
        # An owner may still be writing its PID immediately after mkdir.
        if [ -z "$owner" ]; then sleep 1; owner=$(cat "$lock_path/pid" 2>/dev/null); fi
        boot=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
        saved_boot=$(cat "$lock_path/boot" 2>/dev/null)
        case "$owner" in
            ''|*[!0-9]*) ;;
            *) if [ "$boot" = "$saved_boot" ] && kill -0 "$owner" 2>/dev/null; then return 1; fi ;;
        esac
        rm -f "$lock_path/pid" "$lock_path/boot"
        rmdir "$lock_path" 2>/dev/null || return 1
        mkdir "$lock_path" 2>/dev/null || return 1
    fi
    printf '%s\n' "$$" > "$lock_path/pid"
    cat /proc/sys/kernel/random/boot_id > "$lock_path/boot" 2>/dev/null || true
}
release_update_lock() {
    rm -f "$UPDATE_DIR/$1.lock/pid" "$UPDATE_DIR/$1.lock/boot"
    rmdir "$UPDATE_DIR/$1.lock" 2>/dev/null || true
}
valid_version() {
    case "$1" in ''|*[!0-9]*|0*) return 1;; esac
    [ "${#1}" -le 9 ]
}
read_version() {
    value=$(cat "$UPDATE_DIR/$1" 2>/dev/null) || return 1
    valid_version "$value" || return 1
    printf '%s' "$value"
}
write_version() {
    printf '%s\n' "$2" > "$UPDATE_DIR/$1.tmp" &&
        mv -f "$UPDATE_DIR/$1.tmp" "$UPDATE_DIR/$1"
}
download_layout_file() {
    curl -fsS --connect-timeout 10 --max-time "$NETWORK_TIMEOUT_SECONDS" "$1" -o "$2"
}
validate_layout() (
    cd "$1" || exit 1
    [ "$(wc -l < manifest.sha256 | tr -d ' ')" = "9" ] || exit 1
    for file in $layout_files; do
        hash=$(awk -v path="$file" '$2==path && NF==2 {print $1}' manifest.sha256)
        [ "${#hash}" = 64 ] || exit 1
        case "$hash" in *[!0-9a-f]*) exit 1;; esac
        [ -s "$file" ] || exit 1
        actual=$(sha256sum "$file") || exit 1
        [ "${actual%% *}" = "$hash" ] || exit 1
    done
    sh -n render.sh
)
check_layout_update() (
    [ "${AUTO_UPDATE_LAYOUT:-1}" = 1 ] || exit 0
    command -v curl >/dev/null 2>&1 || exit 0
    command -v sha256sum >/dev/null 2>&1 || { log_message "Layout updates need sha256sum"; exit 0; }
    acquire_update_lock check || exit 0
    stage="$UPDATE_DIR/staging.$$"
    trap 'rm -rf "$stage"; rm -f "$UPDATE_DIR/latest.tmp.$$"; release_update_lock check' 0
    trap 'exit 1' 1 2 15
    base="${LAYOUT_UPDATE_URL:-https://raw.githubusercontent.com/ddeepak95/kindle-eink-dashboard/main/updates}"
    case "$base" in https://*) ;; *) log_message "Layout update URL must use HTTPS"; exit 0;; esac
    if ! download_layout_file "$base/latest.txt" "$UPDATE_DIR/latest.tmp.$$"; then
        log_message "Layout update check unavailable; keeping local layout"; exit 0
    fi
    version=$(tr -d '\r\n' < "$UPDATE_DIR/latest.tmp.$$")
    valid_version "$version" || { log_message "Invalid layout version"; exit 0; }
    for pointer in active pending rejected; do
        [ "$(read_version "$pointer")" != "$version" ] || exit 0
    done
    mkdir -p "$stage/icons" || exit 1
    download_layout_file "$base/releases/$version/manifest.sha256" "$stage/manifest.sha256" || exit 0
    for file in $layout_files; do
        download_layout_file "$base/releases/$version/$file" "$stage/$file" || exit 0
    done
    if ! validate_layout "$stage"; then
        log_message "Layout $version failed validation; retaining current layout"; exit 0
    fi
    # Version directories are immutable; pointers are replaced atomically.
    if [ -d "$UPDATE_DIR/$version" ]; then
        validate_layout "$UPDATE_DIR/$version" || exit 0
    else
        mv "$stage" "$UPDATE_DIR/$version" || exit 1
    fi
    write_version pending "$version" || exit 1
    log_message "Layout $version downloaded; awaiting successful render"
)
run_layout() {
    # Bound a failed/hung renderer without depending on a particular timeout binary.
    sh "$SCRIPT_DIR/render-layout.sh" "$1" &
    render_pid=$!
    (
        sleep "${LAYOUT_RENDER_TIMEOUT_SECONDS:-45}" &
        timer_pid=$!
        trap 'kill "$timer_pid" 2>/dev/null; exit 0' 1 2 15
        wait "$timer_pid"
        kill "$render_pid" 2>/dev/null
    ) &
    watchdog_pid=$!
    wait "$render_pid"
    render_status=$?
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
    return "$render_status"
}
render_with_updates() {
    acquire_update_lock render || return 0
    trap 'release_update_lock render' 0
    trap 'exit 1' 1 2 15
    if [ "${AUTO_UPDATE_LAYOUT:-1}" = 1 ]; then
        active=$(read_version active) || active=""
        pending=$(read_version pending) || pending=""
        if [ -n "$pending" ]; then
            if validate_layout "$UPDATE_DIR/$pending" && run_layout "$UPDATE_DIR/$pending"; then
                if [ -n "$active" ]; then write_version previous "$active" || return 1; fi
                write_version active "$pending" || return 1
                rm -f "$UPDATE_DIR/pending"
                log_message "Layout $pending activated"
                return 0
            fi
            write_version rejected "$pending"
            rm -f "$UPDATE_DIR/pending"
            log_message "Layout $pending failed rendering; rolling back"
        fi
        if [ -n "$active" ]; then
            if validate_layout "$UPDATE_DIR/$active" && run_layout "$UPDATE_DIR/$active"; then return 0; fi
            write_version rejected "$active"
            rm -f "$UPDATE_DIR/active"
            previous=$(read_version previous) || previous=""
            if [ -n "$previous" ] && [ "$previous" != "$active" ] &&
                validate_layout "$UPDATE_DIR/$previous" && run_layout "$UPDATE_DIR/$previous"; then
                write_version active "$previous"
                log_message "Restored layout $previous"
                return 0
            fi
        fi
    fi
    run_layout "$EXTENSION_DIR/layout"
}