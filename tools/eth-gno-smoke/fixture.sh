#!/usr/bin/env bash
# fixture.sh — entrypoint for generating and validating ETH/Gno smoke fixtures.
#
#   fixture.sh eth-proof                    generate a local anvil ETH storage proof
#   fixture.sh sepolia-ugnot [--check]      validate committed Sepolia ugnot fixtures (offline)
#   fixture.sh zkgm-tokenorder-vectors --check
#   fixture.sh sepolia-ugnot --refresh      refetch Sepolia ugnot fixtures (needs SEPOLIA_RPC_URL)
set -euo pipefail

SMOKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  echo "usage: fixture.sh {eth-proof|sepolia-ugnot [--check|--refresh]|zkgm-tokenorder-vectors --check}" >&2
  exit 2
}

case "${1:-}" in
  eth-proof)
    exec "$SMOKE_DIR/scenarios/eth-proof/run.sh"
    ;;
  sepolia-ugnot)
    case "${2:-}" in
      ""|--check)
        cd "$SMOKE_DIR"
        exec go run ./cmd/check-sepolia-ugnot-fixtures
        ;;
      --refresh)
        exec "$SMOKE_DIR/scenarios/sepolia-ugnot/fetch.sh"
        ;;
      *)
      usage
      ;;
    esac
    ;;
  zkgm-tokenorder-vectors)
    case "${2:-}" in
      --check)
        cd "$SMOKE_DIR"
        exec go run ./cmd/check-zkgm-tokenorder-vectors
        ;;
      *)
        usage
        ;;
    esac
    ;;
  *)
    usage
    ;;
esac
