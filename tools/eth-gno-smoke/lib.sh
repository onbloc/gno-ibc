#!/usr/bin/env bash
set -euo pipefail

ETH_GNO_SMOKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ETH_GNO_TESTDATA_DIR="$ETH_GNO_SMOKE_DIR/testdata"
GNO_IBC_ROOT="${GNO_IBC_ROOT:-$(cd "$ETH_GNO_SMOKE_DIR/../.." && pwd)}"
ANVIL_RPC_URL="${ANVIL_RPC_URL:-http://127.0.0.1:8545}"
ANVIL_HOST="${ANVIL_HOST:-127.0.0.1}"
ANVIL_PORT="${ANVIL_PORT:-8545}"
ANVIL_PRIVATE_KEY="${ANVIL_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"

# core.COMMITMENT_MAGIC (gno.land/r/core/ibc/v1/core/path.gno): the value stored
# at a packet commitment path once a packet is committed.
ETH_GNO_COMMITMENT_MAGIC_HEX="0x0100000000000000000000000000000000000000000000000000000000000000"

# Reuse the existing smoke-node/key helpers until this harness needs behavior
# that differs from tools/gnokey-smoke.
source "$GNO_IBC_ROOT/tools/gnokey-smoke/lib.sh"

run_smoke_node() {
  GNODEV_HOME="${GNODEV_HOME:-$WORKDIR/gnodev-home}"
  mkdir -p "$GNODEV_HOME"

  gnodev local \
    -home "$GNODEV_HOME" \
    -root "$GNO_ROOT" \
    -resolver "root=$GNO_IBC_ROOT" \
    -resolver "root=$GNO_ROOT/examples" \
    -resolver "local=$GNO_IBC_ROOT/gno.land/p/core/ibc/zkgm" \
    -resolver "local=$GNO_IBC_ROOT/gno.land/p/core/tokenbucket" \
    -resolver "local=$GNO_IBC_ROOT/gno.land/r/core/ibc/v1/apps/zkgm" \
    -resolver "local=$GNO_IBC_ROOT/gno.land/r/core/ibc/v1/apps/zkgm/v0/impl" \
    -resolver "local=$GNO_IBC_ROOT/gno.land/r/core/ibc/v1/apps/zkgm/v0/loader" \
    -resolver "local=$GNO_IBC_ROOT/gno.land/r/core/ibc/v1/apps/zkgm/testing/e2e" \
    -paths "gno.land/r/core/ibc/v1/core,gno.land/r/core/ibc/v1/lightclients/cometbls,gno.land/r/core/ibc/v1/lightclients/statelensics23mpt,gno.land/r/gnoswap/ibc/v1/apps/zkgm,gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/impl,gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/loader,gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e,gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/mock" \
    -no-web \
    -node-rpc-listener "$RPC_LISTENER"
}

cleanup_eth_gno_smoke_env() {
  if [[ -n "${ANVIL_PID:-}" ]] && kill -0 "$ANVIL_PID" 2>/dev/null; then
    kill "$ANVIL_PID" 2>/dev/null || true
    wait "$ANVIL_PID" 2>/dev/null || true
  fi
  cleanup_smoke_env
}

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

require_log_line() {
  local pattern="$1"
  local file="$2"
  local msg="$3"
  if ! grep -q "$pattern" "$file"; then
    echo "FAIL: $msg"
    cat "$file"
    exit 1
  fi
}

start_anvil() {
  init_smoke_env

  if cast block-number --rpc-url "$ANVIL_RPC_URL" >/dev/null 2>&1; then
    echo "ERROR: $ANVIL_RPC_URL already responds before smoke anvil startup"
    echo "Stop the existing anvil process or choose an isolated ANVIL_PORT/ANVIL_RPC_URL."
    exit 1
  fi

  echo ">> starting anvil on $ANVIL_HOST:$ANVIL_PORT"
  anvil --host "$ANVIL_HOST" --port "$ANVIL_PORT" >"$WORKDIR/anvil.log" 2>&1 &
  ANVIL_PID=$!
  sleep 0.2
  if ! kill -0 "$ANVIL_PID" 2>/dev/null; then
    echo "anvil exited unexpectedly"
    cat "$WORKDIR/anvil.log"
    exit 1
  fi

  local deadline=$((SECONDS + 30))
  while (( SECONDS < deadline )); do
    if cast block-number --rpc-url "$ANVIL_RPC_URL" >/dev/null 2>&1; then
      echo ">> anvil ready"
      return
    fi
    if ! kill -0 "$ANVIL_PID" 2>/dev/null; then
      echo "anvil exited unexpectedly"
      cat "$WORKDIR/anvil.log"
      exit 1
    fi
    sleep 1
  done

  echo "anvil not ready within 30s"
  cat "$WORKDIR/anvil.log"
  exit 1
}
