#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
compose_project=${COMPOSE_PROJECT_NAME:?set COMPOSE_PROJECT_NAME}
voyager_container=${VOYAGER_CONTAINER:?set VOYAGER_CONTAINER}
union_container=${UNION_CONTAINER:?set UNION_CONTAINER}
union_core=${UNION_CORE_CONTRACT:?set UNION_CORE_CONTRACT}
gno_chain_id=${GNO_CHAIN_ID:-dev}
union_chain_id=${UNION_CHAIN_ID:-union-devnet-1}
evm_chain_id=${EVM_CHAIN_ID:?set EVM_CHAIN_ID}
evm_ibc_handler=${EVM_IBC_HANDLER:?set EVM_IBC_HANDLER}
evm_rpc=${EVM_RPC:-http://localhost:8545}
clients_env=${CLIENTS_ENV_FILE:-"$script_dir/clients.env"}

require_positive_decimal() {
  [[ $2 =~ ^[1-9][0-9]*$ ]] || { echo "$1 must be a positive decimal integer" >&2; exit 2; }
}

require_positive_decimal EVM_CHAIN_ID "$evm_chain_id"
[[ $evm_ibc_handler =~ ^0x[0-9a-fA-F]{40}$ ]] || {
  echo "EVM_IBC_HANDLER must be a 20-byte hex address" >&2
  exit 2
}

compose() {
  docker compose \
    --project-name "$compose_project" \
    --project-directory "$script_dir" \
    --file "$script_dir/docker-compose.yml" \
    --env-file "$script_dir/../../.gno-version" \
    --env-file "$script_dir/.env.example" \
    "$@"
}

voyager() {
  docker exec "$voyager_container" ./voyager -c /config/voyager-config.gno-union.jsonc "$@"
}

union_client() {
  local wanted=$1 id=1 value found=0
  while value=$(docker exec "$union_container" uniond query wasm contract-state smart "$union_core" \
    "{\"get_client_type\":{\"client_id\":$id}}" --node tcp://localhost:26657 -o json 2>/dev/null); do
    [[ $(jq -r '.data // empty' <<<"$value") == "$wanted" ]] && found=$id
    ((id += 1))
  done
  echo "$found"
}

evm_client() {
  local wanted=$1 id=1 value found=0
  while value=$(cast call "$evm_ibc_handler" 'clientTypes(uint32)(string)' "$id" --rpc-url "$evm_rpc" 2>/dev/null); do
    value=${value#\"}
    value=${value%\"}
    [[ -n $value ]] || break
    [[ $value == "$wanted" ]] && found=$id
    ((id += 1))
  done
  echo "$found"
}

gno_client() {
  local wanted=$1 output
  output=$(compose --profile setup run --rm --no-deps \
    -e TOPOLOGY_ACTION=discover-client -e "CLIENT_TYPE=$wanted" gno-admin-recovery 2>/dev/null || true)
  sed -n 's/^GNO_CLIENT_ID=//p' <<<"$output" | tail -n 1
}

wait_client() {
  local finder=$1 wanted=$2 deadline=$((SECONDS + 180)) id
  while ((SECONDS < deadline)); do
    id=$($finder "$wanted")
    if [[ $id -gt 0 ]]; then
      echo "$id"
      return
    fi
    sleep 2
  done
  echo "$wanted client was not created within 180 seconds" >&2
  return 1
}

wait_rpc() {
  local chain=$1 deadline=$((SECONDS + 180))
  until voyager rpc latest-height "$chain" --finalized >/dev/null 2>&1; do
    ((SECONDS < deadline)) || { echo "$chain finalized height was not ready within 180 seconds" >&2; return 1; }
    sleep 2
  done
}

latest_height() {
  voyager rpc latest-height "$1" --finalized | jq -r 'if type == "object" then (.height // .revision_height) else . end'
}

wait_consensus_state() {
  local chain=$1 client=$2 height=$3 deadline=$((SECONDS + 360))
  until has_finalized_consensus_state "$chain" "$client" "$height"; do
    ((SECONDS < deadline)) || {
      echo "$chain client $client has no consensus state at $height after 360 seconds" >&2
      return 1
    }
    sleep 2
  done
}

wait_finalized_client_state() {
  local chain=$1 client=$2 deadline=$((SECONDS + 360)) host_height
  while ((SECONDS < deadline)); do
    host_height=$(latest_height "$chain") || true
    # Query latest first: the EVM state module caches client implementations by ID.
    if [[ -n $host_height ]] &&
      voyager rpc client-meta "$chain" "$client" 2>/dev/null |
        jq -e '(.counterparty_chain_id // "") != "" and ((.counterparty_height // "0") | tostring) != "0"' >/dev/null &&
      voyager rpc client-meta "$chain" "$client" --height "$host_height" 2>/dev/null |
        jq -e '(.counterparty_chain_id // "") != "" and ((.counterparty_height // "0") | tostring) != "0"' >/dev/null; then
      return
    fi
    sleep 2
  done
  echo "$chain client $client was not visible at a finalized height after 360 seconds" >&2
  return 1
}

has_finalized_consensus_state() {
  local host_height
  host_height=$(latest_height "$1") || return
  voyager rpc consensus-meta "$1" "$2" "$3" --height "$host_height" 2>/dev/null |
    jq -e '(.timestamp // 0) != 0' >/dev/null
}

ensure_consensus_state() {
  local chain=$1 client=$2 height=$3 op
  echo "ensuring $chain client $client consensus at $height is finalized" >&2
  wait_finalized_client_state "$chain" "$client"
  if ! has_finalized_consensus_state "$chain" "$client" "$height"; then
    op=$(voyager msg update-client "$chain" "$client" --update-to "$height")
    voyager queue enqueue "$op" >/dev/null
    wait_consensus_state "$chain" "$client" "$height"
  fi
}

ensure_client() {
  local finder=$1 wanted=$2
  shift 2
  local id arg has_height=0
  local -a args=("$@")
  for arg in "${args[@]}"; do
    [[ $arg == --height ]] && has_height=1
  done
  ((has_height)) || args+=(--height finalized)
  id=$($finder "$wanted")
  if [[ $id -eq 0 ]]; then
    echo "creating $wanted client" >&2
    voyager msg create-client "${args[@]}" --ibc-spec-id ibc-union --client-type "$wanted" --enqueue >/dev/null
    id=$(wait_client "$finder" "$wanted") || return
  fi
  echo "$id"
}

require_client_info() {
  local chain=$1 id=$2 type=$3 interface=$4 info
  info=$(voyager rpc client-info "$chain" "$id")
  jq -e --arg type "$type" --arg interface "$interface" \
    '.client_type == $type and .ibc_interface == $interface' <<<"$info" >/dev/null || {
    echo "$chain client $id differs: $info" >&2
    return 1
  }
}

for chain in "$union_chain_id" "$gno_chain_id" "$evm_chain_id"; do
  wait_rpc "$chain"
done

gno_client_id=$(ensure_client gno_client cometbls \
  --on "$gno_chain_id" --tracking "$union_chain_id" --ibc-interface ibc-gno)
require_positive_decimal GNO_CLIENT_ID "$gno_client_id"
union_gno_client_id=$(ensure_client union_client gno \
  --on "$union_chain_id" --tracking "$gno_chain_id" --ibc-interface ibc-cosmwasm)
require_positive_decimal UNION_GNO_CLIENT_ID "$union_gno_client_id"
union_evm_client_id=$(ensure_client union_client trusted/evm/mpt \
  --on "$union_chain_id" --tracking "$evm_chain_id" --ibc-interface ibc-cosmwasm)
require_positive_decimal UNION_EVM_CLIENT_ID "$union_evm_client_id"
evm_union_client_id=$(ensure_client evm_client cometbls \
  --on "$evm_chain_id" --tracking "$union_chain_id" --ibc-interface ibc-solidity)
require_positive_decimal EVM_UNION_CLIENT_ID "$evm_union_client_id"

# Lens bootstrap reads the L2 consensus state through the L1 client, so pin
# both L2 heights first and then advance both clients that track Union.
gno_lens_height=$(latest_height "$gno_chain_id")
evm_lens_height=$(latest_height "$evm_chain_id")
ensure_consensus_state "$union_chain_id" "$union_gno_client_id" "$gno_lens_height"
ensure_consensus_state "$union_chain_id" "$union_evm_client_id" "$evm_lens_height"
union_lens_height=$(latest_height "$union_chain_id")
ensure_consensus_state "$evm_chain_id" "$evm_union_client_id" "$union_lens_height"
ensure_consensus_state "$gno_chain_id" "$gno_client_id" "$union_lens_height"

[[ $evm_union_client_id == 1 ]] || {
  echo "EVM cometbls client is $evm_union_client_id, but Voyager config assigns client 1 to the regular batcher" >&2
  exit 1
}

proof_lens_config=$(jq -cn \
  --arg host "$evm_chain_id" \
  --argjson l1 "$evm_union_client_id" \
  --argjson l2 "$union_gno_client_id" \
  '{host_chain_id:$host,l1_client_id:$l1,l2_client_id:$l2,timestamp_offset:24}')
echo "bootstrapping EVM proof-lens through EVM client $evm_union_client_id and Union client $union_gno_client_id" >&2
evm_gno_client_id=$(ensure_client evm_client proof-lens \
  --on "$evm_chain_id" --tracking "$gno_chain_id" --ibc-interface ibc-solidity \
  --config "$proof_lens_config" --height "$gno_lens_height")
require_positive_decimal EVM_GNO_CLIENT_ID "$evm_gno_client_id"

state_lens_config=$(jq -cn \
  --arg host "$gno_chain_id" \
  --argjson l1 "$gno_client_id" \
  --argjson l2 "$union_evm_client_id" \
  '{host_chain_id:$host,l1_client_id:$l1,l2_client_id:$l2,timestamp_offset:88,state_root_offset:0,storage_root_offset:32}')
echo "bootstrapping Gno state-lens through Gno client $gno_client_id and Union client $union_evm_client_id" >&2
gno_evm_client_id=$(ensure_client gno_client state-lens/ics23/mpt \
  --on "$gno_chain_id" --tracking "$evm_chain_id" --ibc-interface ibc-gno \
  --config "$state_lens_config" --height "$evm_lens_height")
require_positive_decimal GNO_EVM_CLIENT_ID "$gno_evm_client_id"

[[ $evm_gno_client_id == 2 ]] || {
  echo "EVM proof-lens client is $evm_gno_client_id, but Voyager config assigns client 2 to the Proof Lens batcher" >&2
  exit 1
}

require_client_info "$gno_chain_id" "$gno_client_id" cometbls ibc-gno
require_client_info "$union_chain_id" "$union_gno_client_id" gno ibc-cosmwasm
require_client_info "$union_chain_id" "$union_evm_client_id" trusted/evm/mpt ibc-cosmwasm
require_client_info "$evm_chain_id" "$evm_union_client_id" cometbls ibc-solidity
require_client_info "$evm_chain_id" "$evm_gno_client_id" proof-lens ibc-solidity
require_client_info "$gno_chain_id" "$gno_evm_client_id" state-lens/ics23/mpt ibc-gno

umask 077
{
  printf 'GNO_CLIENT_ID=%s\n' "$gno_client_id"
  printf 'UNION_GNO_CLIENT_ID=%s\n' "$union_gno_client_id"
  printf 'UNION_EVM_CLIENT_ID=%s\n' "$union_evm_client_id"
  printf 'EVM_UNION_CLIENT_ID=%s\n' "$evm_union_client_id"
  printf 'GNO_EVM_CLIENT_ID=%s\n' "$gno_evm_client_id"
  printf 'EVM_GNO_CLIENT_ID=%s\n' "$evm_gno_client_id"
} >"$clients_env"
echo "wrote live client IDs to $clients_env"
