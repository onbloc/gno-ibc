#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_command gnokey
require_command gnodev

trap cleanup_smoke_env EXIT
setup_smoke_chain

GNO_TO_ETH_TESTDATA_DIR="$ETH_GNO_TESTDATA_DIR/gno-to-eth"
OUTPUT_FIXTURE="${ETH_GNO_GNO_TO_ETH_FIXTURE:-$WORKDIR/gno-to-eth.json}"

echo ">> Gno -> ETH packet extraction smoke"
maketx_run "$GNO_TO_ETH_TESTDATA_DIR/send_packet.gno" "$WORKDIR/send_packet.log"

SOURCE_CHANNEL_ID="$(require_field source_channel_id "$WORKDIR/send_packet.log")"
DESTINATION_CHANNEL_ID="$(require_field destination_channel_id "$WORKDIR/send_packet.log")"
PACKET_DATA_HEX="$(require_field packet_data_hex "$WORKDIR/send_packet.log")"
TIMEOUT_TIMESTAMP="$(require_field timeout_timestamp "$WORKDIR/send_packet.log")"
PACKET_HASH="$(require_field packet_hash "$WORKDIR/send_packet.log")"
BATCH_HASH="$(require_field batch_hash "$WORKDIR/send_packet.log")"
BATCH_PATH_HEX="$(require_field batch_path_hex "$WORKDIR/send_packet.log")"
COMMITMENT_VALUE_HEX="$(require_field commitment_value_hex "$WORKDIR/send_packet.log")"

if [[ "$BATCH_HASH" != "$PACKET_HASH" ]]; then
  echo "FAIL: single-packet batch hash should match packet hash"
  echo "  packet_hash=$PACKET_HASH"
  echo "  batch_hash=$BATCH_HASH"
  exit 1
fi

if [[ "$COMMITMENT_VALUE_HEX" != "0x0100000000000000000000000000000000000000000000000000000000000000" ]]; then
  echo "FAIL: unexpected packet commitment value: $COMMITMENT_VALUE_HEX"
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_FIXTURE")"
cat >"$OUTPUT_FIXTURE" <<EOF
{
  "packet": {
    "source_channel_id": $SOURCE_CHANNEL_ID,
    "destination_channel_id": $DESTINATION_CHANNEL_ID,
    "data_hex": "$PACKET_DATA_HEX",
    "timeout_height": "0",
    "timeout_timestamp": "$TIMEOUT_TIMESTAMP"
  },
  "packet_hash": "$PACKET_HASH",
  "batch_hash": "$BATCH_HASH",
  "batch_path_hex": "$BATCH_PATH_HEX",
  "commitment_value_hex": "$COMMITMENT_VALUE_HEX",
  "proof_height": null,
  "proof": null
}
EOF

echo "PASS: wrote Gno -> ETH fixture to $OUTPUT_FIXTURE"
