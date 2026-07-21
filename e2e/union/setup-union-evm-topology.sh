#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
voyager_container=${VOYAGER_CONTAINER:?set VOYAGER_CONTAINER}
union_zkgm=${UNION_ZKGM_CONTRACT:?set UNION_ZKGM_CONTRACT}
evm_zkgm=${EVM_ZKGM:?set EVM_ZKGM}
union_client=${UNION_EVM_CLIENT_ID:?set UNION_EVM_CLIENT_ID}
evm_client=${EVM_UNION_CLIENT_ID:?set EVM_UNION_CLIENT_ID}
union_chain_id=${UNION_CHAIN_ID:-union-devnet-1}
evm_chain_id=${EVM_CHAIN_ID:-32382}
topology_env=${TOPOLOGY_ENV_FILE:-"$script_dir/union-evm-topology.env"}
version=ucs03-zkgm-0
evm_zkgm_lower=$(printf %s "$evm_zkgm" | tr '[:upper:]' '[:lower:]')

voyager() {
  docker exec "$voyager_container" ./voyager -c /config/voyager-config.gno-union.jsonc "$@"
}

# shellcheck source=voyager-topology.sh
source "$script_dir/voyager-topology.sh"

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

union_connection=$(wait_for 'Union connection' find_connection "$union_chain_id" "$union_client" "$evm_client")
evm_connection=$(wait_for 'EVM connection' find_connection "$evm_chain_id" "$evm_client" "$union_client")

union_connection_state=$(ibc_state "$union_chain_id" "{\"connection\":{\"connection_id\":$union_connection}}")
evm_connection_state=$(ibc_state "$evm_chain_id" "{\"connection\":{\"connection_id\":$evm_connection}}")
jq -e --argjson remote "$evm_connection" '.state.counterparty_connection_id == $remote' <<<"$union_connection_state" >/dev/null
jq -e --argjson remote "$union_connection" '.state.counterparty_connection_id == $remote' <<<"$evm_connection_state" >/dev/null

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

union_channel=$(wait_for 'Union channel' find_channel "$union_chain_id" "$union_connection" "$evm_zkgm_lower")
evm_channel=$(wait_for 'EVM channel' find_channel "$evm_chain_id" "$evm_connection" "$union_port_hex")

union_channel_state=$(ibc_state "$union_chain_id" "{\"channel\":{\"channel_id\":$union_channel}}")
evm_channel_state=$(ibc_state "$evm_chain_id" "{\"channel\":{\"channel_id\":$evm_channel}}")
jq -e --argjson remote "$evm_channel" '.state.counterparty_channel_id == $remote' <<<"$union_channel_state" >/dev/null
jq -e --argjson remote "$union_channel" '.state.counterparty_channel_id == $remote' <<<"$evm_channel_state" >/dev/null

umask 077
{
  printf 'UNION_EVM_CONNECTION_ID=%s\n' "$union_connection"
  printf 'EVM_UNION_CONNECTION_ID=%s\n' "$evm_connection"
  printf 'UNION_EVM_CHANNEL_ID=%s\n' "$union_channel"
  printf 'EVM_UNION_CHANNEL_ID=%s\n' "$evm_channel"
} >"$topology_env"
echo "wrote live Union-EVM topology to $topology_env"
