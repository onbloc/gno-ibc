#!/usr/bin/env bash
# env.sh — shared paths, ports, and environment for the eth-gno-smoke harness.
#
# Sourced first by every entrypoint. It pulls in the smoke-node and key helpers
# from tools/gnokey-smoke (init_smoke_env, cleanup_smoke_env, setup_smoke_chain,
# maketx_run, render_template, ...) and adds the ETH-side configuration plus the
# combined cleanup hook.

ETH_GNO_SMOKE_DIR="${ETH_GNO_SMOKE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
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

require_command() {
  local name="$1"
  command -v "$name" >/dev/null 2>&1 || {
    echo "ERROR: '$name' not found on PATH"
    exit 1
  }
}

cleanup_eth_gno_smoke_env() {
  if [[ -n "${ANVIL_PID:-}" ]] && kill -0 "$ANVIL_PID" 2>/dev/null; then
    kill "$ANVIL_PID" 2>/dev/null || true
    wait "$ANVIL_PID" 2>/dev/null || true
  fi
  cleanup_smoke_env
}
