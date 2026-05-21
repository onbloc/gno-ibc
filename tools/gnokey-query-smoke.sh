#!/usr/bin/env bash
set -euo pipefail

EXPECTED_HIT="0x0100000000000000000000000000000000000000000000000000000000000000"

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gnokey-smoke/lib.sh"

trap cleanup_smoke_env EXIT
setup_smoke_chain

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

probe_qeval_nonempty "GetClientType(cometbls_id=$COMETBLS_ID)" \
  "gno.land/r/core/ibc/v1/core.GetClientType($COMETBLS_ID)"

probe_qeval_nonempty "GetClientType(statelens_id=$STATELENS_ID)" \
  "gno.land/r/core/ibc/v1/core.GetClientType($STATELENS_ID)"

probe_qeval "GetClientType(9999) miss" \
  "gno.land/r/core/ibc/v1/core.GetClientType(9999)" \
  ""

probe_qeval_nonempty "QueryClientState(cometbls_id=$COMETBLS_ID)" \
  "gno.land/r/core/ibc/v1/core.QueryClientState($COMETBLS_ID)"

probe_qeval "QueryClientState(9999) miss" \
  "gno.land/r/core/ibc/v1/core.QueryClientState(9999)" \
  ""

probe_qeval_nonempty "QueryConsensusState(cometbls_id=$COMETBLS_ID, height=$UPDATE_HEIGHT)" \
  "gno.land/r/core/ibc/v1/core.QueryConsensusState($COMETBLS_ID, $UPDATE_HEIGHT)"

probe_qeval_nonempty "QueryConnection(connection_id=$CONNECTION_ID)" \
  "gno.land/r/core/ibc/v1/core.QueryConnection($CONNECTION_ID)"

probe_qeval "QueryConnection(9999) miss" \
  "gno.land/r/core/ibc/v1/core.QueryConnection(9999)" \
  ""

probe_qeval_nonempty "QueryChannel(mock_source=$MOCK_SOURCE)" \
  "gno.land/r/core/ibc/v1/core.QueryChannel($MOCK_SOURCE)"

probe_qeval "QueryChannel(9999) miss" \
  "gno.land/r/core/ibc/v1/core.QueryChannel(9999)" \
  ""

probe_qeval "QueryBatchPackets(batchHash) baseline" \
  "gno.land/r/core/ibc/v1/core.QueryBatchPackets(${BATCH_HASH_LIT})" \
  "$EXPECTED_HIT"

probe_qeval "QueryCommitmentAtPath(BatchPacketsPath(batchHash)) composed" \
  "gno.land/r/core/ibc/v1/core.QueryCommitmentAtPath(BatchPacketsPath(${BATCH_HASH_LIT}))" \
  "$EXPECTED_HIT"

probe_qeval "QueryCommitmentAtPath(H256{}) miss" \
  'gno.land/r/core/ibc/v1/core.QueryCommitmentAtPath(H256{})' \
  ""

probe_qeval "QueryReceiptAtPath(H256{}) miss" \
  'gno.land/r/core/ibc/v1/core.QueryReceiptAtPath(H256{})' \
  ""

echo "all qeval smoke assertions passed"

echo ">> Phase 9: native TokenOrder ack-failure refund (#58 regression)"
# Regression guard for issue #58: a native TokenOrder failure-ack refund routes
# core.PacketAcknowledgement -> impl.Ack -> refundV2 -> sendNative ->
# zkgm.ReleaseNative. ReleaseNative's requireImplCaller must accept the core
# realm as an authorized caller, otherwise the escrow refund panics.
PROXY_ADDR=$(gnokey query vm/qeval -remote "$RPC_ENDPOINT" \
  -data "gno.land/r/gnoswap/ibc/v1/apps/zkgm.ProxyAddress()" 2>&1 | extract_data)
if [[ -z "$PROXY_ADDR" ]]; then
  echo "FAIL: could not resolve zkgm proxy address"
  exit 1
fi
REFUND_RECIPIENT="g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
echo ">> proxy_address=$PROXY_ADDR refund_recipient=$REFUND_RECIPIENT"

# Step 1: open a fresh channel pair (isolated from the Phase 7 pair) and encode
# the native ugnot TokenOrder. This is the single definition of the order.
cat >"$WORKDIR/native_refund_args.gno" <<EOF
package main

import (
	"encoding/hex"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	e2e "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e"
)

func main() {
	e2e.RegisterMockLightClient(cross)
	pair := e2e.OpenE2EChannelPair(cross)

	order := z.TokenOrderV2{
		Sender:      []byte("$REFUND_RECIPIENT"),
		Receiver:    []byte("counterparty-receiver"),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte("counterparty-projected-quote"),
		QuoteAmount: u256.NewUint(100),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
	}
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}

	println("source_channel", pair.Source.String())
	println("destination_channel", pair.Destination.String())
	println("operand_hex", hex.EncodeToString(operand))
}
EOF
maketx_run "$WORKDIR/native_refund_args.gno" "$WORKDIR/native_refund_args.log"
REFUND_SOURCE=$(grep -m1 '^source_channel ' "$WORKDIR/native_refund_args.log" | awk '{print $2}')
REFUND_DEST=$(grep -m1 '^destination_channel ' "$WORKDIR/native_refund_args.log" | awk '{print $2}')
REFUND_OPERAND=$(grep -m1 '^operand_hex ' "$WORKDIR/native_refund_args.log" | awk '{print $2}')
if [[ -z "$REFUND_SOURCE" || -z "$REFUND_DEST" || -z "$REFUND_OPERAND" ]]; then
  echo "FAIL: could not capture native refund channel pair / operand"
  cat "$WORKDIR/native_refund_args.log"
  exit 1
fi
echo ">> refund channel pair: source=$REFUND_SOURCE destination=$REFUND_DEST"

# Step 2: real native send. This escrows 100ugnot on the proxy realm and bumps
# the channel balance. `maketx run` cannot expose OriginSend to zkgm.Send, so
# this must be a direct `maketx call` with -send.
# SendRaw args: channelId, timeoutTimestamp (far-future), salt (32 zero bytes),
# version 2 (INSTR_VERSION_2), opcode 3 (OP_TOKEN_ORDER), operandHex.
maketx_call "$WORKDIR/native_refund_send.log" \
  -pkgpath "gno.land/r/gnoswap/ibc/v1/apps/zkgm" \
  -func SendRaw \
  -args "$REFUND_SOURCE" \
  -args "2000000000000000000" \
  -args "0000000000000000000000000000000000000000000000000000000000000000" \
  -args "2" \
  -args "3" \
  -args "$REFUND_OPERAND" \
  -send "100ugnot"

PROXY_BAL_BEFORE=$(native_balance "$PROXY_ADDR")
if [[ "$PROXY_BAL_BEFORE" != "100ugnot" ]]; then
  echo "FAIL: expected 100ugnot escrowed on proxy after SendRaw, got '$PROXY_BAL_BEFORE'"
  exit 1
fi
echo "PASS: SendRaw escrowed 100ugnot on the proxy realm"

# Step 3: commit the packet and deliver a failure ack through the core callback.
# The packet is rebuilt from the operand captured in step 1, so the TokenOrder
# is defined once (in native_refund_args.gno) and cannot drift between the send
# and the ack.
cat >"$WORKDIR/native_refund_ack.gno" <<EOF
package main

import (
	"encoding/hex"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/core/ibc/v1/core"
	e2e "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e"
)

func main() {
	operand, err := hex.DecodeString("$REFUND_OPERAND")
	if err != nil {
		panic(err)
	}
	instruction := z.Instruction{
		Version: z.INSTR_VERSION_2,
		Opcode:  z.OP_TOKEN_ORDER,
		Operand: operand,
	}
	packet := core.Packet{
		SourceChannelId:      core.ChannelId($REFUND_SOURCE),
		DestinationChannelId: core.ChannelId($REFUND_DEST),
		Data:                 e2e.MustPacketData(cross, instruction),
		TimeoutTimestamp:     core.Timestamp(1 << 62),
	}
	e2e.BatchSend(cross, packet)
	println("commitment_before_ack", core.HasPacketCommitment(cross, packet))

	failureAck := e2e.MustAck(cross, u256.Zero(), []byte("counterparty failed"))
	core.PacketAcknowledgement(cross, core.MsgPacketAcknowledgement{
		Packets:          []core.Packet{packet},
		Acknowledgements: [][]byte{failureAck},
		ProofHeight:      core.Height(1),
	})

	println("commitment_after_ack", core.HasPacketCommitment(cross, packet))
	println("RESULT native ack-failure refund succeeded")
}
EOF
maketx_run "$WORKDIR/native_refund_ack.gno" "$WORKDIR/native_refund_ack.log"
grep -q 'commitment_before_ack true' "$WORKDIR/native_refund_ack.log" \
  || { echo "FAIL: packet commitment missing before ack"; cat "$WORKDIR/native_refund_ack.log"; exit 1; }
grep -q 'commitment_after_ack false' "$WORKDIR/native_refund_ack.log" \
  || { echo "FAIL: packet commitment not cleared after ack"; cat "$WORKDIR/native_refund_ack.log"; exit 1; }
grep -q 'RESULT native ack-failure refund succeeded' "$WORKDIR/native_refund_ack.log" \
  || { echo "FAIL: native ack-failure refund did not complete"; cat "$WORKDIR/native_refund_ack.log"; exit 1; }

PROXY_BAL_AFTER=$(native_balance "$PROXY_ADDR")
RECIPIENT_BAL_AFTER=$(native_balance "$REFUND_RECIPIENT")
if [[ -n "$PROXY_BAL_AFTER" ]]; then
  echo "FAIL: expected proxy escrow drained after refund, got '$PROXY_BAL_AFTER'"
  exit 1
fi
if [[ "$RECIPIENT_BAL_AFTER" != "100ugnot" ]]; then
  echo "FAIL: expected 100ugnot refunded to sender, got '$RECIPIENT_BAL_AFTER'"
  exit 1
fi
echo "PASS: native ack-failure refund released the 100ugnot escrow to the sender (#58)"

echo "all smoke assertions passed"
