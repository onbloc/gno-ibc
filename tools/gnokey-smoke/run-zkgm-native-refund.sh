#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

SMOKE_GAS_WANTED="${ZKGM_NATIVE_REFUND_GAS_WANTED:-200000000}"

trap cleanup_smoke_env EXIT
setup_smoke_chain
ZKGM_TESTDATA_DIR="$SMOKE_TESTDATA_DIR/zkgm"
SMOKE_KEY_ADDRESS="${SMOKE_KEY_ADDRESS:-g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5}"

echo ">> native TokenOrder ack-failure refund (#58 regression)"

maketx_run "$SMOKE_TESTDATA_DIR/query/setup_impls.gno" "$WORKDIR/setup_impls.log"
maketx_run "$SMOKE_TESTDATA_DIR/query/check_zkgm.gno" "$WORKDIR/check_zkgm.log"

ugnot_amount() {
  local balance="$1"
  if [[ -z "$balance" ]]; then
    echo 0
    return
  fi
  sed -nE 's/^([0-9]+)ugnot$/\1/p' <<<"$balance"
}

# Regression guard for issue #58: a native TokenOrder failure-ack refund routes
# core.PacketAcknowledgement -> impl.Ack -> refundV2 -> sendNative ->
# zkgm.ReleaseNative. ReleaseNative's requireImplCaller must accept the core
# realm as an authorized caller, otherwise the escrow refund panics.
PROXY_ADDR=$(gnokey query vm/qeval -remote "$RPC_ENDPOINT" \
  -data "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm.ProxyAddress()" 2>&1 | extract_data)
if [[ -z "$PROXY_ADDR" ]]; then
  echo "FAIL: could not resolve zkgm proxy address"
  exit 1
fi
REFUND_RECIPIENT="$SMOKE_KEY_ADDRESS"
echo ">> proxy_address=$PROXY_ADDR refund_recipient=$REFUND_RECIPIENT"

# Step 1: create a mock light client, open a fresh channel pair, and encode the
# native ugnot TokenOrder.
# This is the single definition of the order.
maketx_run "$ZKGM_TESTDATA_DIR/native_refund_client.gno" "$WORKDIR/native_refund_client.log"
REFUND_CLIENT_ID=$(sed -nE 's/.*"key":"client_id","value":"([0-9]+)".*/\1/p' "$WORKDIR/native_refund_client.log" | tail -n1)
if [[ -z "$REFUND_CLIENT_ID" ]]; then
  echo "FAIL: could not capture native refund mock client id"
  cat "$WORKDIR/native_refund_client.log"
  exit 1
fi
echo ">> refund mock client id=$REFUND_CLIENT_ID"

render_template "$ZKGM_TESTDATA_DIR/native_refund_connection_init.gno.tmpl" "$WORKDIR/native_refund_connection_init.gno" \
  -e "s/@CLIENT_ID@/$REFUND_CLIENT_ID/g"
maketx_run "$WORKDIR/native_refund_connection_init.gno" "$WORKDIR/native_refund_connection_init.log"
REFUND_CONNECTION_ID=$(sed -nE 's/.*"key":"connection_id","value":"([0-9]+)".*/\1/p' "$WORKDIR/native_refund_connection_init.log" | tail -n1)
if [[ -z "$REFUND_CONNECTION_ID" ]]; then
  echo "FAIL: could not capture native refund connection id"
  cat "$WORKDIR/native_refund_connection_init.log"
  exit 1
fi
echo ">> refund connection id=$REFUND_CONNECTION_ID"

render_template "$ZKGM_TESTDATA_DIR/native_refund_connection_ack.gno.tmpl" "$WORKDIR/native_refund_connection_ack.gno" \
  -e "s/@CONNECTION_ID@/$REFUND_CONNECTION_ID/g"
maketx_run "$WORKDIR/native_refund_connection_ack.gno" "$WORKDIR/native_refund_connection_ack.log"

render_template "$ZKGM_TESTDATA_DIR/native_refund_channel_init.gno.tmpl" "$WORKDIR/native_refund_source_init.gno" \
  -e "s/@CONNECTION_ID@/$REFUND_CONNECTION_ID/g"
maketx_run "$WORKDIR/native_refund_source_init.gno" "$WORKDIR/native_refund_source_init.log"
REFUND_SOURCE=$(sed -nE 's/.*"key":"channel_id","value":"([0-9]+)".*/\1/p' "$WORKDIR/native_refund_source_init.log" | tail -n1)
if [[ -z "$REFUND_SOURCE" ]]; then
  echo "FAIL: could not capture native refund source channel id"
  cat "$WORKDIR/native_refund_source_init.log"
  exit 1
fi

render_template "$ZKGM_TESTDATA_DIR/native_refund_channel_init.gno.tmpl" "$WORKDIR/native_refund_dest_init.gno" \
  -e "s/@CONNECTION_ID@/$REFUND_CONNECTION_ID/g"
maketx_run "$WORKDIR/native_refund_dest_init.gno" "$WORKDIR/native_refund_dest_init.log"
REFUND_DEST=$(sed -nE 's/.*"key":"channel_id","value":"([0-9]+)".*/\1/p' "$WORKDIR/native_refund_dest_init.log" | tail -n1)
if [[ -z "$REFUND_DEST" ]]; then
  echo "FAIL: could not capture native refund destination channel id"
  cat "$WORKDIR/native_refund_dest_init.log"
  exit 1
fi

render_template "$ZKGM_TESTDATA_DIR/native_refund_channel_ack.gno.tmpl" "$WORKDIR/native_refund_source_ack.gno" \
  -e "s/@CHANNEL_ID@/$REFUND_SOURCE/g" \
  -e "s/@COUNTERPARTY_CHANNEL_ID@/$REFUND_DEST/g"
maketx_run "$WORKDIR/native_refund_source_ack.gno" "$WORKDIR/native_refund_source_ack.log"

render_template "$ZKGM_TESTDATA_DIR/native_refund_channel_ack.gno.tmpl" "$WORKDIR/native_refund_dest_ack.gno" \
  -e "s/@CHANNEL_ID@/$REFUND_DEST/g" \
  -e "s/@COUNTERPARTY_CHANNEL_ID@/$REFUND_SOURCE/g"
maketx_run "$WORKDIR/native_refund_dest_ack.gno" "$WORKDIR/native_refund_dest_ack.log"

render_template "$ZKGM_TESTDATA_DIR/native_refund_args.gno.tmpl" "$WORKDIR/native_refund_args.gno" \
  -e "s/@REFUND_SOURCE@/$REFUND_SOURCE/g" \
  -e "s/@REFUND_DEST@/$REFUND_DEST/g" \
  -e "s/@SMOKE_KEY_ADDRESS@/$SMOKE_KEY_ADDRESS/g" \
  -e "s/@REFUND_RECIPIENT@/$REFUND_RECIPIENT/g"
maketx_run "$WORKDIR/native_refund_args.gno" "$WORKDIR/native_refund_args.log"
REFUND_OPERAND=$(grep -m1 '^operand_hex ' "$WORKDIR/native_refund_args.log" | awk '{print $2}')
REFUND_PACKET_DATA=$(grep -m1 '^packet_data_hex ' "$WORKDIR/native_refund_args.log" | awk '{print $2}')
if [[ -z "$REFUND_SOURCE" || -z "$REFUND_DEST" || -z "$REFUND_OPERAND" || -z "$REFUND_PACKET_DATA" ]]; then
  echo "FAIL: could not capture native refund channel pair / operand"
  cat "$WORKDIR/native_refund_args.log"
  exit 1
fi
echo ">> refund channel pair: source=$REFUND_SOURCE destination=$REFUND_DEST"

# Step 2: real native send. This escrows 100ugnot on the proxy realm. `maketx
# run` cannot expose OriginSend to zkgm.SendRaw, and the latest alias realm would
# insert a wrapper frame, so this direct call targets the concrete proxy path.
# SendRaw args: channelId, timeoutTimestamp (far-future), salt (32 zero bytes),
# version 2 (INSTR_VERSION_2), opcode 3 (OP_TOKEN_ORDER), operandHex.
PROXY_BAL_INITIAL=$(native_balance "$PROXY_ADDR")
RECIPIENT_BAL_INITIAL=$(native_balance "$REFUND_RECIPIENT")
PROXY_AMOUNT_INITIAL=$(ugnot_amount "$PROXY_BAL_INITIAL")
RECIPIENT_AMOUNT_INITIAL=$(ugnot_amount "$RECIPIENT_BAL_INITIAL")

maketx_call "$WORKDIR/native_refund_send.log" \
  -pkgpath "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm" \
  -func SendRaw \
  -args "$REFUND_SOURCE" \
  -args "2000000000000000000" \
  -args "0000000000000000000000000000000000000000000000000000000000000000" \
  -args "2" \
  -args "3" \
  -args "$REFUND_OPERAND" \
  -send "100ugnot"

PROXY_BAL_BEFORE=$(native_balance "$PROXY_ADDR")
PROXY_AMOUNT_BEFORE=$(ugnot_amount "$PROXY_BAL_BEFORE")
if [[ "$PROXY_AMOUNT_BEFORE" != "$((PROXY_AMOUNT_INITIAL + 100))" ]]; then
  echo "FAIL: expected proxy escrow to increase by 100ugnot after SendRaw, before='$PROXY_BAL_INITIAL' after='$PROXY_BAL_BEFORE'"
  exit 1
fi
echo "PASS: SendRaw escrowed 100ugnot on the proxy realm"

# Step 3: commit the packet and deliver a failure ack through the core callback.
# The packet is rebuilt from the operand captured in step 1, so the TokenOrder
# is defined once (in native_refund_args.gno) and cannot drift between the send
# and the ack.
render_template "$ZKGM_TESTDATA_DIR/native_refund_ack.gno.tmpl" "$WORKDIR/native_refund_ack.gno" \
  -e "s/@REFUND_PACKET_DATA@/$REFUND_PACKET_DATA/g" \
  -e "s/@REFUND_SOURCE@/$REFUND_SOURCE/g" \
  -e "s/@REFUND_DEST@/$REFUND_DEST/g"
maketx_run "$WORKDIR/native_refund_ack.gno" "$WORKDIR/native_refund_ack.log"
grep -q 'RESULT native ack-failure refund succeeded' "$WORKDIR/native_refund_ack.log" \
  || { echo "FAIL: native ack-failure refund did not complete"; cat "$WORKDIR/native_refund_ack.log"; exit 1; }

PROXY_BAL_AFTER=$(native_balance "$PROXY_ADDR")
RECIPIENT_BAL_AFTER=$(native_balance "$REFUND_RECIPIENT")
PROXY_AMOUNT_AFTER=$(ugnot_amount "$PROXY_BAL_AFTER")
RECIPIENT_AMOUNT_AFTER=$(ugnot_amount "$RECIPIENT_BAL_AFTER")
if [[ "$PROXY_AMOUNT_AFTER" != "$PROXY_AMOUNT_INITIAL" ]]; then
  echo "FAIL: expected proxy escrow to return to '$PROXY_BAL_INITIAL' after refund, got '$PROXY_BAL_AFTER'"
  exit 1
fi
if ! grep -q '"type":"ZkgmNativeReleased"' "$WORKDIR/native_refund_ack.log" ||
  ! grep -q '"key":"recipient","value":"'"$REFUND_RECIPIENT"'"' "$WORKDIR/native_refund_ack.log" ||
  ! grep -q '"key":"amount","value":"100"' "$WORKDIR/native_refund_ack.log"; then
  echo "FAIL: expected native refund release event for $REFUND_RECIPIENT amount 100"
  cat "$WORKDIR/native_refund_ack.log"
  exit 1
fi
if [[ "$REFUND_RECIPIENT" != "$SMOKE_KEY_ADDRESS" && "$RECIPIENT_AMOUNT_AFTER" != "$((RECIPIENT_AMOUNT_INITIAL + 100))" ]]; then
  echo "FAIL: expected recipient balance to increase by 100ugnot, before='$RECIPIENT_BAL_INITIAL' after='$RECIPIENT_BAL_AFTER'"
  exit 1
fi
echo "PASS: native ack-failure refund released the 100ugnot escrow to the sender (#58)"
