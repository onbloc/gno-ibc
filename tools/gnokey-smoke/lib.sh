#!/usr/bin/env bash

GNO_SMOKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SMOKE_TESTDATA_DIR="$GNO_SMOKE_DIR/testdata"
GNO_IBC_ROOT="${GNO_IBC_ROOT:-$(cd "$GNO_SMOKE_DIR/../.." && pwd)}"
GNO_ROOT="${GNO_ROOT:-$HOME/.cache/gno-ibc/gno}"
RPC_ENDPOINT="${RPC_ENDPOINT:-tcp://127.0.0.1:26657}"
RPC_URL="${RPC_URL:-http://127.0.0.1:26657}"
RPC_LISTENER="${RPC_LISTENER:-0.0.0.0:26657}"
CHAIN_ID="${CHAIN_ID:-dev}"
SMOKE_KEY_NAME="${SMOKE_KEY_NAME:-test1}"
SMOKE_GAS_FEE="${SMOKE_GAS_FEE:-1000000ugnot}"
SMOKE_GAS_WANTED="${SMOKE_GAS_WANTED:-90000000}"
TEST1_MNEMONIC="${TEST1_MNEMONIC:-source bonus chronic canvas draft south burst lottery vacant surface solve popular case indicate oppose farm nothing bullet exhibit title speed wink action roast}"

init_smoke_env() {
  WORKDIR="${WORKDIR:-$(mktemp -d)}"
  KEYBASE="${KEYBASE:-$WORKDIR/keybase}"
}

cleanup_smoke_env() {
  if [[ -n "${GNODEV_PID:-}" ]] && kill -0 "$GNODEV_PID" 2>/dev/null; then
    kill "$GNODEV_PID" 2>/dev/null || true
    wait "$GNODEV_PID" 2>/dev/null || true
  fi
  if [[ -n "${WORKDIR:-}" ]]; then
    rm -rf "$WORKDIR"
  fi
}

run_smoke_node() {
  # local resolvers map each on-disk gno.land/{p,r}/core/ibc directory to the
  # onbloc/{ibc,unionibc} module path it declares; unneeded once directories
  # match module paths, required while the directory layout is kept.
  gnodev local \
    -root "$GNO_ROOT" \
    -resolver "root=$GNO_IBC_ROOT" \
    -resolver "root=$GNO_ROOT/examples" \
    -resolver "local=$GNO_IBC_ROOT/gno.land/p/core/ibc/zkgm" \
    -resolver "local=$GNO_IBC_ROOT/gno.land/p/core/tokenbucket" \
    -resolver "local=$GNO_IBC_ROOT/gno.land/p/core/ibc/lightclients/cometbls" \
    -resolver "local=$GNO_IBC_ROOT/gno.land/p/core/ibc/lightclients/statelensics23mpt" \
    -resolver "local=$GNO_IBC_ROOT/gno.land/r/core/ibc/v1/core" \
    -resolver "local=$GNO_IBC_ROOT/gno.land/r/core/ibc/v1/lightclients/cometbls" \
    -resolver "local=$GNO_IBC_ROOT/gno.land/r/core/ibc/v1/lightclients/statelensics23mpt" \
    -resolver "local=$GNO_IBC_ROOT/gno.land/r/core/ibc/v1/apps/zkgm" \
    -resolver "local=$GNO_IBC_ROOT/gno.land/r/core/ibc/v1/apps/zkgm/v0/impl" \
    -resolver "local=$GNO_IBC_ROOT/gno.land/r/core/ibc/v1/apps/zkgm/v0/loader" \
    -resolver "local=$GNO_IBC_ROOT/gno.land/r/core/ibc/v1/apps/zkgm/testing/loader" \
    -resolver "local=$GNO_IBC_ROOT/gno.land/r/core/ibc/v1/apps/zkgm/testing/realcometbls" \
    -resolver "local=$GNO_IBC_ROOT/gno.land/r/core/ibc/v1/apps/zkgm/testing/e2e" \
    -paths "gno.land/r/onbloc/unionibc/v1/core,gno.land/r/onbloc/unionibc/v1/lightclients/cometbls,gno.land/r/onbloc/unionibc/v1/lightclients/statelensics23mpt,gno.land/r/onbloc/unionibc/v1/apps/zkgm,gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/impl,gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/loader,gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e" \
    -no-web \
    -node-rpc-listener "$RPC_LISTENER"
}

start_smoke_node() {
  init_smoke_env

  echo ">> starting gnodev on 127.0.0.1:26657"
  run_smoke_node >"$WORKDIR/gnodev.log" 2>&1 &
  GNODEV_PID=$!

  local deadline=$((SECONDS + 60))
  while (( SECONDS < deadline )); do
    if curl -sf "$RPC_URL/status" 2>/dev/null | grep -q latest_block_height; then
      break
    fi
    if ! kill -0 "$GNODEV_PID" 2>/dev/null; then
      echo "gnodev exited unexpectedly"
      cat "$WORKDIR/gnodev.log"
      exit 1
    fi
    sleep 1
  done

  if ! curl -sf "$RPC_URL/status" 2>/dev/null | grep -q latest_block_height; then
    echo "gnodev not ready within 60s"
    cat "$WORKDIR/gnodev.log"
    exit 1
  fi
  echo ">> gnodev ready"
}

recover_smoke_key() {
  init_smoke_env

  echo ">> importing $SMOKE_KEY_NAME into local keybase"
  if ! printf "%s\n\n\n" "$TEST1_MNEMONIC" | gnokey add "$SMOKE_KEY_NAME" -recover -insecure-password-stdin=true -home "$KEYBASE" >"$WORKDIR/keyadd.log" 2>&1; then
    echo "FAIL: gnokey add $SMOKE_KEY_NAME"
    cat "$WORKDIR/keyadd.log"
    exit 1
  fi
}

setup_smoke_chain() {
  init_smoke_env
  start_smoke_node
  recover_smoke_key
}

maketx_run() {
  local script="$1"
  local log="$2"
  echo "--- maketx run: $(basename "$script") ---"
  if ! echo "" | gnokey maketx run -insecure-password-stdin \
    -home "$KEYBASE" \
    -gas-fee "$SMOKE_GAS_FEE" -gas-wanted "$SMOKE_GAS_WANTED" \
    -broadcast -chainid "$CHAIN_ID" -remote "$RPC_ENDPOINT" \
    "$SMOKE_KEY_NAME" "$script" 2>&1 | tee "$log"; then
    echo "FAIL: maketx run failed ($(basename "$script"))"
    exit 1
  fi
  echo "--- end maketx run ---"
}

# maketx_call <log> <gnokey maketx call flags...>. Unlike maketx run, a direct
# call exposes -send / OriginSend to the target realm, which zkgm.SendRaw needs.
maketx_call() {
  local log="$1"
  shift
  echo "--- maketx call ---"
  if ! echo "" | gnokey maketx call -insecure-password-stdin \
    -home "$KEYBASE" \
    -gas-fee "$SMOKE_GAS_FEE" -gas-wanted "$SMOKE_GAS_WANTED" \
    -broadcast -chainid "$CHAIN_ID" -remote "$RPC_ENDPOINT" \
    "$@" "$SMOKE_KEY_NAME" 2>&1 | tee "$log"; then
    echo "FAIL: maketx call failed"
    exit 1
  fi
  echo "--- end maketx call ---"
}

# maketx_addpkg <pkgpath> <pkgdir> [log]. Deploys a package to the running
# gnodev chain. Unlike maketx run, addpkg creates a persistent realm that
# survives across subsequent ephemeral maketx run scripts.
maketx_addpkg() {
  local pkgpath="$1"
  local pkgdir="$2"
  local log="${3:-$WORKDIR/addpkg.log}"
  echo "--- maketx addpkg: $pkgpath ---"
  if ! echo "" | gnokey maketx addpkg -insecure-password-stdin \
    -home "$KEYBASE" \
    -pkgpath "$pkgpath" \
    -pkgdir "$pkgdir" \
    -gas-fee "$SMOKE_GAS_FEE" -gas-wanted "$SMOKE_GAS_WANTED" \
    -broadcast -chainid "$CHAIN_ID" -remote "$RPC_ENDPOINT" \
    "$SMOKE_KEY_NAME" 2>&1 | tee "$log"; then
    echo "FAIL: maketx addpkg failed ($pkgpath)"
    exit 1
  fi
  echo "--- end maketx addpkg ---"
}

extract_data() {
  grep -E '^data:' | sed -nE \
    -e 's/^data: \("(.*)" [^)]+\)$/\1/p' \
    -e 's/^data: \(([^ ]+) [^)]+\)$/\1/p'
}

# native_balance <address> prints the bank balance string, e.g. "100ugnot".
native_balance() {
  gnokey query "bank/balances/$1" -remote "$RPC_ENDPOINT" 2>&1 \
    | sed -nE 's/^data: "(.*)"$/\1/p'
}

probe_qeval() {
  local label="$1"
  local data="$2"
  local expected="$3"
  local raw actual
  raw=$(gnokey query vm/qeval -remote "$RPC_ENDPOINT" -data "$data" 2>&1)
  echo "--- qeval: $label ---"
  echo "expr: $data"
  echo "$raw"
  actual=$(echo "$raw" | extract_data)
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $label"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    exit 1
  fi
  echo "PASS: $label"
}

probe_qeval_nonempty() {
  local label="$1"
  local data="$2"
  local raw actual
  raw=$(gnokey query vm/qeval -remote "$RPC_ENDPOINT" -data "$data" 2>&1)
  echo "--- qeval: $label ---"
  echo "expr: $data"
  echo "$raw"
  actual=$(echo "$raw" | extract_data)
  if [[ -z "$actual" ]]; then
    echo "FAIL: $label expected non-empty, got empty"
    exit 1
  fi
  echo "PASS: $label"
}

hex_to_h256_lit() {
  local hex="${1#0x}"
  local out="H256{"
  for i in $(seq 0 31); do
    [ "$i" -gt 0 ] && out+=","
    out+="0x${hex:$((i*2)):2}"
  done
  out+="}"
  echo "$out"
}

render_template() {
  local template="$1"
  local output="$2"
  shift 2
  sed "$@" "$template" >"$output"
}
