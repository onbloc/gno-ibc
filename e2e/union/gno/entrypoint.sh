#!/bin/bash
set -eu

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

printf "%s\n\n" "$RELAYER_MNEMONIC" | gnokey add relayer --recover --insecure-password-stdin --force >/dev/null
RELAYER_ADDR=$(key_addr relayer)

ADMIN_ADDR="${ADMIN_ADDR:-g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5}"
TEST_ADDR="${TEST_ADDR:-g1z437dpuh5s4p64vtq09dulg6jzxpr2hd4q8r5x}"

account_args=()
add_account() {
  for account in "${account_args[@]}"; do
    [ "$account" = "$1" ] && return
  done
  account_args+=("-add-account" "$1")
}

add_account "${ADMIN_ADDR}=100000000000ugnot"
add_account "${TEST_ADDR}=100000000000ugnot"
add_account "${RELAYER_ADDR}=100000000000ugnot"

exec gnodev local \
  -C /gno-ibc \
  -root /gnoroot \
  -extra-root /gno-ibc \
  -node-rpc-listener 0.0.0.0:26657 \
  -web-listener 0.0.0.0:8888 \
  -web-help-remote http://127.0.0.1:26657 \
  -empty-blocks \
  -no-watch \
  "${account_args[@]}" \
  -paths "gno.land/r/onbloc/ibc/union/access,gno.land/r/onbloc/ibc/union/core,gno.land/r/onbloc/ibc/union/core/v1,gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm,gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
