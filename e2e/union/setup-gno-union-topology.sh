#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
voyager_container=${VOYAGER_CONTAINER:?set VOYAGER_CONTAINER}
union_zkgm=${UNION_ZKGM_CONTRACT:?set UNION_ZKGM_CONTRACT}
gno_client=${GNO_CLIENT_ID:?set GNO_CLIENT_ID}
union_client=${UNION_GNO_CLIENT_ID:?set UNION_GNO_CLIENT_ID}
gno_chain_id=${GNO_CHAIN_ID:-dev}
union_chain_id=${UNION_CHAIN_ID:-union-devnet-1}
topology_env=${TOPOLOGY_ENV_FILE:-"$script_dir/gno-union-topology.env"}
gno_port=gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm
version=ucs03-zkgm-0

voyager() {
  docker exec "$voyager_container" ./voyager -c /config/voyager-config.gno-union.jsonc "$@"
}

# shellcheck source=voyager-topology.sh
source "$script_dir/voyager-topology.sh"

voyager index "$gno_chain_id" --enqueue >/dev/null
voyager index "$union_chain_id" --enqueue >/dev/null

connection_op=$(jq -cn --arg chain "$union_chain_id" --argjson local "$union_client" --argjson remote "$gno_client" '
  {"@type":"call","@value":{"@type":"submit_tx","@value":{
    chain_id:$chain,datagrams:[{ibc_spec_id:"ibc-union",datagram:{
      "@type":"connection_open_init","@value":{client_id:$local,counterparty_client_id:$remote}
    }}]
  }}}')
voyager q e "$connection_op" >/dev/null

union_connection=$(wait_for 'Union connection' find_connection "$union_chain_id" "$union_client" "$gno_client")
gno_connection=$(wait_for 'Gno connection' find_connection "$gno_chain_id" "$gno_client" "$union_client")

union_connection_state=$(ibc_state "$union_chain_id" "{\"connection\":{\"connection_id\":$union_connection}}")
gno_connection_state=$(ibc_state "$gno_chain_id" "{\"connection\":{\"connection_id\":$gno_connection}}")
jq -e --argjson remote "$gno_connection" '.state.counterparty_connection_id == $remote' <<<"$union_connection_state" >/dev/null
jq -e --argjson remote "$union_connection" '.state.counterparty_connection_id == $remote' <<<"$gno_connection_state" >/dev/null

union_port_hex=0x$(printf %s "$union_zkgm" | od -An -tx1 | tr -d ' \n')
gno_port_hex=0x$(printf %s "$gno_port" | od -An -tx1 | tr -d ' \n')
channel_op=$(jq -cn \
  --arg chain "$union_chain_id" \
  --arg port "$union_port_hex" \
  --arg counterparty_port "$gno_port_hex" \
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

union_channel=$(wait_for 'Union channel' find_channel "$union_chain_id" "$union_connection" "$gno_port_hex")
gno_channel=$(wait_for 'Gno channel' find_channel "$gno_chain_id" "$gno_connection" "$union_port_hex")

union_channel_state=$(ibc_state "$union_chain_id" "{\"channel\":{\"channel_id\":$union_channel}}")
gno_channel_state=$(ibc_state "$gno_chain_id" "{\"channel\":{\"channel_id\":$gno_channel}}")
jq -e --argjson remote "$gno_channel" '.state.counterparty_channel_id == $remote' <<<"$union_channel_state" >/dev/null
jq -e --argjson remote "$union_channel" '.state.counterparty_channel_id == $remote' <<<"$gno_channel_state" >/dev/null

umask 077
{
  printf 'GNO_CLIENT_ID=%s\n' "$gno_client"
  printf 'UNION_GNO_CLIENT_ID=%s\n' "$union_client"
  printf 'GNO_PACKET_CONNECTION_ID=%s\n' "$gno_connection"
  printf 'UNION_PACKET_CONNECTION_ID=%s\n' "$union_connection"
  printf 'GNO_PACKET_CHANNEL_ID=%s\n' "$gno_channel"
  printf 'UNION_PACKET_CHANNEL_ID=%s\n' "$union_channel"
} >"$topology_env"
echo "wrote live Gno-Union topology to $topology_env"
