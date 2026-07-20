#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
voyager_container=${VOYAGER_CONTAINER:?set VOYAGER_CONTAINER}
gno_container=${GNO_CONTAINER:?set GNO_CONTAINER}
union_container=${UNION_CONTAINER:?set UNION_CONTAINER}
union_core=${UNION_CORE_CONTRACT:?set UNION_CORE_CONTRACT}
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

union_query() {
  docker exec "$union_container" uniond query wasm contract-state smart "$union_core" "$1" \
    --node tcp://localhost:26657 -o json 2>/dev/null
}

gno_query_string() {
  local output
  output=$(docker exec "$gno_container" gnokey query vm/qeval -remote localhost:26657 -data "$1" 2>&1)
  sed -n 's/.*("\([^"]*\)" string).*/\1/p' <<<"$output"
}

latest_gno_id() {
  local query=$1 id=1
  while [[ -n $(gno_query_string "gno.land/r/onbloc/ibc/union/core.$query($id)") ]]; do
    ((id += 1))
  done
  echo $((id - 1))
}

find_union_connection() {
  local id=1 result
  while result=$(union_query "{\"get_connection\":{\"connection_id\":$id}}" ); do
    if jq -e --argjson local "$union_client" --argjson remote "$gno_client" \
      '.data.state == "open" and .data.client_id == $local and .data.counterparty_client_id == $remote' \
      <<<"$result" >/dev/null; then
      echo "$id"
      return
    fi
    ((id += 1))
  done
  return 1
}

find_union_channel() {
  local connection=$1 id=1 result
  while result=$(union_query "{\"get_channel\":{\"channel_id\":$id}}" ); do
    if jq -e --argjson connection "$connection" --arg version "$version" \
      '.data.state == "open" and .data.connection_id == $connection and .data.version == $version' \
      <<<"$result" >/dev/null; then
      echo "$id"
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
      echo "$value"
      return
    fi
    sleep 2
  done
  echo "$label did not open within 360 seconds" >&2
  return 1
}

wait_gno_open() {
  local label=$1 query=$2 before=$3 deadline=$((SECONDS + 360)) id state
  while ((SECONDS < deadline)); do
    id=$(latest_gno_id "$query")
    if ((id > before)); then
      state=$(gno_query_string "gno.land/r/onbloc/ibc/union/core.${query}State($id)")
      if [[ $state == 3 ]]; then
        echo "$id"
        return
      fi
    fi
    sleep 2
  done
  echo "$label did not open within 360 seconds" >&2
  return 1
}

voyager index "$gno_chain_id" --enqueue >/dev/null
voyager index "$union_chain_id" --enqueue >/dev/null

gno_connection_before=$(latest_gno_id QueryConnection)
connection_op=$(jq -cn --arg chain "$union_chain_id" --argjson local "$union_client" --argjson remote "$gno_client" '
  {"@type":"call","@value":{"@type":"submit_tx","@value":{
    chain_id:$chain,datagrams:[{ibc_spec_id:"ibc-union",datagram:{
      "@type":"connection_open_init","@value":{client_id:$local,counterparty_client_id:$remote}
    }}]
  }}}')
voyager q e "$connection_op" >/dev/null

union_connection=$(wait_for 'Union connection' find_union_connection)
gno_connection=$(wait_gno_open 'Gno connection' QueryConnection "$gno_connection_before")

gno_channel_before=$(latest_gno_id QueryChannel)
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

union_channel=$(wait_for 'Union channel' find_union_channel "$union_connection")
gno_channel=$(wait_gno_open 'Gno channel' QueryChannel "$gno_channel_before")

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
