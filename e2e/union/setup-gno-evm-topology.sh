#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
voyager_container=${VOYAGER_CONTAINER:?set VOYAGER_CONTAINER}
evm_zkgm=${EVM_ZKGM_CONTRACT:?set EVM_ZKGM_CONTRACT}
gno_client=${GNO_EVM_CLIENT_ID:?set GNO_EVM_CLIENT_ID}
evm_client=${EVM_GNO_CLIENT_ID:?set EVM_GNO_CLIENT_ID}
gno_chain_id=${GNO_CHAIN_ID:-dev}
evm_chain_id=${EVM_CHAIN_ID:?set EVM_CHAIN_ID}
topology_env=${TOPOLOGY_ENV_FILE:-"$script_dir/gno-evm-topology.env"}
gno_port=gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm
version=ucs03-zkgm-0
evm_zkgm_lower=$(printf %s "$evm_zkgm" | tr '[:upper:]' '[:lower:]')

require_positive_decimal() {
  [[ $2 =~ ^[1-9][0-9]*$ ]] || { echo "$1 must be a positive decimal integer" >&2; exit 2; }
}

require_positive_decimal EVM_CHAIN_ID "$evm_chain_id"
require_positive_decimal GNO_EVM_CLIENT_ID "$gno_client"
require_positive_decimal EVM_GNO_CLIENT_ID "$evm_client"
[[ $evm_zkgm =~ ^0x[0-9a-fA-F]{40}$ ]] || {
  echo "EVM_ZKGM_CONTRACT must be a 20-byte hex address" >&2
  exit 2
}

voyager() {
  docker exec "$voyager_container" ./voyager -c /config/voyager-config.gno-union.jsonc "$@"
}

# shellcheck source=voyager-topology.sh
source "$script_dir/voyager-topology.sh"

if [[ ${VOYAGER_INDEX_STARTED:-0} != 1 ]]; then
  voyager index "$gno_chain_id" --enqueue >/dev/null
  voyager index "$evm_chain_id" --enqueue >/dev/null
fi

connection_op=$(jq -cn --arg chain "$gno_chain_id" --argjson local "$gno_client" --argjson remote "$evm_client" '
  {"@type":"call","@value":{"@type":"submit_tx","@value":{
    chain_id:$chain,datagrams:[{ibc_spec_id:"ibc-union",datagram:{
      "@type":"connection_open_init","@value":{client_id:$local,counterparty_client_id:$remote}
    }}]
  }}}')
voyager q e "$connection_op" >/dev/null

gno_connection=$(wait_for 'Gno-EVM Gno connection' find_connection "$gno_chain_id" "$gno_client" "$evm_client")
evm_connection=$(wait_for 'Gno-EVM EVM connection' find_connection "$evm_chain_id" "$evm_client" "$gno_client")
require_positive_decimal GNO_EVM_CONNECTION_ID "$gno_connection"
require_positive_decimal EVM_GNO_CONNECTION_ID "$evm_connection"

gno_connection_state=$(ibc_state "$gno_chain_id" "{\"connection\":{\"connection_id\":$gno_connection}}")
evm_connection_state=$(ibc_state "$evm_chain_id" "{\"connection\":{\"connection_id\":$evm_connection}}")
jq -e --argjson remote "$evm_connection" '.state.counterparty_connection_id == $remote' <<<"$gno_connection_state" >/dev/null
jq -e --argjson remote "$gno_connection" '.state.counterparty_connection_id == $remote' <<<"$evm_connection_state" >/dev/null

gno_port_hex=0x$(printf %s "$gno_port" | od -An -tx1 | tr -d ' \n')
channel_op=$(jq -cn \
  --arg chain "$gno_chain_id" \
  --arg port "$gno_port_hex" \
  --arg counterparty_port "$evm_zkgm_lower" \
  --arg version "$version" \
  --argjson connection "$gno_connection" '
  {"@type":"call","@value":{"@type":"submit_tx","@value":{
    chain_id:$chain,datagrams:[{ibc_spec_id:"ibc-union",datagram:{
      "@type":"channel_open_init","@value":{
        port_id:$port,counterparty_port_id:$counterparty_port,
        connection_id:$connection,version:$version
      }
    }}]
  }}}')
voyager q e "$channel_op" >/dev/null

gno_channel=$(wait_for 'Gno-EVM Gno channel' find_channel "$gno_chain_id" "$gno_connection" "$evm_zkgm_lower")
evm_channel=$(wait_for 'Gno-EVM EVM channel' find_channel "$evm_chain_id" "$evm_connection" "$gno_port_hex")
require_positive_decimal GNO_EVM_CHANNEL_ID "$gno_channel"
require_positive_decimal EVM_GNO_CHANNEL_ID "$evm_channel"

gno_channel_state=$(ibc_state "$gno_chain_id" "{\"channel\":{\"channel_id\":$gno_channel}}")
evm_channel_state=$(ibc_state "$evm_chain_id" "{\"channel\":{\"channel_id\":$evm_channel}}")
jq -e --argjson remote "$evm_channel" '.state.counterparty_channel_id == $remote' <<<"$gno_channel_state" >/dev/null
jq -e --argjson remote "$gno_channel" '.state.counterparty_channel_id == $remote' <<<"$evm_channel_state" >/dev/null

umask 077
{
  printf 'GNO_EVM_CONNECTION_ID=%s\n' "$gno_connection"
  printf 'EVM_GNO_CONNECTION_ID=%s\n' "$evm_connection"
  printf 'GNO_EVM_CHANNEL_ID=%s\n' "$gno_channel"
  printf 'EVM_GNO_CHANNEL_ID=%s\n' "$evm_channel"
} >"$topology_env"
echo "wrote live Gno-EVM topology to $topology_env"
