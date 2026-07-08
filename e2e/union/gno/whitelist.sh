#!/bin/bash
set -eu

GNO_CHAIN_ID="${GNO_CHAIN_ID:-dev}"
GNO_GNOKEY_REMOTE="${GNO_GNOKEY_REMOTE:-gno:26657}"
ADMIN_MNEMONIC="${ADMIN_MNEMONIC:-$TEST_MNEMONIC}"

printf "%s\n\n" "$RELAYER_MNEMONIC" | gnokey add relayer --recover --insecure-password-stdin --force >/dev/null
RELAYER_ADDR=$(gnokey list 2>&1 | sed -n 's/.*addr: \([^ ]*\).*/\1/p' | head -n1)

printf "%s\n\n" "$ADMIN_MNEMONIC" | gnokey add admin --recover --insecure-password-stdin --force >/dev/null
ADMIN_ADDR=$(gnokey list 2>&1 | sed -n 's/.*addr: \([^ ]*\).*/\1/p' | head -n1)

echo "Granting Gno Union relayer role to $RELAYER_ADDR with admin $ADMIN_ADDR"
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
  -args "$RELAYER_ADDR" \
  admin
