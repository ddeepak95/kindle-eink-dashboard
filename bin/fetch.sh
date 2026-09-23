#!/bin/sh

# shellcheck source=common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"

force_refresh="${1:-0}"

if [ "$force_refresh" != "1" ] && cache_is_fresh; then
    log_message "Using fresh weather cache"
    exit 0
fi

if ! mkdir "$CACHE_DIR/.refresh.lock" 2>/dev/null; then
    log_message "Refresh already in progress"
    exit 0
fi

tmp_weather="$CACHE_DIR/weather.json.tmp.$$"
tmp_quote="$CACHE_DIR/quote.txt.tmp.$$"
wifi_started=0
cleanup() {
    if [ "$wifi_started" = "1" ]; then
        set_wifi 0
    fi
    rm -f "$tmp_weather" "$tmp_quote"
    rmdir "$CACHE_DIR/.refresh.lock" 2>/dev/null || true
}
trap cleanup 0 1 2 15

if [ "$MANAGE_WIFI" = "1" ]; then
    set_wifi 1
    wifi_started=1
    sleep "$WIFI_WAIT_SECONDS"
fi

api_url="https://api.open-meteo.com/v1/forecast?latitude=$LATITUDE&longitude=$LONGITUDE&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m&hourly=temperature_2m,weather_code,precipitation_probability&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max&temperature_unit=$TEMPERATURE_UNIT&wind_speed_unit=$WIND_SPEED_UNIT&precipitation_unit=$PRECIPITATION_UNIT&timezone=$TIMEZONE&forecast_days=$FORECAST_DAYS&forecast_hours=$((HOURLY_FORECAST_COUNT + 1))"

fetch_ok=0
if command -v curl >/dev/null 2>&1; then
    if curl -fsS --connect-timeout 15 --max-time "$NETWORK_TIMEOUT_SECONDS" \
        "$api_url" -o "$tmp_weather"; then
        if grep -q '"current"' "$tmp_weather" && grep -q '"hourly"' "$tmp_weather" && grep -q '"daily"' "$tmp_weather"; then
            mv "$tmp_weather" "$WEATHER_CACHE"
            date +%s > "$STAMP_FILE"
            fetch_ok=1
            log_message "Weather updated"
        fi
    fi
else
    log_message "curl is not installed"
fi

if [ -n "$QUOTE_URL" ] && command -v curl >/dev/null 2>&1; then
    if curl -fsS --connect-timeout 15 --max-time "$NETWORK_TIMEOUT_SECONDS" \
        "$QUOTE_URL" -o "$tmp_quote" && [ -s "$tmp_quote" ]; then
        mv "$tmp_quote" "$QUOTE_CACHE"
        log_message "Quote updated"
    fi
fi

# Reuse the current Wi-Fi session; offline/update failures never block weather.
. "$SCRIPT_DIR/updates.sh"
check_layout_update || log_message "Layout update check failed"

if [ "$fetch_ok" = "1" ]; then
    exit 0
fi

if [ -s "$WEATHER_CACHE" ]; then
    log_message "Weather request failed; using cached data"
    exit 0
fi

notify_error "Could not download weather, and no cached forecast exists."
exit 1
