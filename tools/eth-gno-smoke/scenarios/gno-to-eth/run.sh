#!/usr/bin/env bash
set -euo pipefail

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ETH_GNO_SMOKE_DIR="$(cd "$SCENARIO_DIR/../.." && pwd)"
source "$ETH_GNO_SMOKE_DIR/lib/env.sh"
source "$ETH_GNO_SMOKE_DIR/lib/log.sh"
source "$ETH_GNO_SMOKE_DIR/lib/gno.sh"

require_command gnokey
require_command gnodev
require_command curl
require_command jq
require_command xxd

trap cleanup_eth_gno_smoke_env EXIT
setup_smoke_chain

OUTPUT_FIXTURE="${ETH_GNO_GNO_TO_ETH_FIXTURE:-$SCENARIO_DIR/fixture.json}"

echo ">> Gno -> ETH packet extraction smoke"
maketx_run "$SCENARIO_DIR/send_packet.gno" "$WORKDIR/send_packet.log"

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

if [[ "$COMMITMENT_VALUE_HEX" != "$ETH_GNO_COMMITMENT_MAGIC_HEX" ]]; then
  echo "FAIL: unexpected packet commitment value: $COMMITMENT_VALUE_HEX"
  exit 1
fi

echo ">> Gno -> ETH commitment store proof"
fetch_gno_store_proof "$BATCH_PATH_HEX" "$WORKDIR/gno_store_proof.json"
if jq -e '.error // empty' "$WORKDIR/gno_store_proof.json" >/dev/null; then
  echo "FAIL: ABCI proof query failed"
  cat "$WORKDIR/gno_store_proof.json"
  exit 1
fi
PROOF_HEIGHT="$(jq -r '.result.response.Height // .result.response.height' "$WORKDIR/gno_store_proof.json")"
PROOF_VALUE_BASE64="$(jq -r '.result.response.Value // .result.response.value // empty' "$WORKDIR/gno_store_proof.json")"
PROOF_OPS_JSON="$(jq -c '.result.response.Proof // .result.response.proofOps // .result.response.proof_ops // null' "$WORKDIR/gno_store_proof.json")"
if [[ -z "$PROOF_HEIGHT" || "$PROOF_HEIGHT" == "null" || -z "$PROOF_VALUE_BASE64" || "$PROOF_OPS_JSON" == "null" ]]; then
  echo "FAIL: ABCI proof response missing height, value, or proof ops"
  cat "$WORKDIR/gno_store_proof.json"
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_FIXTURE")"
jq -n \
  --argjson source_channel_id "$SOURCE_CHANNEL_ID" \
  --argjson destination_channel_id "$DESTINATION_CHANNEL_ID" \
  --arg packet_data_hex "$PACKET_DATA_HEX" \
  --arg timeout_timestamp "$TIMEOUT_TIMESTAMP" \
  --arg packet_hash "$PACKET_HASH" \
  --arg batch_hash "$BATCH_HASH" \
  --arg batch_path_hex "$BATCH_PATH_HEX" \
  --arg commitment_value_hex "$COMMITMENT_VALUE_HEX" \
  --argjson proof_height "$PROOF_HEIGHT" \
  --arg proof_value_base64 "$PROOF_VALUE_BASE64" \
  --argjson proof "$PROOF_OPS_JSON" \
  '{
    packet: {
      source_channel_id: $source_channel_id,
      destination_channel_id: $destination_channel_id,
      data_hex: $packet_data_hex,
      timeout_height: "0",
      timeout_timestamp: $timeout_timestamp
    },
    packet_hash: $packet_hash,
    batch_hash: $batch_hash,
    batch_path_hex: $batch_path_hex,
    commitment_value_hex: $commitment_value_hex,
    proof_height: $proof_height,
    proof_value_base64: $proof_value_base64,
    proof: $proof
  }' >"$OUTPUT_FIXTURE"

echo "PASS: wrote Gno -> ETH fixture to $OUTPUT_FIXTURE"
