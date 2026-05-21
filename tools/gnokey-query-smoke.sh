#!/usr/bin/env bash
set -euo pipefail

EXPECTED_HIT="0x0100000000000000000000000000000000000000000000000000000000000000"

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gnokey-smoke/lib.sh"

trap cleanup_smoke_env EXIT
setup_smoke_chain
QUERY_TESTDATA_DIR="$SMOKE_TESTDATA_DIR/query"
ZKGM_TESTDATA_DIR="$SMOKE_TESTDATA_DIR/zkgm"

echo ">> Phase 1: register light clients (Sections 0.1, 0.2)"
maketx_run "$QUERY_TESTDATA_DIR/register_clients.gno" "$WORKDIR/register.log"
grep -q 'registered_statelens true' "$WORKDIR/register.log" || { echo "FAIL: state-lens not registered"; cat "$WORKDIR/register.log"; exit 1; }
grep -q 'registered_cometbls true' "$WORKDIR/register.log" || { echo "FAIL: cometbls not registered"; cat "$WORKDIR/register.log"; exit 1; }
echo "PASS: light client registrations"

echo ">> Phase 2: ZKGM app loader check (Section 0.3)"
maketx_run "$QUERY_TESTDATA_DIR/check_zkgm.gno" "$WORKDIR/check_zkgm.log"
grep -q 'zkgm_registered true' "$WORKDIR/check_zkgm.log" || { echo "FAIL: ZKGM app not auto-registered"; cat "$WORKDIR/check_zkgm.log"; exit 1; }
echo "PASS: ZKGM app auto-registered"

echo ">> Phase 3: CreateClient cometbls (Section 1.1)"
maketx_run "$QUERY_TESTDATA_DIR/create_cometbls.gno" "$WORKDIR/create_cometbls.log"
COMETBLS_ID=$(grep -m1 '^cometbls_client_id ' "$WORKDIR/create_cometbls.log" | awk '{print $2}')
if [[ -z "$COMETBLS_ID" ]]; then
  echo "FAIL: cometbls_client_id not captured"
  cat "$WORKDIR/create_cometbls.log"
  exit 1
fi
echo ">> cometbls_client_id=$COMETBLS_ID"

echo ">> Phase 4: UpdateClient cometbls (Section 2)"
render_template "$QUERY_TESTDATA_DIR/update_client.gno.tmpl" "$WORKDIR/update_client.gno" \
  -e "s/@COMETBLS_ID@/$COMETBLS_ID/g"
maketx_run "$WORKDIR/update_client.gno" "$WORKDIR/update_client.log"
UPDATE_HEIGHT=$(grep -m1 '^update_height ' "$WORKDIR/update_client.log" | awk '{print $2}')
if [[ -z "$UPDATE_HEIGHT" ]]; then
  echo "FAIL: update_height not captured"
  cat "$WORKDIR/update_client.log"
  exit 1
fi
echo ">> update_height=$UPDATE_HEIGHT"

echo ">> Phase 5: ConnectionOpenInit (Section 3)"
render_template "$QUERY_TESTDATA_DIR/conn_init.gno.tmpl" "$WORKDIR/conn_init.gno" \
  -e "s/@COMETBLS_ID@/$COMETBLS_ID/g"
maketx_run "$WORKDIR/conn_init.gno" "$WORKDIR/conn_init.log"
CONNECTION_ID=$(grep -m1 '^connection_id ' "$WORKDIR/conn_init.log" | awk '{print $2}')
if [[ -z "$CONNECTION_ID" ]]; then
  echo "FAIL: connection_id not captured"
  cat "$WORKDIR/conn_init.log"
  exit 1
fi
echo ">> connection_id=$CONNECTION_ID"

echo ">> Phase 6: CreateStateLensClient (Section 1.2)"
maketx_run "$QUERY_TESTDATA_DIR/create_statelens.gno" "$WORKDIR/create_statelens.log"
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
maketx_run "$QUERY_TESTDATA_DIR/mock_channels.gno" "$WORKDIR/mock_channels.log"
MOCK_SOURCE=$(grep -m1 '^mock_source ' "$WORKDIR/mock_channels.log" | awk '{print $2}')
MOCK_DEST=$(grep -m1 '^mock_destination ' "$WORKDIR/mock_channels.log" | awk '{print $2}')
if [[ -z "$MOCK_SOURCE" || -z "$MOCK_DEST" ]]; then
  echo "FAIL: mock channel ids not captured"
  cat "$WORKDIR/mock_channels.log"
  exit 1
fi
echo ">> mock_source=$MOCK_SOURCE mock_destination=$MOCK_DEST"

render_template "$QUERY_TESTDATA_DIR/send_batch.gno.tmpl" "$WORKDIR/send.gno" \
  -e "s/@MOCK_SOURCE@/$MOCK_SOURCE/g" \
  -e "s/@MOCK_DEST@/$MOCK_DEST/g"
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
render_template "$ZKGM_TESTDATA_DIR/native_refund_args.gno.tmpl" "$WORKDIR/native_refund_args.gno" \
  -e "s/@REFUND_RECIPIENT@/$REFUND_RECIPIENT/g"
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
render_template "$ZKGM_TESTDATA_DIR/native_refund_ack.gno.tmpl" "$WORKDIR/native_refund_ack.gno" \
  -e "s/@REFUND_OPERAND@/$REFUND_OPERAND/g" \
  -e "s/@REFUND_SOURCE@/$REFUND_SOURCE/g" \
  -e "s/@REFUND_DEST@/$REFUND_DEST/g"
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
