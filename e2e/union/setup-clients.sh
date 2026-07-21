#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
compose_project=${COMPOSE_PROJECT_NAME:?set COMPOSE_PROJECT_NAME}
voyager_container=${VOYAGER_CONTAINER:?set VOYAGER_CONTAINER}
union_container=${UNION_CONTAINER:?set UNION_CONTAINER}
union_core=${UNION_CORE_CONTRACT:?set UNION_CORE_CONTRACT}
gno_chain_id=${GNO_CHAIN_ID:-dev}
union_chain_id=${UNION_CHAIN_ID:-union-devnet-1}
evm_chain_id=${EVM_CHAIN_ID:-32382}
evm_ibc_handler=${EVM_IBC_HANDLER:?set EVM_IBC_HANDLER}
evm_rpc=${EVM_RPC:-http://localhost:8545}
clients_env=${CLIENTS_ENV_FILE:-"$script_dir/clients.env"}

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

ensure_client() {
  local finder=$1 wanted=$2
  shift 2
  local id
  id=$($finder "$wanted")
  if [[ $id -eq 0 ]]; then
    voyager msg create-client "$@" --ibc-spec-id ibc-union --client-type "$wanted" --height finalized --enqueue >/dev/null
    id=$(wait_client "$finder" "$wanted") || return
  fi
  echo "$id"
}

for chain in "$union_chain_id" "$gno_chain_id" "$evm_chain_id"; do
  wait_rpc "$chain"
done

gno_client_id=$(ensure_client gno_client cometbls \
  --on "$gno_chain_id" --tracking "$union_chain_id" --ibc-interface ibc-gno)
union_gno_client_id=$(ensure_client union_client gno \
  --on "$union_chain_id" --tracking "$gno_chain_id" --ibc-interface ibc-cosmwasm)
union_evm_client_id=$(ensure_client union_client trusted/evm/mpt \
  --on "$union_chain_id" --tracking "$evm_chain_id" --ibc-interface ibc-cosmwasm)
evm_union_client_id=$(ensure_client evm_client cometbls \
  --on "$evm_chain_id" --tracking "$union_chain_id" --ibc-interface ibc-solidity)

umask 077
{
  printf 'GNO_CLIENT_ID=%s\n' "$gno_client_id"
  printf 'UNION_GNO_CLIENT_ID=%s\n' "$union_gno_client_id"
  printf 'UNION_EVM_CLIENT_ID=%s\n' "$union_evm_client_id"
  printf 'EVM_UNION_CLIENT_ID=%s\n' "$evm_union_client_id"
} >"$clients_env"
echo "wrote live client IDs to $clients_env"
