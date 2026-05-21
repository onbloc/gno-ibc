#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_command anvil
require_command cast
require_command solc
require_command jq
require_command go
require_command curl

trap cleanup_eth_gno_smoke_env EXIT
init_smoke_env
start_anvil

ETH_TO_GNO_TESTDATA_DIR="$ETH_GNO_TESTDATA_DIR/eth-to-gno"
OUTPUT_FIXTURE="${ETH_GNO_ETH_TO_GNO_FIXTURE:-$ETH_TO_GNO_TESTDATA_DIR/latest.json}"
COMMITMENT_PATH_HEX="${ETH_GNO_COMMITMENT_PATH_HEX:-0x472a9e75d39222a3bf79c3c11213f805e1268c67b038092c0eac21f1ad990409}"
COMMITMENT_VALUE_HEX="${ETH_GNO_COMMITMENT_VALUE_HEX:-0x0100000000000000000000000000000000000000000000000000000000000000}"

echo ">> compiling local CommitmentMap contract"
solc --bin --abi --overwrite -o "$WORKDIR/solc" "$ETH_TO_GNO_TESTDATA_DIR/CommitmentMap.sol" >"$WORKDIR/solc.log"
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

echo ">> writing packet commitment"
cast send --json --rpc-url "$ANVIL_RPC_URL" --private-key "$ANVIL_PRIVATE_KEY" \
  "$CONTRACT_ADDRESS" "set(bytes32,bytes32)" "$COMMITMENT_PATH_HEX" "$COMMITMENT_VALUE_HEX" >"$WORKDIR/set.json"

STORAGE_SLOT="$(cast index bytes32 "$COMMITMENT_PATH_HEX" 0)"
BLOCK_NUMBER_DEC="$(cast block-number --rpc-url "$ANVIL_RPC_URL")"
BLOCK_NUMBER_HEX="$(cast to-hex "$BLOCK_NUMBER_DEC")"

echo ">> fetching eth_getProof for $STORAGE_SLOT at block $BLOCK_NUMBER_DEC"
jq -n \
  --arg contract "$CONTRACT_ADDRESS" \
  --arg storage_slot "$STORAGE_SLOT" \
  --arg block_number "$BLOCK_NUMBER_HEX" \
  '{
    jsonrpc: "2.0",
    id: 1,
    method: "eth_getProof",
    params: [$contract, [$storage_slot], $block_number]
  }' >"$WORKDIR/get_proof_request.json"
curl -sf -H "content-type: application/json" \
  --data @"$WORKDIR/get_proof_request.json" \
  "$ANVIL_RPC_URL" >"$WORKDIR/get_proof.json"

go run "$ETH_GNO_SMOKE_DIR/encode-storage-proof.go" <"$WORKDIR/get_proof.json" >"$WORKDIR/encoded_proof.json"

STORAGE_ROOT="$(jq -r '.storage_hash' "$WORKDIR/encoded_proof.json")"
PROOF_BYTES_HEX="$(jq -r '.proof_bytes_hex' "$WORKDIR/encoded_proof.json")"
PROOF_NODE_COUNT="$(jq -r '.proof_node_count' "$WORKDIR/encoded_proof.json")"

mkdir -p "$(dirname "$OUTPUT_FIXTURE")"
jq -n \
  --arg contract "$CONTRACT_ADDRESS" \
  --arg commitment_path "$COMMITMENT_PATH_HEX" \
  --arg commitment_value "$COMMITMENT_VALUE_HEX" \
  --arg commitment_map_slot "0x0000000000000000000000000000000000000000000000000000000000000000" \
  --arg storage_slot "$STORAGE_SLOT" \
  --arg block_number "$BLOCK_NUMBER_HEX" \
  --arg storage_root "$STORAGE_ROOT" \
  --arg proof_bytes_hex "$PROOF_BYTES_HEX" \
  --argjson proof_node_count "$PROOF_NODE_COUNT" \
  '{
    commitment_path_hex: $commitment_path,
    commitment_value_hex: $commitment_value,
    eth: {
      contract: $contract,
      commitment_map_slot: $commitment_map_slot,
      block_number: $block_number,
      storage_root: $storage_root,
      storage_slot: $storage_slot
    },
    proof_node_count: $proof_node_count,
    proof_bytes_hex: $proof_bytes_hex
  }' >"$OUTPUT_FIXTURE"

echo "PASS: wrote ETH storage proof fixture to $OUTPUT_FIXTURE"
