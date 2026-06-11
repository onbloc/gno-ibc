#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

trap cleanup_smoke_env EXIT
setup_smoke_chain
ZKGM_TESTDATA_DIR="$SMOKE_TESTDATA_DIR/zkgm"
TOKEN_PKGPATH="gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/smoketoken"
SENDER_ADDR="g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5" # test1
AMOUNT=100

echo ">> GRC20 TokenOrder ack-failure refund"
PROXY_ADDR=$(gnokey query vm/qeval -remote "$RPC_ENDPOINT" \
  -data "gno.land/r/onbloc/unionibc/v1/apps/zkgm.ProxyAddress()" 2>&1 | extract_data)
if [[ -z "$PROXY_ADDR" ]]; then
  echo "FAIL: could not resolve zkgm proxy address"
  exit 1
fi
echo ">> proxy_address=$PROXY_ADDR sender=$SENDER_ADDR token=$TOKEN_PKGPATH"

maketx_addpkg "$TOKEN_PKGPATH" "$ZKGM_TESTDATA_DIR/grc20token" "$WORKDIR/token_addpkg.log"
probe_qeval "token registered" "$TOKEN_PKGPATH.BalanceOf(\"$PROXY_ADDR\")" "0"

maketx_call "$WORKDIR/faucet.log" \
  -pkgpath "$TOKEN_PKGPATH" \
  -func Faucet \
  -args "$AMOUNT"
probe_qeval "test1 funded" "$TOKEN_PKGPATH.BalanceOf(\"$SENDER_ADDR\")" "$AMOUNT"

maketx_call "$WORKDIR/approve.log" \
  -pkgpath "$TOKEN_PKGPATH" \
  -func Approve \
  -args "$PROXY_ADDR" \
  -args "$AMOUNT"
probe_qeval "approval set" "$TOKEN_PKGPATH.Allowance(\"$SENDER_ADDR\",\"$PROXY_ADDR\")" "$AMOUNT"

render_template "$ZKGM_TESTDATA_DIR/grc20_refund_args.gno.tmpl" "$WORKDIR/grc20_refund_args.gno" \
  -e "s|@SENDER@|$SENDER_ADDR|g" \
  -e "s|@DENOM@|$TOKEN_PKGPATH|g"
maketx_run "$WORKDIR/grc20_refund_args.gno" "$WORKDIR/grc20_refund_args.log"
REFUND_SOURCE=$(grep -m1 '^source_channel ' "$WORKDIR/grc20_refund_args.log" | awk '{print $2}')
REFUND_DEST=$(grep -m1 '^destination_channel ' "$WORKDIR/grc20_refund_args.log" | awk '{print $2}')
REFUND_OPERAND=$(grep -m1 '^operand_hex ' "$WORKDIR/grc20_refund_args.log" | awk '{print $2}')
if [[ -z "$REFUND_SOURCE" || -z "$REFUND_DEST" || -z "$REFUND_OPERAND" ]]; then
  echo "FAIL: could not capture GRC20 refund channel pair / operand"
  cat "$WORKDIR/grc20_refund_args.log"
  exit 1
fi
echo ">> refund channel pair: source=$REFUND_SOURCE destination=$REFUND_DEST"

maketx_call "$WORKDIR/grc20_refund_send.log" \
  -pkgpath "gno.land/r/onbloc/unionibc/v1/apps/zkgm" \
  -func SendRaw \
  -args "$REFUND_SOURCE" \
  -args "2000000000000000000" \
  -args "0000000000000000000000000000000000000000000000000000000000000000" \
  -args "2" \
  -args "3" \
  -args "$REFUND_OPERAND"

probe_qeval "proxy escrowed" "$TOKEN_PKGPATH.BalanceOf(\"$PROXY_ADDR\")" "$AMOUNT"
probe_qeval "sender drained" "$TOKEN_PKGPATH.BalanceOf(\"$SENDER_ADDR\")" "0"

render_template "$ZKGM_TESTDATA_DIR/native_refund_ack.gno.tmpl" "$WORKDIR/grc20_refund_ack.gno" \
  -e "s/@REFUND_OPERAND@/$REFUND_OPERAND/g" \
  -e "s/@REFUND_SOURCE@/$REFUND_SOURCE/g" \
  -e "s/@REFUND_DEST@/$REFUND_DEST/g"
maketx_run "$WORKDIR/grc20_refund_ack.gno" "$WORKDIR/grc20_refund_ack.log"
grep -q 'commitment_before_ack true' "$WORKDIR/grc20_refund_ack.log" \
  || { echo "FAIL: packet commitment missing before ack"; cat "$WORKDIR/grc20_refund_ack.log"; exit 1; }
grep -q 'commitment_after_ack false' "$WORKDIR/grc20_refund_ack.log" \
  || { echo "FAIL: packet commitment not cleared after ack"; cat "$WORKDIR/grc20_refund_ack.log"; exit 1; }
grep -q 'RESULT .*ack-failure refund succeeded' "$WORKDIR/grc20_refund_ack.log" \
  || { echo "FAIL: GRC20 ack-failure refund did not complete"; cat "$WORKDIR/grc20_refund_ack.log"; exit 1; }

probe_qeval "proxy drained after refund" "$TOKEN_PKGPATH.BalanceOf(\"$PROXY_ADDR\")" "0"
probe_qeval "sender refunded" "$TOKEN_PKGPATH.BalanceOf(\"$SENDER_ADDR\")" "$AMOUNT"
echo "PASS: GRC20 ack-failure refund released the escrow back to the sender"
