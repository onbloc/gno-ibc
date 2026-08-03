#!/bin/bash
set -eu

remote=http://gno:26657
chain_id=dev.ibc
admin_addr=g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5
setup_pkg=gno.land/r/onbloc/ibc/union/testing/e2e_setup
zkgm_pkg=gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm

printf '%s\n\n' "$ADMIN_MNEMONIC" |
  gnokey add admin --recover --insecure-password-stdin --force >/dev/null

query_address() {
  gnokey query vm/qeval -remote "$remote" -data "$1" 2>&1 |
    sed -n 's/.*("\(g1[^"]*\)" string).*/\1/p'
}

is_bootstrapped() {
  gnokey query vm/qeval -remote "$remote" \
    -data "gno.land/r/onbloc/ibc/union/core.HasApp([]byte(\"$zkgm_pkg\"))" 2>&1 |
    grep -q '(true bool)'
}

if is_bootstrapped; then
  echo 'Gno E2E setup already bootstrapped'
  exit 0
fi

grant_role() {
  printf '\n' | gnokey maketx call \
    -gas-fee 1000000ugnot \
    -gas-wanted 90000000 \
    -broadcast \
    -chainid "$chain_id" \
    -remote "$remote" \
    -insecure-password-stdin \
    -pkgpath gno.land/r/onbloc/ibc/union/access \
    -func GrantRole \
    -args "$1" \
    -args "$2" \
    admin
}

setup_addr=$(query_address "$setup_pkg.Address()")
cometbls_addr=$(query_address "$setup_pkg.PackageAddress(\"gno.land/r/onbloc/ibc/union/lightclients/cometbls\")")
statelens_addr=$(query_address "$setup_pkg.PackageAddress(\"gno.land/r/onbloc/ibc/union/lightclients/statelensics23mpt\")")

test -n "$setup_addr" && test -n "$cometbls_addr" && test -n "$statelens_addr"

grant_role 1 "$admin_addr"
grant_role 0 "$setup_addr"
grant_role 1 "$setup_addr"
grant_role 1 "$cometbls_addr"
grant_role 1 "$statelens_addr"

printf '\n' | gnokey maketx call \
  -gas-fee 1000000ugnot \
  -gas-wanted 90000000 \
  -broadcast \
  -chainid "$chain_id" \
  -remote "$remote" \
  -insecure-password-stdin \
  -pkgpath "$setup_pkg" \
  -func Bootstrap \
  admin

is_bootstrapped
echo 'Gno E2E setup complete'
