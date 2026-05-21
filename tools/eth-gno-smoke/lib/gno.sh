#!/usr/bin/env bash
# gno.sh — gnodev launch override for the eth-gno-smoke harness.
#
# The smoke-node and key helpers come from tools/gnokey-smoke/lib.sh, sourced by
# lib/env.sh. This file overrides run_smoke_node with the resolver and realm-path
# set the ETH/Gno harness needs, so it must be sourced after lib/env.sh.

run_smoke_node() {
  GNODEV_HOME="${GNODEV_HOME:-$WORKDIR/gnodev-home}"
  mkdir -p "$GNODEV_HOME"

  # exec so the caller's `... & GNODEV_PID=$!` captures gnodev's PID, not
  # the wrapping subshell — otherwise cleanup's kill orphans gnodev.
  exec gnodev local \
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
