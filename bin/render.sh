#!/bin/sh

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"

if [ ! -s "$WEATHER_CACHE" ]; then notify_error "No weather data is available yet."; exit 1; fi
if ! FBINK=$(find_fbink); then notify_error "FBInk was not found."; exit 1; fi
if ! set_landscape; then notify_error "fbdepth could not switch the screen to landscape."; exit 1; fi

temp=$(round_number "$(current_value temperature_2m)")
feels=$(round_number "$(current_value apparent_temperature)")
wind=$(round_number "$(current_value wind_speed_10m)")
code=$(round_number "$(current_value weather_code)")
condition=$(weather_description "$code")
updated=$(current_text_value time | tr 'T' ' ')
unit=$(temperature_suffix)
wind_unit=$(wind_suffix)
today_high=$(round_number "$(daily_array_value temperature_2m_max 1)")
today_low=$(round_number "$(daily_array_value temperature_2m_min 1)")
today_rain=$(round_number "$(daily_array_value precipitation_probability_max 1)")

quote=""; author=""
if [ "$SHOW_QUOTE" = "1" ]; then
    if [ -s "$QUOTE_CACHE" ]; then
        quote=$(sed -n '1p' "$QUOTE_CACHE"); author=$(sed -n '2p' "$QUOTE_CACHE")
    elif [ -s "$EXTENSION_DIR/data/quotes.txt" ]; then
        day=$(date +%j | sed 's/^0*//'); [ -n "$day" ] || day=1
        count=$(wc -l < "$EXTENSION_DIR/data/quotes.txt" | tr -d ' ')
        quote_line=$(sed -n "$((day % count + 1))p" "$EXTENSION_DIR/data/quotes.txt")
        quote=${quote_line%%|*}; author=${quote_line#*|}
    fi
fi

header=$(date '+%A, %B %d')
icons="$EXTENSION_DIR/assets/icons"

draw_rule() { "$FBINK" -q -b -B BLACK --cls "top=$1,left=$2,width=$3,height=$4"; }
draw_icon() {
    icon_path="$icons/$(weather_icon_name "$1").png"
    [ -r "$icon_path" ] || return 1
    "$FBINK" -q -b --image "file=$icon_path,x=$2,y=$3,w=$4,h=$4" >/dev/null 2>&1
}
text_box() {
    text_px="$1"; text_top="$2"; text_bottom="$3"; text_left="$4"; text_right="$5"; text_style="$6"; shift 6
    "$FBINK" -q -b -m --truetype "regular=$FONT_REGULAR,bold=$FONT_BOLD,px=$text_px,top=$text_top,bottom=$text_bottom,left=$text_left,right=$text_right,style=$text_style" "$*"
}

render_truetype() {
    "$FBINK" -q -b --cls
    text_box 35 34 988 52 1040 BOLD "$LOCATION_NAME"
    text_box 29 41 992 1000 48 REGULAR "$header"
    draw_rule 101 52 1344 4

    draw_icon "$code" 72 154 185 || true
    text_box 126 130 742 260 730 BOLD "${temp} degrees"
    text_box 42 305 690 280 690 REGULAR "$condition"
    text_box 28 374 650 280 690 REGULAR "Feels ${feels} degrees  |  Wind ${wind} ${wind_unit}"

    draw_rule 137 795 4 302
    text_box 26 143 880 830 55 BOLD "TODAY"
    text_box 68 186 710 830 55 BOLD "${today_high} / ${today_low}"
    text_box 26 287 680 830 55 REGULAR "HIGH / LOW, degrees ${unit}"
    text_box 34 350 615 830 55 BOLD "${today_rain}% rain"

    draw_rule 469 52 1344 4
    text_box 27 491 520 52 1050 BOLD "NEXT SIX HOURS"
    i=1
    while [ "$i" -le "$HOURLY_FORECAST_COUNT" ]; do
        hour_time=$(hourly_array_value time "$i"); [ -n "$hour_time" ] || break
        hour_temp=$(round_number "$(hourly_array_value temperature_2m "$i")")
        hour_code=$(round_number "$(hourly_array_value weather_code "$i")")
        hour_rain=$(round_number "$(hourly_array_value precipitation_probability "$i")")
        left=$((52 + (i - 1) * 224)); right=$((1448 - left - 192)); icon_x=$((left + 56))
        text_box 25 545 482 "$left" "$right" BOLD "$(hour_label "$hour_time")"
        draw_icon "$hour_code" "$icon_x" 594 80 || true
        text_box 38 688 293 "$left" "$right" BOLD "${hour_temp} degrees"
        text_box 23 752 247 "$left" "$right" REGULAR "Rain ${hour_rain}%"
        [ "$i" -ge "$HOURLY_FORECAST_COUNT" ] || draw_rule 546 $((left + 208)) 2 257
        i=$((i + 1))
    done

    draw_rule 825 52 1344 4
    if [ -n "$quote" ]; then
        quote_block=$(printf '"%s"\n- %s' "$quote" "$author")
        "$FBINK" -q -b -m --truetype "regular=$FONT_REGULAR,bold=$FONT_BOLD,px=29,top=852,bottom=80,left=120,right=120" "$quote_block" || log_message "Quote rendering failed"
    fi
    text_box 21 1022 22 52 52 REGULAR "Updated $updated"
    "$FBINK" -q -f --refresh
}

render_bitmap() {
    "$FBINK" -q -b --cls
    "$FBINK" -q -b -m -S 3 -y 1 "$LOCATION_NAME  |  $header"
    "$FBINK" -q -b -m -S 6 -y 4 "${temp} ${unit}  $condition"
    "$FBINK" -q -b -m -S 2 -y 12 "Feels ${feels}  High ${today_high}  Low ${today_low}  Rain ${today_rain}%  Wind ${wind} ${wind_unit}"
    "$FBINK" -q -b -m -S 2 -y 18 "NEXT SIX HOURS"
    i=1
    while [ "$i" -le "$HOURLY_FORECAST_COUNT" ]; do
        hour_time=$(hourly_array_value time "$i"); [ -n "$hour_time" ] || break
        hour_temp=$(round_number "$(hourly_array_value temperature_2m "$i")")
        hour_code=$(round_number "$(hourly_array_value weather_code "$i")")
        hour_rain=$(round_number "$(hourly_array_value precipitation_probability "$i")")
        "$FBINK" -q -b -S 1 -x 2 -y $((21 + i * 3)) "$(hour_label "$hour_time")  ${hour_temp} ${unit}  $(weather_description "$hour_code")  Rain ${hour_rain}%"
        i=$((i + 1))
    done
    [ -z "$quote" ] || "$FBINK" -q -b -m -S 1 -y -7 "\"$quote\"  - $author"
    "$FBINK" -q -b -m -S 1 -y -2 "Updated $updated"
    "$FBINK" -q -f --refresh
}

if "$FBINK" --help 2>&1 | grep -q -- '--truetype' && [ -r "$FONT_REGULAR" ] && [ -r "$FONT_BOLD" ]; then
    render_truetype
else
    render_bitmap
fi
log_message "Landscape dashboard rendered"
