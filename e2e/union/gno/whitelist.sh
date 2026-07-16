#!/bin/bash
set -eu

GNO_CHAIN_ID="${GNO_CHAIN_ID:-dev}"
GNO_GNOKEY_REMOTE="${GNO_GNOKEY_REMOTE:-gno:26657}"
ADMIN_MNEMONIC="${ADMIN_MNEMONIC:-$TEST_MNEMONIC}"

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

printf "%s\n\n" "$ADMIN_MNEMONIC" | gnokey add admin --recover --insecure-password-stdin --force >/dev/null
ADMIN_ADDR=$(key_addr admin)
[ "$ADMIN_ADDR" = "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5" ] || {
  echo "admin mnemonic does not match the Voyager Gno signer" >&2
  exit 1
}

echo "Granting Gno Union relayer role to $ADMIN_ADDR"
printf "\n" | gnokey maketx call \
  -gas-fee 1000000ugnot \
  -gas-wanted 90000000 \
  -broadcast \
  -chainid "$GNO_CHAIN_ID" \
  -remote "$GNO_GNOKEY_REMOTE" \
  -insecure-password-stdin \
  -pkgpath gno.land/r/onbloc/ibc/union/access \
  -func GrantRole \
  -args 1 \
  -args "$ADMIN_ADDR" \
  admin
