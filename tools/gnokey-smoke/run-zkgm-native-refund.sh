#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

trap cleanup_smoke_env EXIT
setup_smoke_chain
ZKGM_TESTDATA_DIR="$SMOKE_TESTDATA_DIR/zkgm"
SENDER_ADDR="g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5" # test1

echo ">> native TokenOrder ack-failure refund (#58 regression)"
# Regression guard for issue #58: a native TokenOrder failure-ack refund routes
# core.PacketAcknowledgement -> impl.Ack -> refundV2 -> sendNative ->
# zkgm.ReleaseNative. ReleaseNative's requireImplCaller must accept the core
# realm as an authorized caller, otherwise the escrow refund panics.
PROXY_ADDR=$(gnokey query vm/qeval -remote "$RPC_ENDPOINT" \
  -data "gno.land/r/onbloc/unionibc/v1/apps/zkgm.ProxyAddress()" 2>&1 | extract_data)
if [[ -z "$PROXY_ADDR" ]]; then
  echo "FAIL: could not resolve zkgm proxy address"
  exit 1
fi
echo ">> proxy_address=$PROXY_ADDR sender=$SENDER_ADDR"

# Step 1: open a fresh channel pair and encode the native ugnot TokenOrder.
# This is the single definition of the order.
render_template "$ZKGM_TESTDATA_DIR/native_refund_args.gno.tmpl" "$WORKDIR/native_refund_args.gno" \
  -e "s/@SENDER@/$SENDER_ADDR/g"
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
  -pkgpath "gno.land/r/onbloc/unionibc/v1/apps/zkgm" \
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
if [[ -n "$PROXY_BAL_AFTER" ]]; then
  echo "FAIL: expected proxy escrow drained after refund, got '$PROXY_BAL_AFTER'"
  exit 1
fi
echo "PASS: native ack-failure refund released the 100ugnot escrow to the sender (#58)"
