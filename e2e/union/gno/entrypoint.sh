#!/bin/bash
set -eu

printf '%s\n\n' "$TEST_MNEMONIC" |
  gnokey add sender --recover --insecure-password-stdin --force >/dev/null

exec gnodev local \
  -chain-id dev.ibc \
  -C /gno-ibc \
  -root /gnoroot \
  -extra-root /gno-ibc \
  -node-rpc-listener 0.0.0.0:26657 \
  -web-listener 0.0.0.0:8888 \
  -web-help-remote http://127.0.0.1:26657 \
  -empty-blocks \
  -no-watch \
  -add-account g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5=100000000000ugnot \
  -add-account g1z437dpuh5s4p64vtq09dulg6jzxpr2hd4q8r5x=100000000000ugnot \
  -paths "gno.land/r/onbloc/ibc/union/access,gno.land/r/onbloc/ibc/union/core,gno.land/r/onbloc/ibc/union/core/v1,gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm,gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1,gno.land/r/onbloc/ibc/union/testing/e2e_setup"

