#!/usr/bin/env bash
set -euo pipefail

GNO_ROOT="${GNO_ROOT:-$HOME/.cache/gno-ibc/gno}"
GNO_IBC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RPC_ENDPOINT="tcp://127.0.0.1:26657"
RPC_URL="http://127.0.0.1:26657"
EXPECTED_HIT="0x0100000000000000000000000000000000000000000000000000000000000000"
TEST1_MNEMONIC="source bonus chronic canvas draft south burst lottery vacant surface solve popular case indicate oppose farm nothing bullet exhibit title speed wink action roast"

WORKDIR=$(mktemp -d)
KEYBASE="$WORKDIR/keybase"

cleanup() {
  if [[ -n "${GNODEV_PID:-}" ]] && kill -0 "$GNODEV_PID" 2>/dev/null; then
    kill "$GNODEV_PID" 2>/dev/null || true
    wait "$GNODEV_PID" 2>/dev/null || true
  fi
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

echo ">> starting gnodev on 127.0.0.1:26657"
gnodev local \
  -root "$GNO_ROOT" \
  -resolver "root=$GNO_IBC_ROOT" \
  -resolver "root=$GNO_ROOT/examples" \
  -resolver "local=$GNO_IBC_ROOT/gno.land/p/core/ibc/zkgm" \
  -resolver "local=$GNO_IBC_ROOT/gno.land/p/core/tokenbucket" \
  -resolver "local=$GNO_IBC_ROOT/gno.land/r/core/ibc/v1/apps/zkgm" \
  -resolver "local=$GNO_IBC_ROOT/gno.land/r/core/ibc/v1/apps/zkgm/v0/impl" \
  -resolver "local=$GNO_IBC_ROOT/gno.land/r/core/ibc/v1/apps/zkgm/v0/loader" \
  -resolver "local=$GNO_IBC_ROOT/gno.land/r/core/ibc/v1/apps/zkgm/testing/e2e" \
  -paths "gno.land/r/core/ibc/v1/core,gno.land/r/core/ibc/v1/lightclients/cometbls,gno.land/r/core/ibc/v1/lightclients/statelensics23mpt,gno.land/r/gnoswap/ibc/v1/apps/zkgm,gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/impl,gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/loader,gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e" \
  -no-web \
  -node-rpc-listener "0.0.0.0:26657" \
  >"$WORKDIR/gnodev.log" 2>&1 &
GNODEV_PID=$!

DEADLINE=$((SECONDS + 60))
while (( SECONDS < DEADLINE )); do
  if curl -sf "$RPC_URL/status" 2>/dev/null | grep -q latest_block_height; then
    break
  fi
  if ! kill -0 "$GNODEV_PID" 2>/dev/null; then
    echo "gnodev exited unexpectedly"
    cat "$WORKDIR/gnodev.log"
    exit 1
  fi
  sleep 1
done

if ! curl -sf "$RPC_URL/status" 2>/dev/null | grep -q latest_block_height; then
  echo "gnodev not ready within 60s"
  cat "$WORKDIR/gnodev.log"
  exit 1
fi
echo ">> gnodev ready"

echo ">> importing test1 into local keybase"
if ! printf "%s\n\n\n" "$TEST1_MNEMONIC" | gnokey add test1 -recover -insecure-password-stdin=true -home "$KEYBASE" >"$WORKDIR/keyadd.log" 2>&1; then
  echo "FAIL: gnokey add test1"
  cat "$WORKDIR/keyadd.log"
  exit 1
fi

maketx_run() {
  local script="$1"
  local log="$2"
  if ! echo "" | gnokey maketx run -insecure-password-stdin \
    -home "$KEYBASE" \
    -gas-fee 1000000ugnot -gas-wanted 90000000 \
    -broadcast -chainid dev -remote "$RPC_ENDPOINT" \
    test1 "$script" >"$log" 2>&1; then
    echo "FAIL: maketx run failed ($(basename "$script"))"
    cat "$log"
    exit 1
  fi
}

run_qeval() {
  gnokey query vm/qeval -remote "$RPC_ENDPOINT" -data "$1" 2>&1
}

extract_data() {
  grep -E '^data:' | sed -E 's/^data: \("(.*)" [^)]+\)$/\1/'
}

assert_eq() {
  local label="$1" actual="$2" expected="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $label"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    exit 1
  fi
  echo "PASS: $label"
}

assert_nonempty() {
  local label="$1" actual="$2"
  if [[ -z "$actual" ]]; then
    echo "FAIL: $label expected non-empty, got empty"
    exit 1
  fi
  local preview="${actual:0:60}"
  if (( ${#actual} > 60 )); then preview+="..."; fi
  echo "PASS: $label ($preview)"
}

hex_to_h256_lit() {
  local hex="${1#0x}"
  local out="H256{"
  for i in $(seq 0 31); do
    [ "$i" -gt 0 ] && out+=","
    out+="0x${hex:$((i*2)):2}"
  done
  out+="}"
  echo "$out"
}

echo ">> Phase 1: register light clients (Sections 0.1, 0.2)"
cat >"$WORKDIR/register.gno" <<'EOF'
package main

import (
	core "gno.land/r/core/ibc/v1/core"
	cometbls "gno.land/r/core/ibc/v1/lightclients/cometbls"
	statelens "gno.land/r/core/ibc/v1/lightclients/statelensics23mpt"
)

func main() {
	if !core.HasClient(statelens.ClientType) {
		core.RegisterClient(cross, statelens.ClientType, statelens.Adapter{})
	}
	if !core.HasClient(cometbls.ClientType) {
		core.RegisterClient(cross, cometbls.ClientType, cometbls.Adapter{})
	}
	println("registered_statelens", core.HasClient(statelens.ClientType))
	println("registered_cometbls", core.HasClient(cometbls.ClientType))
}
EOF
maketx_run "$WORKDIR/register.gno" "$WORKDIR/register.log"
grep -q 'registered_statelens true' "$WORKDIR/register.log" || { echo "FAIL: state-lens not registered"; cat "$WORKDIR/register.log"; exit 1; }
grep -q 'registered_cometbls true' "$WORKDIR/register.log" || { echo "FAIL: cometbls not registered"; cat "$WORKDIR/register.log"; exit 1; }
echo "PASS: light client registrations"

echo ">> Phase 2: ZKGM app loader check (Section 0.3)"
cat >"$WORKDIR/check_zkgm.gno" <<'EOF'
package main

import (
	core "gno.land/r/core/ibc/v1/core"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
)

func main() {
	portID := []byte(zkgm.ProxyPkgPath())
	println("zkgm_registered", core.HasApp(portID))
}
EOF
maketx_run "$WORKDIR/check_zkgm.gno" "$WORKDIR/check_zkgm.log"
grep -q 'zkgm_registered true' "$WORKDIR/check_zkgm.log" || { echo "FAIL: ZKGM app not auto-registered"; cat "$WORKDIR/check_zkgm.log"; exit 1; }
echo "PASS: ZKGM app auto-registered"

echo ">> Phase 3: CreateClient cometbls (Section 1.1)"
cat >"$WORKDIR/create_cometbls.gno" <<'EOF'
package main

import (
	"encoding/hex"

	core "gno.land/r/core/ibc/v1/core"
	cometbls "gno.land/r/core/ibc/v1/lightclients/cometbls"
)

func main() {
	clientState, err := hex.DecodeString("756e696f6e2d6465766e65742d313333370000000000000000000000000000000000000000000000000000000000000000000000000000000460623fc85e000000000000000000000000000000000000000000000000000000000002540be400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cafebabd0cf2ffe8f45a20514018173d3007644817a9767dc0fbdb246696fd9c261ce3bc")
	if err != nil {
		panic(err)
	}
	consensusState, err := hex.DecodeString("000000000000000000000000000000000000000000000000180a0696b346ce00ee7e3e58f98ac95d63ce93b270981df3ee54ca367f8d521ed1f444717595cd3620ddfe7a0f75c65d876316091eccd494a54a2bb324c872015f73e528d53cb9c4")
	if err != nil {
		panic(err)
	}
	id := core.CreateClient(cross, core.MsgCreateClient{
		ClientType:          cometbls.ClientType,
		ClientStateBytes:    clientState,
		ConsensusStateBytes: consensusState,
	})
	println("cometbls_client_id", id.String())
}
EOF
maketx_run "$WORKDIR/create_cometbls.gno" "$WORKDIR/create_cometbls.log"
COMETBLS_ID=$(grep -m1 '^cometbls_client_id ' "$WORKDIR/create_cometbls.log" | awk '{print $2}')
if [[ -z "$COMETBLS_ID" ]]; then
  echo "FAIL: cometbls_client_id not captured"
  cat "$WORKDIR/create_cometbls.log"
  exit 1
fi
echo ">> cometbls_client_id=$COMETBLS_ID"

echo ">> Phase 4: UpdateClient cometbls (Section 2)"
cat >"$WORKDIR/update_client.gno" <<EOF
package main

import (
	"encoding/hex"

	core "gno.land/r/core/ibc/v1/core"
)

func main() {
	msg, err := hex.DecodeString("00000000000000000000000000000000000000000000000000000000cafebabe00000000000000000000000000000000000000000000000000000000673f5ac3000000000000000000000000000000000000000000000000000000003b7e468e20ddfe7a0f75c65d876316091eccd494a54a2bb324c872015f73e528d53cb9c420ddfe7a0f75c65d876316091eccd494a54a2bb324c872015f73e528d53cb9c4ee7e3e58f98ac95d63ce93b270981df3ee54ca367f8d521ed1f444717595cd3600000000000000000000000000000000000000000000000000000000cafebabd0000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000018003cf56142a1e03d2445a82100feaf70c1cd95a731ed85792afff5792ec0bdd2108991bb56f9043a269f88903de616a9ab99a3c5ab778e566744b060456c5616c06bce7f1930421768c2cbd79f88d08ec3a52d7c9a867064e973064385e9c945e02951190dd7ce1662546733dd540188c96e608ca750fef36b39e2577833634c70ae6f1a6d00dc6c21446aaf285ef35d944e8782b131300574f9a889c7e708a2325e9a78013bbe869d38b19c602daf69644c77d177e99ed76398bcee13c61fdbf2e178a5ba028a36033e54d1d9a0071e82e04079a5305347ebac6d66f6ebfa48b1da1bf9dc5a51efa292e1dc7b85d26f18422eb386c48ca75434039764448bb96268ddc2cf683ddca4bd83df21c5631cf784375eebe77eabc2de77886bf1d48392c9c52e063b4a7131eab9abba12a9f26888bc37366d41ac7d4bac0bf6755acb009bf9f36f380b6d0eeaabf066503a1b6e01dcc965d968d7694e01b1755e6bdd21c7a80b41682748f9b7151714be34aa79aad48bbb2a84525f6cdf812658c6e4f")
	if err != nil {
		panic(err)
	}
	h := core.UpdateClient(cross, core.MsgUpdateClient{
		ClientId:      core.ClientId($COMETBLS_ID),
		ClientMessage: msg,
	})
	println("update_height", h.String())
}
EOF
maketx_run "$WORKDIR/update_client.gno" "$WORKDIR/update_client.log"
UPDATE_HEIGHT=$(grep -m1 '^update_height ' "$WORKDIR/update_client.log" | awk '{print $2}')
if [[ -z "$UPDATE_HEIGHT" ]]; then
  echo "FAIL: update_height not captured"
  cat "$WORKDIR/update_client.log"
  exit 1
fi
echo ">> update_height=$UPDATE_HEIGHT"

echo ">> Phase 5: ConnectionOpenInit (Section 3)"
cat >"$WORKDIR/conn_init.gno" <<EOF
package main

import core "gno.land/r/core/ibc/v1/core"

func main() {
	id := core.ConnectionOpenInit(cross, core.MsgConnectionOpenInit{
		ClientId:             core.ClientId($COMETBLS_ID),
		CounterpartyClientId: core.ClientId(99),
	})
	println("connection_id", id.String())
}
EOF
maketx_run "$WORKDIR/conn_init.gno" "$WORKDIR/conn_init.log"
CONNECTION_ID=$(grep -m1 '^connection_id ' "$WORKDIR/conn_init.log" | awk '{print $2}')
if [[ -z "$CONNECTION_ID" ]]; then
  echo "FAIL: connection_id not captured"
  cat "$WORKDIR/conn_init.log"
  exit 1
fi
echo ">> connection_id=$CONNECTION_ID"

echo ">> Phase 6: CreateStateLensClient (Section 1.2)"
cat >"$WORKDIR/create_statelens.gno" <<'EOF'
package main

import (
	"bytes"

	statelensp "gno.land/p/core/ibc/lightclients/statelensics23mpt"
	core "gno.land/r/core/ibc/v1/core"
	statelens "gno.land/r/core/ibc/v1/lightclients/statelensics23mpt"
)

func main() {
	consensusState, err := statelensp.EncodeConsensusState(statelensp.ConsensusState{
		Timestamp:   1,
		StateRoot:   bytes.Repeat([]byte{0x01}, 32),
		StorageRoot: bytes.Repeat([]byte{0x02}, 32),
	})
	if err != nil {
		panic(err)
	}
	id := core.CreateClient(cross, core.MsgCreateClient{
		ClientType: statelens.ClientType,
		ClientStateBytes: statelensp.EncodeClientState(statelensp.ClientState{
			L2ChainID:         "local-l2",
			L1ClientID:        1,
			L2ClientID:        1,
			L2LatestHeight:    1,
			TimestampOffset:   64,
			StateRootOffset:   0,
			StorageRootOffset: 32,
		}),
		ConsensusStateBytes: consensusState,
	})
	println("statelens_client_id", id.String())
}
EOF
maketx_run "$WORKDIR/create_statelens.gno" "$WORKDIR/create_statelens.log"
STATELENS_ID=$(grep -m1 '^statelens_client_id ' "$WORKDIR/create_statelens.log" | awk '{print $2}')
if [[ -z "$STATELENS_ID" ]]; then
  echo "FAIL: statelens_client_id not captured"
  cat "$WORKDIR/create_statelens.log"
  exit 1
fi
echo ">> statelens_client_id=$STATELENS_ID"

echo ">> SKIP Sections 4-6 (ConnectionOpen{Try,Ack,Confirm}): need Union counterparty proofs"
echo ">> SKIP Section 7 (ChannelOpenInit): depends on open connection, covered by mock path"
echo ">> SKIP Sections 8-10 (ChannelOpen{Try,Ack,Confirm}): need Union counterparty proofs"

echo ">> Phase 7: mock ZKGM channel pair + BatchSend"
cat >"$WORKDIR/mock_channels.gno" <<'EOF'
package main

import (
	e2e "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e"
	_ "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/loader"
)

func main() {
	e2e.RegisterMockLightClient(cross)
	pair := e2e.OpenE2EChannelPair(cross)
	println("mock_source", pair.Source.String())
	println("mock_destination", pair.Destination.String())
}
EOF
maketx_run "$WORKDIR/mock_channels.gno" "$WORKDIR/mock_channels.log"
MOCK_SOURCE=$(grep -m1 '^mock_source ' "$WORKDIR/mock_channels.log" | awk '{print $2}')
MOCK_DEST=$(grep -m1 '^mock_destination ' "$WORKDIR/mock_channels.log" | awk '{print $2}')
if [[ -z "$MOCK_SOURCE" || -z "$MOCK_DEST" ]]; then
  echo "FAIL: mock channel ids not captured"
  cat "$WORKDIR/mock_channels.log"
  exit 1
fi
echo ">> mock_source=$MOCK_SOURCE mock_destination=$MOCK_DEST"

cat >"$WORKDIR/send.gno" <<EOF
package main

import (
	core "gno.land/r/core/ibc/v1/core"
	e2e "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e"
	_ "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/loader"
)

func main() {
	packet := core.Packet{
		SourceChannelId:      core.ChannelId($MOCK_SOURCE),
		DestinationChannelId: core.ChannelId($MOCK_DEST),
		Data:                 []byte("hello"),
		TimeoutTimestamp:     core.Timestamp(1 << 60),
	}
	batchHash := e2e.BatchSend(cross, packet)
	println("batch_hash", batchHash.String())
}
EOF
maketx_run "$WORKDIR/send.gno" "$WORKDIR/send.log"
BATCH_HASH=$(grep -m1 '^batch_hash ' "$WORKDIR/send.log" | awk '{print $2}')
if [[ -z "$BATCH_HASH" ]]; then
  echo "FAIL: batch_hash not captured"
  cat "$WORKDIR/send.log"
  exit 1
fi
echo ">> batch_hash=$BATCH_HASH"
BATCH_HASH_LIT=$(hex_to_h256_lit "$BATCH_HASH")

echo ">> Phase 8: qeval probes"

R=$(run_qeval "gno.land/r/core/ibc/v1/core.GetClientType($COMETBLS_ID)" | extract_data)
assert_nonempty "GetClientType(cometbls_id=$COMETBLS_ID)" "$R"

R=$(run_qeval "gno.land/r/core/ibc/v1/core.GetClientType($STATELENS_ID)" | extract_data)
assert_nonempty "GetClientType(statelens_id=$STATELENS_ID)" "$R"

R=$(run_qeval "gno.land/r/core/ibc/v1/core.GetClientType(9999)" | extract_data)
assert_eq "GetClientType(9999) miss" "$R" ""

R=$(run_qeval "gno.land/r/core/ibc/v1/core.QueryClientState($COMETBLS_ID)" | extract_data)
assert_nonempty "QueryClientState(cometbls_id=$COMETBLS_ID)" "$R"

R=$(run_qeval "gno.land/r/core/ibc/v1/core.QueryClientState(9999)" | extract_data)
assert_eq "QueryClientState(9999) miss" "$R" ""

R=$(run_qeval "gno.land/r/core/ibc/v1/core.QueryConsensusState($COMETBLS_ID, $UPDATE_HEIGHT)" | extract_data)
assert_nonempty "QueryConsensusState(cometbls_id=$COMETBLS_ID, height=$UPDATE_HEIGHT)" "$R"

R=$(run_qeval "gno.land/r/core/ibc/v1/core.QueryConnection($CONNECTION_ID)" | extract_data)
assert_nonempty "QueryConnection(connection_id=$CONNECTION_ID)" "$R"

R=$(run_qeval "gno.land/r/core/ibc/v1/core.QueryConnection(9999)" | extract_data)
assert_eq "QueryConnection(9999) miss" "$R" ""

R=$(run_qeval "gno.land/r/core/ibc/v1/core.QueryChannel($MOCK_SOURCE)" | extract_data)
assert_nonempty "QueryChannel(mock_source=$MOCK_SOURCE)" "$R"

R=$(run_qeval "gno.land/r/core/ibc/v1/core.QueryChannel(9999)" | extract_data)
assert_eq "QueryChannel(9999) miss" "$R" ""

R=$(run_qeval "gno.land/r/core/ibc/v1/core.QueryBatchPackets(${BATCH_HASH_LIT})" | extract_data)
assert_eq "QueryBatchPackets(batchHash) baseline" "$R" "$EXPECTED_HIT"

R=$(run_qeval "gno.land/r/core/ibc/v1/core.QueryCommitmentAtPath(BatchPacketsPath(${BATCH_HASH_LIT}))" | extract_data)
assert_eq "QueryCommitmentAtPath(BatchPacketsPath(batchHash)) composed" "$R" "$EXPECTED_HIT"

R=$(run_qeval 'gno.land/r/core/ibc/v1/core.QueryCommitmentAtPath(H256{})' | extract_data)
assert_eq "QueryCommitmentAtPath(H256{}) miss" "$R" ""

R=$(run_qeval 'gno.land/r/core/ibc/v1/core.QueryReceiptAtPath(H256{})' | extract_data)
assert_eq "QueryReceiptAtPath(H256{}) miss" "$R" ""

echo "all qeval smoke assertions passed"
