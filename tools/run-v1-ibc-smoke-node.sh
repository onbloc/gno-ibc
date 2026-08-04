#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=$(cd "$script_dir/.." && pwd -P)
gno_root=${GNO_ROOT:-$HOME/.cache/gno-ibc/gno}

exec gnodev local \
  -C "$repo_root" \
  -root "$gno_root" \
  -extra-root "$repo_root" \
  -chain-id "${CHAIN_ID:-dev}" \
  -no-web \
  -node-rpc-listener "${RPC_LISTENER:-0.0.0.0:26657}" \
  -paths "gno.land/r/onbloc/ibc/union/access,gno.land/r/onbloc/ibc/union/core,gno.land/r/onbloc/ibc/union/core/v1,gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm,gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1,gno.land/r/onbloc/ibc/union/testing/e2e_setup"
