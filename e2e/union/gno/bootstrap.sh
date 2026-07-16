#!/bin/bash
set -eu

printf "%s\n\n" "$ADMIN_MNEMONIC" | gnokey add admin --recover --insecure-password-stdin --force >/dev/null
printf "\n" | gnokey maketx run \
  -gas-fee 1000000ugnot \
  -gas-wanted 90000000 \
  -broadcast \
  -chainid "${GNO_CHAIN_ID:-dev}" \
  -remote "${GNO_GNOKEY_REMOTE:-gno:26657}" \
  -insecure-password-stdin \
  admin /bootstrap.gno
