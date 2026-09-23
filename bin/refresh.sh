#!/bin/sh

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
"$SCRIPT_DIR/fetch.sh" 1 || exit 1
exec "$SCRIPT_DIR/render.sh"
