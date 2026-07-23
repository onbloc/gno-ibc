#!/bin/bash
set -eu

GNO_CHAIN_ID="${GNO_CHAIN_ID:-dev}"
GNO_GNOKEY_REMOTE="${GNO_GNOKEY_REMOTE:-gno:26657}"
ADMIN_MNEMONIC="${ADMIN_MNEMONIC:-$TEST_MNEMONIC}"
VOYAGER_CONFIG="${VOYAGER_CONFIG:-/voyager-config.gno-union.jsonc}"
SETUP_PKG="gno.land/r/onbloc/ibc/union/testing/e2e_setup"
ADMIN_ROLE=0
RELAYER_ROLE=1

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
VOYAGER_RAW_KEY=$(awk '
  /voyager-transaction-plugin-gno/ { plugin = 1 }
  plugin && /"key":/ {
    line = $0
    sub(/^.*"key":[[:space:]]*"/, "", line)
    sub(/".*$/, "", line)
    print line
    exit
  }
' "$VOYAGER_CONFIG")
[ -n "$VOYAGER_RAW_KEY" ] || {
  echo "Voyager Gno signer key not found" >&2
  exit 1
}
[ "${VOYAGER_RAW_KEY,,}" = "$(printf '%s\n' "$ADMIN_MNEMONIC" | mnemonic-raw-key)" ] || {
  echo "admin mnemonic does not match the Voyager Gno signer key" >&2
  exit 1
}

query_address() {
  gnokey query vm/qeval -remote "$GNO_GNOKEY_REMOTE" -data "$1" 2>&1 |
    sed -n 's/.*("\(g1[^"]*\)" string).*/\1/p'
}

SETUP_ADDR=$(query_address "$SETUP_PKG.Address()")
[ -n "$SETUP_ADDR" ] || {
  echo "failed to resolve E2E setup realm address" >&2
  exit 1
}
COMETBLS_ADDR=$(query_address "$SETUP_PKG.PackageAddress(\"gno.land/r/onbloc/ibc/union/lightclients/cometbls\")")
STATELENS_ADDR=$(query_address "$SETUP_PKG.PackageAddress(\"gno.land/r/onbloc/ibc/union/lightclients/statelensics23mpt\")")
[ -n "$COMETBLS_ADDR" ] && [ -n "$STATELENS_ADDR" ] || {
  echo "failed to resolve light-client realm addresses" >&2
  exit 1
}

grant_role() {
  role="$1"
  account="$2"
  printf "\n" | gnokey maketx call \
    -gas-fee 1000000ugnot \
    -gas-wanted 90000000 \
    -broadcast \
    -chainid "$GNO_CHAIN_ID" \
    -remote "$GNO_GNOKEY_REMOTE" \
    -insecure-password-stdin \
    -pkgpath gno.land/r/onbloc/ibc/union/access \
    -func GrantRole \
    -args "$role" \
    -args "$account" \
    admin
}

echo "Granting relayer role to $ADMIN_ADDR and setup roles to $SETUP_ADDR"
grant_role "$RELAYER_ROLE" "$ADMIN_ADDR"
grant_role "$ADMIN_ROLE" "$SETUP_ADDR"
grant_role "$RELAYER_ROLE" "$SETUP_ADDR"
grant_role "$RELAYER_ROLE" "$COMETBLS_ADDR"
grant_role "$RELAYER_ROLE" "$STATELENS_ADDR"
