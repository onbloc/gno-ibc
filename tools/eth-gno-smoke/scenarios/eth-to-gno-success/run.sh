#!/usr/bin/env bash
set -euo pipefail

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ETH_GNO_SMOKE_DIR="$(cd "$SCENARIO_DIR/../.." && pwd)"
source "$ETH_GNO_SMOKE_DIR/lib/env.sh"
source "$ETH_GNO_SMOKE_DIR/lib/log.sh"
source "$ETH_GNO_SMOKE_DIR/lib/gno.sh"
source "$ETH_GNO_SMOKE_DIR/lib/recv.sh"

RPC_LISTENER="${ETH_GNO_SUCCESS_RECV_RPC_LISTENER:-127.0.0.1:26659}"
RPC_URL="${ETH_GNO_SUCCESS_RECV_RPC_URL:-http://127.0.0.1:26659}"
RPC_ENDPOINT="${ETH_GNO_SUCCESS_RECV_RPC_ENDPOINT:-tcp://127.0.0.1:26659}"

require_command gnokey
require_command gnodev
require_command anvil
require_command jq

SMOKE_GAS_WANTED="${ETH_GNO_SMOKE_GAS_WANTED:-200000000}"

trap cleanup_eth_gno_smoke_env EXIT
setup_smoke_chain

OUTPUT_FIXTURE="${ETH_GNO_ETH_TO_GNO_SUCCESS_FIXTURE:-$SCENARIO_DIR/fixture.json}"

echo ">> ETH -> Gno success proof input derivation"
maketx_run "$SCENARIO_DIR/fixture_inputs.gno" "$WORKDIR/fixture_inputs_success.log"
derive_recv_proof_inputs "$WORKDIR/fixture_inputs_success.log"
EXPECTED_SENDER="$(require_field expected_sender "$WORKDIR/fixture_inputs_success.log")"
EXPECTED_CALLDATA="$(require_field expected_calldata "$WORKDIR/fixture_inputs_success.log")"
COMMITMENTS_JSON="$(recv_commitments_json)"

echo ">> ETH -> Gno success storage proof generation"
generate_recv_proof_fixture "$OUTPUT_FIXTURE" "$COMMITMENTS_JSON"
load_recv_proof_fixture "$OUTPUT_FIXTURE"

render_template "$SCENARIO_DIR/recv.gno.tmpl" "$WORKDIR/recv_call_success.gno" \
  -e "s|@STORAGE_ROOT_HEX@|$STORAGE_ROOT|g" \
  -e "s|@CONN_ACK_PROOF_HEX@|$CONN_ACK_PROOF|g" \
  -e "s|@CHANNEL_ACK_PROOF_HEX@|$CHANNEL_ACK_PROOF|g" \
  -e "s|@PACKET_DATA_HEX@|$PACKET_DATA_HEX|g" \
  -e "s|@PACKET_TIMEOUT_TIMESTAMP@|$PACKET_TIMEOUT_TIMESTAMP|g" \
  -e "s|@PACKET_PROOF_HEX@|$PACKET_PROOF|g" \
  -e "s|@EXPECTED_SENDER@|$EXPECTED_SENDER|g" \
  -e "s|@EXPECTED_CALLDATA@|$EXPECTED_CALLDATA|g"

echo ">> ETH -> Gno success PacketRecv"
maketx_run "$WORKDIR/recv_call_success.gno" "$WORKDIR/recv_call_success.log"

RECV_LOG="$WORKDIR/recv_call_success.log"
require_log_line '"type":"PacketRecv"' "$RECV_LOG" "PacketRecv event missing"
require_log_line '"type":"WriteAck"' "$RECV_LOG" "WriteAck event missing"
require_log_line '^has_receipt true$' "$RECV_LOG" "packet receipt missing"
require_log_line '^has_ack true$' "$RECV_LOG" "acknowledgement missing"
require_log_line '^ack_success true$' "$RECV_LOG" "success acknowledgement missing"
require_log_line '^mock_calls 1$' "$RECV_LOG" "mock receiver was not called exactly once"
require_log_line "^last_sender $EXPECTED_SENDER$" "$RECV_LOG" "mock sender mismatch"
require_log_line "^last_calldata $EXPECTED_CALLDATA$" "$RECV_LOG" "mock calldata mismatch"
require_log_line '^last_relayer_msg success-relayer-msg$' "$RECV_LOG" "mock relayer message mismatch"
require_log_line '^last_source_channel 1$' "$RECV_LOG" "mock source channel mismatch"
require_log_line '^last_destination_channel 1$' "$RECV_LOG" "mock destination channel mismatch"
require_log_line '^has_receipt_after_duplicate true$' "$RECV_LOG" "packet receipt missing after duplicate"
require_log_line '^has_ack_after_duplicate true$' "$RECV_LOG" "acknowledgement missing after duplicate"
require_log_line '^mock_calls_after_duplicate 1$' "$RECV_LOG" "duplicate receive called mock receiver"
ACK_HASH_AFTER_RECV="$(require_field ack_hash_after_recv "$RECV_LOG")"
ACK_HASH_AFTER_DUPLICATE="$(require_field ack_hash_after_duplicate "$RECV_LOG")"
if [[ "$ACK_HASH_AFTER_RECV" != "$ACK_HASH_AFTER_DUPLICATE" ]]; then
  echo "FAIL: duplicate receive changed acknowledgement hash"
  echo "  after_recv=$ACK_HASH_AFTER_RECV"
  echo "  after_duplicate=$ACK_HASH_AFTER_DUPLICATE"
  exit 1
fi

echo "PASS: ETH -> Gno success acknowledgement smoke"
