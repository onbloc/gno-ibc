#!/bin/sh
set -eu

UNION_VOYAGER_DIR="${UNION_VOYAGER_DIR:-/Users/notjoon/union-voyager}"
VOYAGER_CONFIG="${VOYAGER_CONFIG:-$(pwd)/voyager-config.gno-union.jsonc}"
VOYAGER_BIN="${VOYAGER_BIN:-$UNION_VOYAGER_DIR/target/debug/voyager}"

if [ ! -x "$VOYAGER_BIN" ]; then
  echo "missing $VOYAGER_BIN; build Voyager first" >&2
  exit 1
fi

cd "$UNION_VOYAGER_DIR"
exec "$VOYAGER_BIN" -c "$VOYAGER_CONFIG" "$@"
