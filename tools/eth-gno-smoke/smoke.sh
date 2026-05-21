#!/usr/bin/env bash
# smoke.sh — entrypoint for the local ETH/Gno packet smoke scenarios.
#
#   smoke.sh gno-to-eth          Gno ZKGM send -> ETH-consumable packet commitment
#   smoke.sh eth-to-gno          ETH storage proof -> Gno PacketRecv (error ack)
#   smoke.sh eth-to-gno-success  ETH storage proof -> Gno PacketRecv (success ack)
#   smoke.sh eth-to-gno-bad-proof  ETH storage proof rejection with wrong value
#   smoke.sh all                 run every smoke scenario in order
set -euo pipefail

SMOKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  echo "usage: smoke.sh {gno-to-eth|eth-to-gno|eth-to-gno-success|eth-to-gno-bad-proof|all}" >&2
  exit 2
}

case "${1:-}" in
  gno-to-eth)
    exec "$SMOKE_DIR/scenarios/gno-to-eth/run.sh"
    ;;
  eth-to-gno)
    exec "$SMOKE_DIR/scenarios/eth-to-gno-error/run.sh"
    ;;
  eth-to-gno-success)
    exec "$SMOKE_DIR/scenarios/eth-to-gno-success/run.sh"
    ;;
  eth-to-gno-bad-proof)
    exec "$SMOKE_DIR/scenarios/eth-to-gno-bad-proof/run.sh"
    ;;
  all)
    "$SMOKE_DIR/scenarios/gno-to-eth/run.sh"
    "$SMOKE_DIR/scenarios/eth-to-gno-error/run.sh"
    "$SMOKE_DIR/scenarios/eth-to-gno-success/run.sh"
    "$SMOKE_DIR/scenarios/eth-to-gno-bad-proof/run.sh"
    ;;
  *)
    usage
    ;;
esac
