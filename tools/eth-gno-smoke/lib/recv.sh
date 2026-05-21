#!/usr/bin/env bash
# recv.sh — shared ETH -> Gno receive proof derivation helpers.

derive_recv_proof_inputs() {
  local input_log="$1"

  CONN_ACK_PATH="$(require_field conn_ack_path "$input_log")"
  CONN_ACK_VALUE="$(require_field conn_ack_value "$input_log")"
  CHANNEL_ACK_PATH="$(require_field channel_ack_path "$input_log")"
  CHANNEL_ACK_VALUE="$(require_field channel_ack_value "$input_log")"
  PACKET_PATH="$(require_field packet_path "$input_log")"
  PACKET_VALUE="$(require_field packet_value "$input_log")"
  PACKET_DATA_HEX="$(require_field packet_data_hex "$input_log")"
  PACKET_TIMEOUT_TIMESTAMP="$(require_field packet_timeout_timestamp "$input_log")"
}

recv_commitments_json() {
  local packet_value="${1:-$PACKET_VALUE}"

  jq -n \
    --arg conn_path "$CONN_ACK_PATH" \
    --arg conn_value "$CONN_ACK_VALUE" \
    --arg channel_path "$CHANNEL_ACK_PATH" \
    --arg channel_value "$CHANNEL_ACK_VALUE" \
    --arg packet_path "$PACKET_PATH" \
    --arg packet_value "$packet_value" \
    '[
      {name: "conn_ack", path_hex: $conn_path, value_hex: $conn_value},
      {name: "channel_ack", path_hex: $channel_path, value_hex: $channel_value},
      {name: "packet", path_hex: $packet_path, value_hex: $packet_value}
    ]'
}

generate_recv_proof_fixture() {
  local output_fixture="$1"
  local commitments_json="$2"

  ETH_GNO_COMMITMENTS_JSON="$commitments_json" \
  ETH_GNO_ETH_TO_GNO_FIXTURE="$output_fixture" \
    "$ETH_GNO_SMOKE_DIR/scenarios/eth-proof/run.sh"
}

load_recv_proof_fixture() {
  local output_fixture="$1"

  STORAGE_ROOT="$(jq -r '.eth.storage_root' "$output_fixture")"
  CONN_ACK_PROOF="$(jq -r '.proofs.conn_ack.proof_bytes_hex' "$output_fixture")"
  CHANNEL_ACK_PROOF="$(jq -r '.proofs.channel_ack.proof_bytes_hex' "$output_fixture")"
  PACKET_PROOF="$(jq -r '.proofs.packet.proof_bytes_hex' "$output_fixture")"
}
