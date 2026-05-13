#!/usr/bin/env bash
set -euo pipefail

GNO_ROOT="${GNO_ROOT:-$HOME/.cache/gno-ibc/gno}"
GNO_IBC_ROOT="${GNO_IBC_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
RPC_LISTENER="${RPC_LISTENER:-0.0.0.0:26657}"

gnodev local \
  -root "$GNO_ROOT" \
  -resolver "root=$GNO_IBC_ROOT" \
  -resolver "root=$GNO_ROOT/examples" \
  -resolver "local=$GNO_IBC_ROOT/gno.land/p/core/ibc/zkgm" \
  -resolver "local=$GNO_IBC_ROOT/gno.land/p/core/tokenbucket" \
  -resolver "local=$GNO_IBC_ROOT/gno.land/r/core/ibc/v1/apps/zkgm" \
  -resolver "local=$GNO_IBC_ROOT/gno.land/r/core/ibc/v1/apps/zkgm/v0/impl" \
  -resolver "local=$GNO_IBC_ROOT/gno.land/r/core/ibc/v1/apps/zkgm/v0/loader" \
  -resolver "local=$GNO_IBC_ROOT/gno.land/r/core/ibc/v1/apps/zkgm/testing/e2e" \
  -paths "gno.land/r/core/ibc/v1/core,gno.land/r/core/ibc/v1/lightclients/cometbls,gno.land/r/core/ibc/v1/lightclients/statelensics23mpt,gno.land/r/gnoswap/ibc/v1/apps/zkgm,gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/impl,gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/loader,gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e" \
  -no-web \
  -node-rpc-listener "$RPC_LISTENER"
