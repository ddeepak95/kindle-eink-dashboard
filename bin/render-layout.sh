#!/bin/sh
# Run in a fresh shell so rendering errors propagate to the rollback controller.
set -e
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"
DASHBOARD_LAYOUT_DIR="$1"
[ -s "$WEATHER_CACHE" ] || exit 1
FBINK=$(find_fbink) || exit 1
set_landscape || exit 1
. "$DASHBOARD_LAYOUT_DIR/render.sh"