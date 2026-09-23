#!/bin/sh

# Location shown on the dashboard.
LOCATION_NAME="Ithaca"
LATITUDE="42.44063"
LONGITUDE="-76.49661"
TIMEZONE="America/New_York"

# Open-Meteo units: fahrenheit/celsius and mph/kmh/ms/kn.
TEMPERATURE_UNIT="fahrenheit"
WIND_SPEED_UNIT="mph"
PRECIPITATION_UNIT="inch"

# Number of daily rows requested. The renderer uses today plus three days.
FORECAST_DAYS="4"
HOURLY_FORECAST_COUNT="6"

# Avoid repeated downloads when Show Dashboard is tapped several times.
MIN_REFRESH_SECONDS="300"
NETWORK_TIMEOUT_SECONDS="35"

# Low-power dashboard cycle. The Kindle wakes, refreshes, and suspends again.
# Start with one hour; do not reduce below five minutes.
REFRESH_INTERVAL_SECONDS="3600"
WAKE_SETTLE_SECONDS="10"

# Automatic mode turns Wi-Fi on only for fetching and parks it before sleep.
MANAGE_WIFI="1"
WIFI_WAIT_SECONDS="10"

# Set to 0 for a weather-only screen.
SHOW_QUOTE="1"

# Optional plain-text URL. Line 1 is the quote; line 2 is the author.
# Leave blank to rotate through data/quotes.txt once per day.
QUOTE_URL=""

# Optional FBInk override. When blank, common KUAL/FBInk paths are searched.
FBINK_PATH=""

# Optional fbdepth override. The bundled PW2 binary supports the Paperwhite 3.
FBDEPTH_PATH=""

# Paperwhite system fonts used by FBInk's OpenType renderer.
FONT_REGULAR="/usr/java/lib/fonts/Caecilia_LT_65_Medium.ttf"
FONT_BOLD="/usr/java/lib/fonts/Caecilia_LT_75_Bold.ttf"
