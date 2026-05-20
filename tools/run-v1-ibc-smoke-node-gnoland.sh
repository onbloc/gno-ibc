#!/usr/bin/env bash
# Run a gnoland node pre-loaded with all IBC packages.
#
# State is persisted in DATA_DIR so the node resumes from the last block on
# subsequent runs.  Use --reset to wipe state and start a fresh chain.
#
# Usage:
#   ./run-v1-ibc-smoke-node-gnoland.sh          # resume or fresh start
#   ./run-v1-ibc-smoke-node-gnoland.sh --reset  # wipe state, start from block 0
#
# Logs are written to $CACHE_DIR/gnoland.log and also printed to the terminal.
# To follow logs in another terminal:
#   tail -f "$HOME/.cache/gno-ibc/gnoland.log"
#
# To force genesis-txs regeneration (after changing .gno sources):
#   rm "$HOME/.cache/gno-ibc/ibc-genesis-txs.jsonl"
set -euo pipefail

GNO_ROOT="${GNO_ROOT:-$HOME/.cache/gno-ibc/gno}"
GNO_IBC_ROOT="${GNO_IBC_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
RPC_LISTENER="${RPC_LISTENER:-0.0.0.0:26657}"
CHAIN_ID="${CHAIN_ID:-dev}"

CACHE_DIR="${CACHE_DIR:-$HOME/.cache/gno-ibc}"
GENESIS_TXS="$CACHE_DIR/ibc-genesis-txs.jsonl"
DATA_DIR="${DATA_DIR:-$CACHE_DIR/gnoland-data}"
LOG_FILE="${LOG_FILE:-$CACHE_DIR/gnoland.log}"

# gnoland reads GNOROOT at flag-registration time (before -gnoroot-dir is
# parsed), so the env var must be set even though we also pass -gnoroot-dir.
export GNOROOT="$GNO_ROOT"

# ── flags ─────────────────────────────────────────────────────────────────────
RESET=false
for arg in "$@"; do
    case "$arg" in
        --reset) RESET=true ;;
        *) echo "unknown flag: $arg"; exit 1 ;;
    esac
done

if $RESET; then
    echo ">> wiping node state: $DATA_DIR"
    rm -rf "$DATA_DIR"
fi

# ── 1. Generate genesis txs if not cached ─────────────────────────────────────
if [ ! -f "$GENESIS_TXS" ]; then
    echo ">> generating genesis txs (cached at $GENESIS_TXS after first run)"
    mkdir -p "$CACHE_DIR"
    python3 "$GNO_IBC_ROOT/tools/gen-ibc-genesis-txs.py" \
        --ibc-root "$GNO_IBC_ROOT" \
        --output "$GENESIS_TXS"
fi

# ── 2. Prepare config (idempotent) ───────────────────────────────────────────
mkdir -p "$DATA_DIR"
gnoland config init -force -config-path "$DATA_DIR/config/config.toml"
gnoland config set rpc.laddr "tcp://$RPC_LISTENER" \
    -config-path "$DATA_DIR/config/config.toml"

# ── 3. First run vs. resume ───────────────────────────────────────────────────
# genesis.json is stored explicitly inside DATA_DIR so its presence reliably
# indicates whether a chain has already been initialised.
if [ ! -f "$DATA_DIR/genesis.json" ]; then
    echo ">> starting gnoland from block 0 (rpc: $RPC_LISTENER, data: $DATA_DIR)"
    echo ">> logs: $LOG_FILE"
    gnoland start \
        -lazy \
        -chainid "$CHAIN_ID" \
        -gnoroot-dir "$GNO_ROOT" \
        -data-dir "$DATA_DIR" \
        -genesis "$DATA_DIR/genesis.json" \
        -genesis-txs-file "$GENESIS_TXS" \
        -skip-genesis-sig-verification \
        -log-format console \
        2>&1 | tee "$LOG_FILE"
else
    echo ">> resuming gnoland from existing state (rpc: $RPC_LISTENER, data: $DATA_DIR)"
    echo ">> logs: $LOG_FILE"
    gnoland start \
        -gnoroot-dir "$GNO_ROOT" \
        -data-dir "$DATA_DIR" \
        -genesis "$DATA_DIR/genesis.json" \
        -log-format console \
        2>&1 | tee "$LOG_FILE"
fi
