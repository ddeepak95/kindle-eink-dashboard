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
    quote_source="$EXTENSION_DIR/data/quotes.txt"
    if [ -n "$QUOTE_URL" ] && [ -s "$QUOTE_CACHE" ]; then quote_source="$QUOTE_CACHE"; fi
    if [ -s "$quote_source" ]; then
        selected=$(select_quote "$quote_source")
        quote=$(printf '%s\n' "$selected" | sed -n '1p')
        author=$(printf '%s\n' "$selected" | sed -n '2p')
    fi
fi

groups=$(forecast_groups)
group_count=$(printf '%s\n' "$groups" | awk 'NF {n++} END {print n+0}')
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
    text_box 41 34 988 52 1040 BOLD "$LOCATION_NAME"
    text_box 33 41 980 800 48 REGULAR "$header"
    draw_rule 101 52 1344 4

    draw_icon "$code" 72 154 185 || true
    text_box 145 130 742 260 730 BOLD "${temp}°"
    text_box 46 305 690 280 690 REGULAR "$condition"
    text_box 32 371 600 280 690 REGULAR "Feels ${feels}° | Wind ${wind} ${wind_unit}"

    draw_rule 137 795 4 302
    text_box 32 143 880 830 55 BOLD "TODAY"
    text_box 77 186 710 830 55 BOLD "${today_high} / ${today_low}"
    text_box 29 287 680 830 55 REGULAR "HIGH / LOW, degrees ${unit}"
    text_box 40 350 615 830 55 BOLD "${today_rain}% rain"

    draw_rule 469 52 1344 4
    text_box 32 488 530 52 700 BOLD "NEXT $HOURLY_FORECAST_COUNT HOURS"
    i=0
    if [ "$group_count" -gt 0 ]; then
        printf '%s\n' "$groups" | while IFS='|' read -r first last low high hour_code hour_rain; do
            columns=$group_count
            [ "$group_count" -le 6 ] || columns=$(((group_count + 1) / 2))
            width=$((1344 / columns))
            if [ "$group_count" -gt 6 ]; then
                left=$((52 + (i % columns) * width)); right=$((1448 - left - width + 20))
                top=$((539 + (i / columns) * 140))
                text_box 29 "$top" $((1072 - top - 38)) "$left" "$right" BOLD "$(period_label "$first" "$last")"
                draw_icon "$hour_code" "$left" $((top + 38)) 40 || true
                temperatures="$low"; [ "$low" = "$high" ] || temperatures="$low-$high"
                text_box 32 $((top + 38)) $((1072 - top - 78)) $((left + 46)) "$right" BOLD "$temperatures"
                text_box 23 $((top + 78)) $((1072 - top - 108)) "$left" "$right" BOLD "$(weather_description "$hour_code")"
                text_box 24 $((top + 108)) $((1072 - top - 140)) "$left" "$right" REGULAR "Rain $hour_rain%"
                [ "$hour_code" -lt 51 ] || draw_rule $((top + 137)) "$left" $((width - 20)) 3
                i=$((i + 1))
                continue
            fi
            left=$((52 + i * width)); right=$((1448 - left - width + 20)); icon_x=$((left + width / 2 - 40))
            text_box 29 539 481 "$left" "$right" BOLD "$(period_label "$first" "$last")"
            draw_icon "$hour_code" "$icon_x" 584 80 || true
            temperatures="$low"; [ "$low" = "$high" ] || temperatures="$low-$high"
            text_box 40 674 337 "$left" "$right" BOLD "$temperatures"
            text_box 25 732 274 "$left" "$right" BOLD "$(weather_description "$hour_code")"
            text_box 27 783 239 "$left" "$right" REGULAR "Rain $hour_rain%"
            # Thick underline calls attention to rain, snow and storms on e-ink.
            [ "$hour_code" -lt 51 ] || draw_rule 818 "$left" $((width - 20)) 5
            i=$((i + 1))
            [ "$i" -ge "$group_count" ] || draw_rule 546 $((left + width - 10)) 2 257
        done
    fi
    draw_rule 825 52 1344 4
    if [ -n "$quote" ]; then
        quote_block=$(printf '"%s"\n- %s' "$quote" "$author")
        "$FBINK" -q -b -m --truetype "regular=$FONT_REGULAR,bold=$FONT_BOLD,px=35,top=845,bottom=65,left=85,right=85" "$quote_block" || log_message "Quote rendering failed"
    fi
    text_box 25 1022 12 52 52 REGULAR "Updated $updated"
    "$FBINK" -q -f --refresh
}

render_bitmap() {
    "$FBINK" -q -b --cls
    "$FBINK" -q -b -m -S 3 -y 1 "$LOCATION_NAME  |  $header"
    "$FBINK" -q -b -m -S 6 -y 4 "${temp} ${unit}  $condition"
    "$FBINK" -q -b -m -S 2 -y 12 "Feels ${feels}  High ${today_high}  Low ${today_low}  Rain ${today_rain}%  Wind ${wind} ${wind_unit}"
    "$FBINK" -q -b -m -S 2 -y 18 "NEXT $HOURLY_FORECAST_COUNT HOURS"
    i=0
    printf '%s\n' "$groups" | while IFS='|' read -r first last low high hour_code hour_rain; do
        [ -n "$first" ] || continue
        temperatures="$low"; [ "$low" = "$high" ] || temperatures="$low-$high"
        marker=""; [ "$hour_code" -lt 51 ] || marker="! "
        "$FBINK" -q -b -S 2 -x 2 -y $((22 + i * 2)) "$marker$(period_label "$first" "$last")  $temperatures $unit  $(weather_description "$hour_code")  $hour_rain%"
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
