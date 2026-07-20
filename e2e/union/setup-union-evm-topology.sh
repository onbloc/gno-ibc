#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
voyager_container=${VOYAGER_CONTAINER:?set VOYAGER_CONTAINER}
union_container=${UNION_CONTAINER:?set UNION_CONTAINER}
union_core=${UNION_CORE_CONTRACT:?set UNION_CORE_CONTRACT}
union_zkgm=${UNION_ZKGM_CONTRACT:?set UNION_ZKGM_CONTRACT}
evm_handler=${EVM_IBC_HANDLER:?set EVM_IBC_HANDLER}
evm_zkgm=${EVM_ZKGM:?set EVM_ZKGM}
union_client=${UNION_EVM_CLIENT_ID:?set UNION_EVM_CLIENT_ID}
evm_client=${EVM_UNION_CLIENT_ID:?set EVM_UNION_CLIENT_ID}
union_chain_id=${UNION_CHAIN_ID:-union-devnet-1}
evm_chain_id=${EVM_CHAIN_ID:-32382}
evm_rpc=${EVM_RPC:-http://localhost:8545}
topology_env=${TOPOLOGY_ENV_FILE:-"$script_dir/union-evm-topology.env"}
version=ucs03-zkgm-0
evm_zkgm_lower=$(printf %s "$evm_zkgm" | tr '[:upper:]' '[:lower:]')

voyager() {
  docker exec "$voyager_container" ./voyager -c /config/voyager-config.gno-union.jsonc "$@"
}

union_query() {
  docker exec "$union_container" uniond query wasm contract-state smart "$union_core" "$1" \
    --node tcp://localhost:26657 -o json 2>/dev/null
}

find_union_connection() {
  local id=1 result
  while result=$(union_query "{\"get_connection\":{\"connection_id\":$id}}" ); do
    if jq -e --argjson local "$union_client" --argjson remote "$evm_client" \
      '.data.state == "open" and .data.client_id == $local and .data.counterparty_client_id == $remote' \
      <<<"$result" >/dev/null; then
      printf '%s\n' "$id"
      return
    fi
    ((id += 1))
  done
  return 1
}

find_evm_connection() {
  local id=1 result
  while result=$(cast call "$evm_handler" \
    'connections(uint32)(uint8,uint32,uint32,uint32)' "$id" --rpc-url "$evm_rpc" --json 2>/dev/null); do
    [[ $(jq -r '.[0] | tonumber' <<<"$result") -ne 0 ]] || break
    if jq -e --argjson local "$evm_client" --argjson remote "$union_client" \
      '(.[0] | tonumber) == 3 and (.[1] | tonumber) == $local and (.[2] | tonumber) == $remote' <<<"$result" >/dev/null; then
      printf '%s\n' "$id"
      return
    fi
    ((id += 1))
  done
  return 1
}

find_union_channel() {
  local connection=$1 id=1 result
  while result=$(union_query "{\"get_channel\":{\"channel_id\":$id}}" ); do
    if jq -e --argjson connection "$connection" --arg port "$evm_zkgm_lower" --arg version "$version" \
      '.data.state == "open" and .data.connection_id == $connection and
       (.data.counterparty_port_id | ascii_downcase) == $port and .data.version == $version' \
      <<<"$result" >/dev/null; then
      printf '%s\n' "$id"
      return
    fi
    ((id += 1))
  done
  return 1
}

find_evm_channel() {
  local connection=$1 id=1 result union_port_hex
  union_port_hex=0x$(printf %s "$union_zkgm" | od -An -tx1 | tr -d ' \n')
  while result=$(cast call "$evm_handler" \
    'channels(uint32)(uint8,uint32,uint32,bytes,string)' "$id" --rpc-url "$evm_rpc" --json 2>/dev/null); do
    [[ $(jq -r '.[0] | tonumber' <<<"$result") -ne 0 ]] || break
    if jq -e --argjson connection "$connection" --arg port "$union_port_hex" --arg version "$version" \
      '(.[0] | tonumber) == 3 and (.[1] | tonumber) == $connection and (.[3] | ascii_downcase) == $port and .[4] == $version' \
      <<<"$result" >/dev/null; then
      printf '%s\n' "$id"
      return
    fi
    ((id += 1))
  done
  return 1
}

wait_for() {
  local label=$1 finder=$2 deadline=$((SECONDS + 360)) value
  shift 2
  while ((SECONDS < deadline)); do
    if value=$($finder "$@"); then
      printf '%s\n' "$value"
      return
    fi
    sleep 2
  done
  echo "$label did not open within 360 seconds" >&2
  return 1
}

# Keep both event streams active before submitting the first handshake datagram.
voyager index "$union_chain_id" --enqueue >/dev/null
voyager index "$evm_chain_id" --enqueue >/dev/null

connection_op=$(jq -cn --arg chain "$union_chain_id" --argjson local "$union_client" --argjson remote "$evm_client" '
  {"@type":"call","@value":{"@type":"submit_tx","@value":{
    chain_id:$chain,datagrams:[{ibc_spec_id:"ibc-union",datagram:{
      "@type":"connection_open_init","@value":{client_id:$local,counterparty_client_id:$remote}
    }}]
  }}}')
voyager q e "$connection_op" >/dev/null

union_connection=$(wait_for 'Union connection' find_union_connection)
evm_connection=$(wait_for 'EVM connection' find_evm_connection)

union_port_hex=0x$(printf %s "$union_zkgm" | od -An -tx1 | tr -d ' \n')
channel_op=$(jq -cn \
  --arg chain "$union_chain_id" \
  --arg port "$union_port_hex" \
  --arg counterparty_port "$evm_zkgm_lower" \
  --arg version "$version" \
  --argjson connection "$union_connection" '
  {"@type":"call","@value":{"@type":"submit_tx","@value":{
    chain_id:$chain,datagrams:[{ibc_spec_id:"ibc-union",datagram:{
      "@type":"channel_open_init","@value":{
        port_id:$port,counterparty_port_id:$counterparty_port,
        connection_id:$connection,version:$version
      }
    }}]
  }}}')
voyager q e "$channel_op" >/dev/null

union_channel=$(wait_for 'Union channel' find_union_channel "$union_connection")
evm_channel=$(wait_for 'EVM channel' find_evm_channel "$evm_connection")

umask 077
{
  printf 'UNION_EVM_CONNECTION_ID=%s\n' "$union_connection"
  printf 'EVM_UNION_CONNECTION_ID=%s\n' "$evm_connection"
  printf 'UNION_EVM_CHANNEL_ID=%s\n' "$union_channel"
  printf 'EVM_UNION_CHANNEL_ID=%s\n' "$evm_channel"
} >"$topology_env"
echo "wrote live Union-EVM topology to $topology_env"
