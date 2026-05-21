#!/usr/bin/env bash
set -euo pipefail

RPC_LISTENER="${RPC_LISTENER:-0.0.0.0:26657}"

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gnokey-smoke/lib.sh"

run_smoke_node
