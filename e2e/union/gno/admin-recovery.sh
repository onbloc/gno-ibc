#!/bin/bash
set -eu

DEFAULT_MNEMONIC="source bonus chronic canvas draft south burst lottery vacant surface solve popular case indicate oppose farm nothing bullet exhibit title speed wink action roast"

GNO_CHAIN_ID="${GNO_CHAIN_ID:-dev}"
GNO_GNOKEY_REMOTE="${GNO_GNOKEY_REMOTE:-gno:26657}"
ADMIN_MNEMONIC="${ADMIN_MNEMONIC:-$DEFAULT_MNEMONIC}"

key_addr() {
  name="$1"
  addrs=$(gnokey list 2>&1 | awk -v name="$name" '
    $0 ~ ("(^|[[:space:]])" name "([[:space:]:-]|$)") && match($0, /addr: [^ ]+/) {
      print substr($0, RSTART + 6, RLENGTH - 6)
    }
  ')
  count=$(printf "%s\n" "$addrs" | sed '/^$/d' | wc -l | tr -d ' ')
  [ "$count" = 1 ] || {
    echo "expected one key named $name, got $count" >&2
    exit 1
  }
  printf "%s\n" "$addrs"
}

qeval() {
  gnokey query vm/qeval -remote "$GNO_GNOKEY_REMOTE" -data "$1" 2>&1
}

non_empty_query() {
  out=$(qeval "$1" || true)
  printf "%s\n" "$out" | grep -Eq '\("[^"]+" string\)'
}

query_connection="gno.land/r/onbloc/ibc/union/core.QueryConnection(5)"
query_channel="gno.land/r/onbloc/ibc/union/core.QueryChannel(3)"

printf "%s\n\n" "$ADMIN_MNEMONIC" | gnokey add admin --recover --insecure-password-stdin --force >/dev/null
ADMIN_ADDR=$(key_addr admin)

call_setup() {
  func=$1
  shift
  args=()
  for arg in "$@"; do
    args+=("-args" "$arg")
  done
  printf "\n" | gnokey maketx call \
    -gas-fee 1000000ugnot \
    -gas-wanted 90000000 \
    -broadcast \
    -chainid "$GNO_CHAIN_ID" \
    -remote "$GNO_GNOKEY_REMOTE" \
    -insecure-password-stdin \
    -pkgpath gno.land/r/onbloc/ibc/union/testing/e2e_setup \
    -func "$func" \
    "${args[@]}" \
    admin
}

latest_id() {
  query=$1
  id=1
  while non_empty_query "gno.land/r/onbloc/ibc/union/core.$query($id)"; do
    id=$((id + 1))
  done
  echo $((id - 1))
}

find_client() {
  type=$1
  id=1
  found=0
  while out=$(qeval "gno.land/r/onbloc/ibc/union/core.QueryClientType($id)") &&
    value=$(printf '%s\n' "$out" | sed -n 's/.*("\([^"]*\)" string).*/\1/p') &&
    [ -n "$value" ]; do
    [ "$value" = "$type" ] && found=$id
    id=$((id + 1))
  done
  echo "$found"
}

require_env() {
  eval "value=\${$1:-}"
  [ -n "$value" ] || {
    echo "missing $1" >&2
    exit 1
  }
}

case "${TOPOLOGY_ACTION:-legacy}" in
  discover-client)
    require_env CLIENT_TYPE
    id=$(find_client "$CLIENT_TYPE")
    [ "$id" -gt 0 ] || { echo "no Gno $CLIENT_TYPE client found" >&2; exit 1; }
    echo "GNO_CLIENT_ID=$id"
    exit
    ;;
  init-connection)
    require_env GNO_CLIENT_ID
    require_env COUNTERPARTY_CLIENT_ID
    before=$(latest_id QueryConnection)
    call_setup OpenConnectionInit "$GNO_CLIENT_ID" "$COUNTERPARTY_CLIENT_ID"
    id=$(latest_id QueryConnection)
    [ "$id" -gt "$before" ] || { echo "Gno connection was not created" >&2; exit 1; }
    echo "GNO_PACKET_CONNECTION_ID=$id"
    exit
    ;;
  ack-connection)
    require_env GNO_PACKET_CONNECTION_ID
    require_env COUNTERPARTY_CONNECTION_ID
    call_setup ForceConnectionOpenAck "$GNO_PACKET_CONNECTION_ID" "$COUNTERPARTY_CONNECTION_ID"
    echo "GNO_PACKET_CONNECTION_ID=$GNO_PACKET_CONNECTION_ID"
    exit
    ;;
  init-channel)
    require_env GNO_PACKET_CONNECTION_ID
    require_env COUNTERPARTY_PORT_ID
    before=$(latest_id QueryChannel)
    call_setup OpenChannelInit "$GNO_PACKET_CONNECTION_ID" "$COUNTERPARTY_PORT_ID"
    id=$(latest_id QueryChannel)
    [ "$id" -gt "$before" ] || { echo "Gno channel was not created" >&2; exit 1; }
    echo "GNO_PACKET_CHANNEL_ID=$id"
    exit
    ;;
  ack-channel)
    require_env GNO_PACKET_CHANNEL_ID
    require_env COUNTERPARTY_CHANNEL_ID
    call_setup ForceChannelOpenAck "$GNO_PACKET_CHANNEL_ID" "$COUNTERPARTY_CHANNEL_ID"
    echo "GNO_PACKET_CHANNEL_ID=$GNO_PACKET_CHANNEL_ID"
    exit
    ;;
  legacy) ;;
  *) echo "unknown TOPOLOGY_ACTION=$TOPOLOGY_ACTION" >&2; exit 2 ;;
esac

echo "Running Gno admin recovery as $ADMIN_ADDR"
call_setup Recover

non_empty_query "$query_connection" || {
  echo "QueryConnection(5) is empty after recovery" >&2
  exit 1
}

non_empty_query "$query_channel" || {
  echo "QueryChannel(3) is empty after recovery" >&2
  exit 1
}

echo "Gno admin recovery complete"
