#!/bin/sh

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
"$SCRIPT_DIR/fetch.sh" 0 || exit 1
exec "$SCRIPT_DIR/render.sh"
