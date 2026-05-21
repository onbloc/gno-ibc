#!/usr/bin/env bash
set -euo pipefail

ETH_GNO_SMOKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ETH_GNO_TESTDATA_DIR="$ETH_GNO_SMOKE_DIR/testdata"
GNO_IBC_ROOT="${GNO_IBC_ROOT:-$(cd "$ETH_GNO_SMOKE_DIR/../.." && pwd)}"

# Reuse the existing smoke-node/key helpers until this harness needs behavior
# that differs from tools/gnokey-smoke.
source "$GNO_IBC_ROOT/tools/gnokey-smoke/lib.sh"

require_command() {
  local name="$1"
  command -v "$name" >/dev/null 2>&1 || {
    echo "ERROR: '$name' not found on PATH"
    exit 1
  }
}

capture_field() {
  local name="$1"
  local file="$2"
  awk -v key="$name" '$1 == key { print $2; exit }' "$file"
}

require_field() {
  local name="$1"
  local file="$2"
  local value
  value="$(capture_field "$name" "$file")"
  if [[ -z "$value" ]]; then
    echo "FAIL: missing '$name' in $file"
    cat "$file"
    exit 1
  fi
  printf "%s" "$value"
}

status_incomplete() {
  local direction="$1"
  cat <<EOF
ERROR: $direction smoke runner is scaffolded but not fully implemented.

See tools/eth-gno-smoke/README.md and
local_docs/plans/eth-gno-independent-smoke-plan.md for the byte contracts and
remaining automation steps.

Set ETH_GNO_SMOKE_ALLOW_INCOMPLETE=1 to print this status without failing.
EOF
  if [[ "${ETH_GNO_SMOKE_ALLOW_INCOMPLETE:-}" == "1" ]]; then
    return 0
  fi
  exit 1
}
