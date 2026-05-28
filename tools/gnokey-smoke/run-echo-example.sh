#!/usr/bin/env bash
set -euo pipefail

GNO_SMOKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GNO_IBC_ROOT="${GNO_IBC_ROOT:-$(cd "$GNO_SMOKE_DIR/../.." && pwd)}"

SMOKE_EXTRA_RESOLVERS=(
  "local=$GNO_IBC_ROOT/gno.land/r/core/ibc/examples/echo"
)
SMOKE_EXTRA_PATHS="gno.land/r/gnoswap/ibc/examples/echo"

source "$GNO_SMOKE_DIR/lib.sh"

trap cleanup_smoke_env EXIT
setup_smoke_chain
ECHO_TESTDATA_DIR="$SMOKE_TESTDATA_DIR/echo"

echo ">> Phase 1: confirm echo registered with the ZKGM proxy"
probe_qeval "echo registered" \
  'gno.land/r/gnoswap/ibc/v1/apps/zkgm.GetReceiver("gno.land/r/gnoswap/ibc/examples/echo") != nil' \
  "true"

echo ">> Phase 2: invoke OnZkgm with a sample CallEnv"
maketx_run "$ECHO_TESTDATA_DIR/invoke_receiver.gno" "$WORKDIR/invoke_receiver.log"
require_log_line "$WORKDIR/invoke_receiver.log" '^registered true' "receiver registered at invoke time"
require_log_line "$WORKDIR/invoke_receiver.log" '^calls 1'        "receiver call count incremented"
require_log_line "$WORKDIR/invoke_receiver.log" '^last_calldata hello' "receiver captured calldata"
echo "PASS: receiver observed the CallEnv"

echo ">> Phase 3: read back captured state via vm/qeval"
probe_qeval "echo.Calls()" \
  'gno.land/r/gnoswap/ibc/examples/echo.Calls()' \
  "1"
probe_qeval "echo.LastCalldata()" \
  'gno.land/r/gnoswap/ibc/examples/echo.LastCalldata()' \
  "hello"

echo "PASS: echo-receiver example end-to-end"
