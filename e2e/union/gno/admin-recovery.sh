#!/bin/bash
set -eu

DEFAULT_MNEMONIC="source bonus chronic canvas draft south burst lottery vacant surface solve popular case indicate oppose farm nothing bullet exhibit title speed wink action roast"

GNO_CHAIN_ID="${GNO_CHAIN_ID:-dev}"
GNO_GNOKEY_REMOTE="${GNO_GNOKEY_REMOTE:-gno:26657}"
GNO_CLIENT_ID="${GNO_CLIENT_ID:-1}"
UNION_CLIENT_ID="${UNION_CLIENT_ID:-4}"
GNO_PACKET_CONNECTION_ID="${GNO_PACKET_CONNECTION_ID:-5}"
UNION_PACKET_CONNECTION_ID="${UNION_PACKET_CONNECTION_ID:-3}"
GNO_PACKET_CHANNEL_ID="${GNO_PACKET_CHANNEL_ID:-3}"
UNION_PACKET_CHANNEL_ID="${UNION_PACKET_CHANNEL_ID:-2}"
GNO_PACKET_PORT_ID="${GNO_PACKET_PORT_ID:-gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm}"
GNO_PACKET_RELAYER="${GNO_PACKET_RELAYER:-g1relayer}"
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

query_connection="gno.land/r/onbloc/ibc/union/core.QueryConnection($GNO_PACKET_CONNECTION_ID)"
query_channel="gno.land/r/onbloc/ibc/union/core.QueryChannel($GNO_PACKET_CHANNEL_ID)"

printf "%s\n\n" "$ADMIN_MNEMONIC" | gnokey add admin --recover --insecure-password-stdin --force >/dev/null
ADMIN_ADDR=$(key_addr admin)

if non_empty_query "$query_connection" && non_empty_query "$query_channel"; then
  echo "Gno connection $GNO_PACKET_CONNECTION_ID and channel $GNO_PACKET_CHANNEL_ID already exist; skipping recovery"
  exit 0
fi

script="/tmp/gno-admin-recovery.gno"
cat >"$script" <<EOF
package main

import (
	"gno.land/p/onbloc/ibc/union/types"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	core "gno.land/r/onbloc/ibc/union/core"
)

func main(cur realm) {
	portId := []byte("$GNO_PACKET_PORT_ID")
	version := zkgm.Version
	relayer := "$GNO_PACKET_RELAYER"

	if core.QueryConnection(types.ConnectionId($GNO_PACKET_CONNECTION_ID)) == "" {
		for id := 1; id <= $GNO_PACKET_CONNECTION_ID; id++ {
			if core.QueryConnection(types.ConnectionId(id)) == "" {
				core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(types.ClientId($GNO_CLIENT_ID), types.ClientId($UNION_CLIENT_ID)))
			}
		}
		core.ForceConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(types.ConnectionId($GNO_PACKET_CONNECTION_ID), types.ConnectionId($UNION_PACKET_CONNECTION_ID), nil, 0))
	}
	if core.QueryChannel(types.ChannelId($GNO_PACKET_CHANNEL_ID)) == "" {
		for id := 1; id <= $GNO_PACKET_CHANNEL_ID; id++ {
			if core.QueryChannel(types.ChannelId(id)) == "" {
				core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(portId, portId, types.ConnectionId($GNO_PACKET_CONNECTION_ID), version, relayer))
			}
		}
		core.ForceChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(types.ChannelId($GNO_PACKET_CHANNEL_ID), version, types.ChannelId($UNION_PACKET_CHANNEL_ID), nil, 0, relayer))
	}
}
EOF

echo "Running Gno admin recovery as $ADMIN_ADDR"
printf "\n" | gnokey maketx run \
  -gas-fee 1000000ugnot \
  -gas-wanted 90000000 \
  -broadcast \
  -chainid "$GNO_CHAIN_ID" \
  -remote "$GNO_GNOKEY_REMOTE" \
  -insecure-password-stdin \
  admin "$script"

non_empty_query "$query_connection" || {
  echo "QueryConnection($GNO_PACKET_CONNECTION_ID) is empty after recovery" >&2
  exit 1
}

non_empty_query "$query_channel" || {
  echo "QueryChannel($GNO_PACKET_CHANNEL_ID) is empty after recovery" >&2
  exit 1
}

echo "Gno admin recovery complete"
