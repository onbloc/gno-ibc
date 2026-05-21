#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

RPC_LISTENER="${ETH_GNO_RECV_RPC_LISTENER:-127.0.0.1:26658}"
RPC_URL="${ETH_GNO_RECV_RPC_URL:-http://127.0.0.1:26658}"
RPC_ENDPOINT="${ETH_GNO_RECV_RPC_ENDPOINT:-tcp://127.0.0.1:26658}"

require_command gnokey
require_command gnodev
require_command anvil
require_command jq

SMOKE_GAS_WANTED="${ETH_GNO_SMOKE_GAS_WANTED:-200000000}"

trap cleanup_eth_gno_smoke_env EXIT
setup_smoke_chain

ETH_TO_GNO_TESTDATA_DIR="$ETH_GNO_TESTDATA_DIR/eth-to-gno"
OUTPUT_FIXTURE="${ETH_GNO_ETH_TO_GNO_FIXTURE:-$ETH_TO_GNO_TESTDATA_DIR/latest.json}"

echo ">> ETH -> Gno proof input derivation"
maketx_run "$ETH_TO_GNO_TESTDATA_DIR/fixture_inputs.gno" "$WORKDIR/fixture_inputs.log"

CONN_ACK_PATH="$(require_field conn_ack_path "$WORKDIR/fixture_inputs.log")"
CONN_ACK_VALUE="$(require_field conn_ack_value "$WORKDIR/fixture_inputs.log")"
CHANNEL_ACK_PATH="$(require_field channel_ack_path "$WORKDIR/fixture_inputs.log")"
CHANNEL_ACK_VALUE="$(require_field channel_ack_value "$WORKDIR/fixture_inputs.log")"
PACKET_PATH="$(require_field packet_path "$WORKDIR/fixture_inputs.log")"
PACKET_VALUE="$(require_field packet_value "$WORKDIR/fixture_inputs.log")"
PACKET_DATA_HEX="$(require_field packet_data_hex "$WORKDIR/fixture_inputs.log")"
PACKET_TIMEOUT_TIMESTAMP="$(require_field packet_timeout_timestamp "$WORKDIR/fixture_inputs.log")"

COMMITMENTS_JSON="$(jq -n \
  --arg conn_path "$CONN_ACK_PATH" \
  --arg conn_value "$CONN_ACK_VALUE" \
  --arg channel_path "$CHANNEL_ACK_PATH" \
  --arg channel_value "$CHANNEL_ACK_VALUE" \
  --arg packet_path "$PACKET_PATH" \
  --arg packet_value "$PACKET_VALUE" \
  '[
    {name: "conn_ack", path_hex: $conn_path, value_hex: $conn_value},
    {name: "channel_ack", path_hex: $channel_path, value_hex: $channel_value},
    {name: "packet", path_hex: $packet_path, value_hex: $packet_value}
  ]')"

echo ">> ETH -> Gno storage proof generation"
ETH_GNO_COMMITMENTS_JSON="$COMMITMENTS_JSON" \
ETH_GNO_ETH_TO_GNO_FIXTURE="$OUTPUT_FIXTURE" \
  "$ETH_GNO_SMOKE_DIR/generate-eth-proof-fixture.sh"

STORAGE_ROOT="$(jq -r '.eth.storage_root' "$OUTPUT_FIXTURE")"
CONN_ACK_PROOF="$(jq -r '.proofs.conn_ack.proof_bytes_hex' "$OUTPUT_FIXTURE")"
CHANNEL_ACK_PROOF="$(jq -r '.proofs.channel_ack.proof_bytes_hex' "$OUTPUT_FIXTURE")"
PACKET_PROOF="$(jq -r '.proofs.packet.proof_bytes_hex' "$OUTPUT_FIXTURE")"

render_template "$ETH_TO_GNO_TESTDATA_DIR/recv_packet.gno.tmpl" "$WORKDIR/recv_packet.gno" \
  -e "s|@STORAGE_ROOT_HEX@|$STORAGE_ROOT|g" \
  -e "s|@CONN_ACK_PROOF_HEX@|$CONN_ACK_PROOF|g" \
  -e "s|@CHANNEL_ACK_PROOF_HEX@|$CHANNEL_ACK_PROOF|g" \
  -e "s|@PACKET_DATA_HEX@|$PACKET_DATA_HEX|g" \
  -e "s|@PACKET_TIMEOUT_TIMESTAMP@|$PACKET_TIMEOUT_TIMESTAMP|g" \
  -e "s|@PACKET_PROOF_HEX@|$PACKET_PROOF|g"

echo ">> ETH -> Gno PacketRecv"
maketx_run "$WORKDIR/recv_packet.gno" "$WORKDIR/recv_packet.log"

grep -q '"type":"PacketRecv"' "$WORKDIR/recv_packet.log" \
  || { echo "FAIL: PacketRecv event missing"; cat "$WORKDIR/recv_packet.log"; exit 1; }
grep -q '"type":"WriteAck"' "$WORKDIR/recv_packet.log" \
  || { echo "FAIL: WriteAck event missing"; cat "$WORKDIR/recv_packet.log"; exit 1; }
grep -q '^has_receipt true$' "$WORKDIR/recv_packet.log" \
  || { echo "FAIL: packet receipt missing"; cat "$WORKDIR/recv_packet.log"; exit 1; }
grep -q '^has_ack true$' "$WORKDIR/recv_packet.log" \
  || { echo "FAIL: acknowledgement missing"; cat "$WORKDIR/recv_packet.log"; exit 1; }
grep -q '^has_receipt_after_duplicate true$' "$WORKDIR/recv_packet.log" \
  || { echo "FAIL: packet receipt missing after duplicate"; cat "$WORKDIR/recv_packet.log"; exit 1; }
grep -q '^has_ack_after_duplicate true$' "$WORKDIR/recv_packet.log" \
  || { echo "FAIL: acknowledgement missing after duplicate"; cat "$WORKDIR/recv_packet.log"; exit 1; }
ACK_HASH_AFTER_RECV="$(require_field ack_hash_after_recv "$WORKDIR/recv_packet.log")"
ACK_HASH_AFTER_DUPLICATE="$(require_field ack_hash_after_duplicate "$WORKDIR/recv_packet.log")"
if [[ "$ACK_HASH_AFTER_RECV" != "$ACK_HASH_AFTER_DUPLICATE" ]]; then
  echo "FAIL: duplicate receive changed acknowledgement hash"
  echo "  after_recv=$ACK_HASH_AFTER_RECV"
  echo "  after_duplicate=$ACK_HASH_AFTER_DUPLICATE"
  exit 1
fi

echo "PASS: ETH -> Gno PacketRecv smoke"
