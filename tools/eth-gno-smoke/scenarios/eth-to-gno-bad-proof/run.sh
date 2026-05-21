#!/usr/bin/env bash
set -euo pipefail

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ETH_GNO_SMOKE_DIR="$(cd "$SCENARIO_DIR/../.." && pwd)"
SUCCESS_SCENARIO_DIR="$ETH_GNO_SMOKE_DIR/scenarios/eth-to-gno-success"
source "$ETH_GNO_SMOKE_DIR/lib/env.sh"
source "$ETH_GNO_SMOKE_DIR/lib/log.sh"
source "$ETH_GNO_SMOKE_DIR/lib/gno.sh"
source "$ETH_GNO_SMOKE_DIR/lib/recv.sh"

RPC_LISTENER="${ETH_GNO_BAD_PROOF_RECV_RPC_LISTENER:-127.0.0.1:26660}"
RPC_URL="${ETH_GNO_BAD_PROOF_RECV_RPC_URL:-http://127.0.0.1:26660}"
RPC_ENDPOINT="${ETH_GNO_BAD_PROOF_RECV_RPC_ENDPOINT:-tcp://127.0.0.1:26660}"

require_command gnokey
require_command gnodev
require_command anvil
require_command jq

SMOKE_GAS_WANTED="${ETH_GNO_SMOKE_GAS_WANTED:-200000000}"
ZERO_COMMITMENT="0x0000000000000000000000000000000000000000000000000000000000000000"

trap cleanup_eth_gno_smoke_env EXIT
setup_smoke_chain

OUTPUT_FIXTURE="${ETH_GNO_ETH_TO_GNO_BAD_PROOF_FIXTURE:-$SCENARIO_DIR/fixture.json}"

echo ">> ETH -> Gno bad packet proof input derivation"
maketx_run "$SUCCESS_SCENARIO_DIR/fixture_inputs.gno" "$WORKDIR/fixture_inputs_bad_proof.log"
derive_recv_proof_inputs "$WORKDIR/fixture_inputs_bad_proof.log"
EXPECTED_SENDER="$(require_field expected_sender "$WORKDIR/fixture_inputs_bad_proof.log")"
EXPECTED_CALLDATA="$(require_field expected_calldata "$WORKDIR/fixture_inputs_bad_proof.log")"
COMMITMENTS_JSON="$(recv_commitments_json "$ZERO_COMMITMENT")"

echo ">> ETH -> Gno bad packet proof generation"
generate_recv_proof_fixture "$OUTPUT_FIXTURE" "$COMMITMENTS_JSON"
load_recv_proof_fixture "$OUTPUT_FIXTURE"

render_template "$SUCCESS_SCENARIO_DIR/recv.gno.tmpl" "$WORKDIR/recv_bad_packet_proof.gno" \
  -e "s|@STORAGE_ROOT_HEX@|$STORAGE_ROOT|g" \
  -e "s|@CONN_ACK_PROOF_HEX@|$CONN_ACK_PROOF|g" \
  -e "s|@CHANNEL_ACK_PROOF_HEX@|$CHANNEL_ACK_PROOF|g" \
  -e "s|@PACKET_DATA_HEX@|$PACKET_DATA_HEX|g" \
  -e "s|@PACKET_TIMEOUT_TIMESTAMP@|$PACKET_TIMEOUT_TIMESTAMP|g" \
  -e "s|@PACKET_PROOF_HEX@|$PACKET_PROOF|g" \
  -e "s|@EXPECTED_SENDER@|$EXPECTED_SENDER|g" \
  -e "s|@EXPECTED_CALLDATA@|$EXPECTED_CALLDATA|g"

echo ">> ETH -> Gno bad packet proof rejection"
if echo "" | gnokey maketx run -insecure-password-stdin \
  -home "$KEYBASE" \
  -gas-fee "$SMOKE_GAS_FEE" -gas-wanted "$SMOKE_GAS_WANTED" \
  -broadcast -chainid "$CHAIN_ID" -remote "$RPC_ENDPOINT" \
  "$SMOKE_KEY_NAME" "$WORKDIR/recv_bad_packet_proof.gno" 2>&1 | tee "$WORKDIR/recv_bad_packet_proof.log"; then
  echo "FAIL: PacketRecv accepted a packet proof with the wrong commitment value"
  exit 1
fi

require_log_line 'statelensics23mpt: stored value mismatch' "$WORKDIR/recv_bad_packet_proof.log" "expected commitment-value rejection missing"

echo "PASS: ETH -> Gno bad packet proof rejected"
