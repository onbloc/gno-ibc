#!/usr/bin/env bash
set -euo pipefail

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ETH_GNO_SMOKE_DIR="$(cd "$SCENARIO_DIR/../.." && pwd)"
source "$ETH_GNO_SMOKE_DIR/lib/env.sh"
source "$ETH_GNO_SMOKE_DIR/lib/eth.sh"

require_command anvil
require_command cast
require_command solc
require_command jq
require_command go
require_command curl

trap cleanup_eth_gno_smoke_env EXIT
init_smoke_env
start_anvil

OUTPUT_FIXTURE="${ETH_GNO_ETH_TO_GNO_FIXTURE:-$SCENARIO_DIR/fixture.json}"
COMMITMENT_PATH_HEX="${ETH_GNO_COMMITMENT_PATH_HEX:-0x472a9e75d39222a3bf79c3c11213f805e1268c67b038092c0eac21f1ad990409}"
COMMITMENT_VALUE_HEX="${ETH_GNO_COMMITMENT_VALUE_HEX:-$ETH_GNO_COMMITMENT_MAGIC_HEX}"
COMMITMENTS_JSON="${ETH_GNO_COMMITMENTS_JSON:-}"
if [[ -z "$COMMITMENTS_JSON" ]]; then
  COMMITMENTS_JSON="$(jq -n \
    --arg path "$COMMITMENT_PATH_HEX" \
    --arg value "$COMMITMENT_VALUE_HEX" \
    '[{name: "packet", path_hex: $path, value_hex: $value}]')"
fi

echo ">> compiling local CommitmentMap contract"
solc --bin --abi --overwrite -o "$WORKDIR/solc" "$SCENARIO_DIR/CommitmentMap.sol" >"$WORKDIR/solc.log"
CONTRACT_BIN="$(tr -d '\n' <"$WORKDIR/solc/CommitmentMap.bin")"
if [[ -z "$CONTRACT_BIN" ]]; then
  echo "FAIL: solc did not produce CommitmentMap bytecode"
  cat "$WORKDIR/solc.log"
  exit 1
fi

echo ">> deploying CommitmentMap"
cast send --json --rpc-url "$ANVIL_RPC_URL" --private-key "$ANVIL_PRIVATE_KEY" \
  --create "0x$CONTRACT_BIN" >"$WORKDIR/deploy.json"
CONTRACT_ADDRESS="$(jq -r '.contractAddress // empty' "$WORKDIR/deploy.json")"
if [[ -z "$CONTRACT_ADDRESS" ]]; then
  echo "FAIL: could not capture deployed contract address"
  cat "$WORKDIR/deploy.json"
  exit 1
fi

echo ">> writing packet commitments"
while IFS= read -r commitment; do
  NAME="$(jq -r '.name' <<<"$commitment")"
  PATH_HEX="$(jq -r '.path_hex' <<<"$commitment")"
  VALUE_HEX="$(jq -r '.value_hex' <<<"$commitment")"
  cast send --json --rpc-url "$ANVIL_RPC_URL" --private-key "$ANVIL_PRIVATE_KEY" \
    "$CONTRACT_ADDRESS" "set(bytes32,bytes32)" "$PATH_HEX" "$VALUE_HEX" >"$WORKDIR/set_$NAME.json"
done < <(jq -c '.[]' <<<"$COMMITMENTS_JSON")

BLOCK_NUMBER_DEC="$(cast block-number --rpc-url "$ANVIL_RPC_URL")"
BLOCK_NUMBER_HEX="$(cast to-hex "$BLOCK_NUMBER_DEC")"

echo ">> building storage proof encoder"
ENCODER_BIN="$WORKDIR/encode-storage-proof"
(cd "$ETH_GNO_SMOKE_DIR" && go build -o "$ENCODER_BIN" ./cmd/encode-storage-proof)

echo ">> fetching eth_getProof at block $BLOCK_NUMBER_DEC"
: >"$WORKDIR/proofs.jsonl"
while IFS= read -r commitment; do
  NAME="$(jq -r '.name' <<<"$commitment")"
  PATH_HEX="$(jq -r '.path_hex' <<<"$commitment")"
  VALUE_HEX="$(jq -r '.value_hex' <<<"$commitment")"
  STORAGE_SLOT="$(cast index bytes32 "$PATH_HEX" 0)"

  jq -n \
    --arg contract "$CONTRACT_ADDRESS" \
    --arg storage_slot "$STORAGE_SLOT" \
    --arg block_number "$BLOCK_NUMBER_HEX" \
    '{
      jsonrpc: "2.0",
      id: 1,
      method: "eth_getProof",
      params: [$contract, [$storage_slot], $block_number]
    }' >"$WORKDIR/get_proof_request_$NAME.json"
  curl -sf -H "content-type: application/json" \
    --data @"$WORKDIR/get_proof_request_$NAME.json" \
    "$ANVIL_RPC_URL" >"$WORKDIR/get_proof_$NAME.json"
  "$ENCODER_BIN" <"$WORKDIR/get_proof_$NAME.json" >"$WORKDIR/encoded_proof_$NAME.json"

  jq -n \
    --arg name "$NAME" \
    --arg path "$PATH_HEX" \
    --arg value "$VALUE_HEX" \
    --arg storage_slot "$STORAGE_SLOT" \
    --slurpfile encoded "$WORKDIR/encoded_proof_$NAME.json" \
    '{
      key: $name,
      value: {
        commitment_path_hex: $path,
        commitment_value_hex: $value,
        storage_slot: $storage_slot,
        proof_node_count: $encoded[0].proof_node_count,
        proof_bytes_hex: $encoded[0].proof_bytes_hex
      }
    }' >>"$WORKDIR/proofs.jsonl"
done < <(jq -c '.[]' <<<"$COMMITMENTS_JSON")

STORAGE_ROOT="$(jq -r '.storage_hash' "$WORKDIR/encoded_proof_$(jq -r '.[0].name' <<<"$COMMITMENTS_JSON").json")"
PROOFS_JSON="$(jq -s 'map({(.key): .value}) | add' "$WORKDIR/proofs.jsonl")"
FIRST_NAME="$(jq -r '.[0].name' <<<"$COMMITMENTS_JSON")"
FIRST_PROOF="$(jq -c --arg name "$FIRST_NAME" '.[$name]' <<<"$PROOFS_JSON")"

mkdir -p "$(dirname "$OUTPUT_FIXTURE")"
jq -n \
  --arg contract "$CONTRACT_ADDRESS" \
  --arg commitment_map_slot "0x0000000000000000000000000000000000000000000000000000000000000000" \
  --arg block_number "$BLOCK_NUMBER_HEX" \
  --arg storage_root "$STORAGE_ROOT" \
  --argjson proofs "$PROOFS_JSON" \
  --argjson first_proof "$FIRST_PROOF" \
  '{
    commitment_path_hex: $first_proof.commitment_path_hex,
    commitment_value_hex: $first_proof.commitment_value_hex,
    eth: {
      contract: $contract,
      commitment_map_slot: $commitment_map_slot,
      block_number: $block_number,
      storage_root: $storage_root,
      storage_slot: $first_proof.storage_slot
    },
    proof_node_count: $first_proof.proof_node_count,
    proof_bytes_hex: $first_proof.proof_bytes_hex,
    proofs: $proofs
  }' >"$OUTPUT_FIXTURE"

echo "PASS: wrote ETH storage proof fixture to $OUTPUT_FIXTURE"
