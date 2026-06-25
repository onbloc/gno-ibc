#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

trap cleanup_smoke_env EXIT
setup_smoke_chain
QUERY_TESTDATA_DIR="$SMOKE_TESTDATA_DIR/query"

echo ">> Phase 0: install core/zkgm implementations"
maketx_run "$QUERY_TESTDATA_DIR/setup_impls.gno" "$WORKDIR/setup_impls.log"
grep -q 'core_impl_updated' "$WORKDIR/setup_impls.log" || { echo "FAIL: core impl not installed"; cat "$WORKDIR/setup_impls.log"; exit 1; }
grep -q 'zkgm_impl_updated' "$WORKDIR/setup_impls.log" || { echo "FAIL: zkgm impl not installed"; cat "$WORKDIR/setup_impls.log"; exit 1; }

echo ">> Phase 1: register light clients (Sections 0.1, 0.2)"
maketx_run "$QUERY_TESTDATA_DIR/register_clients.gno" "$WORKDIR/register.log"
grep -q 'registered_statelens true' "$WORKDIR/register.log" || { echo "FAIL: state-lens not registered"; cat "$WORKDIR/register.log"; exit 1; }
grep -q 'registered_cometbls true' "$WORKDIR/register.log" || { echo "FAIL: cometbls not registered"; cat "$WORKDIR/register.log"; exit 1; }
echo "PASS: light client registrations"

echo ">> Phase 2: ZKGM app loader check (Section 0.3)"
maketx_run "$QUERY_TESTDATA_DIR/check_zkgm.gno" "$WORKDIR/check_zkgm.log"
grep -q 'zkgm_registered true' "$WORKDIR/check_zkgm.log" || { echo "FAIL: ZKGM app not auto-registered"; cat "$WORKDIR/check_zkgm.log"; exit 1; }
echo "PASS: ZKGM app auto-registered"

echo ">> Phase 3: CreateClient cometbls (Section 1.1)"
maketx_run "$QUERY_TESTDATA_DIR/create_cometbls.gno" "$WORKDIR/create_cometbls.log"
COMETBLS_ID=$(sed -nE 's/.*"key":"client_id","value":"([0-9]+)".*/\1/p' "$WORKDIR/create_cometbls.log" | head -n1)
if [[ -z "$COMETBLS_ID" ]]; then
  echo "FAIL: cometbls_client_id not captured"
  cat "$WORKDIR/create_cometbls.log"
  exit 1
fi
echo ">> cometbls_client_id=$COMETBLS_ID"

echo ">> Phase 4: UpdateClient cometbls (Section 2)"
render_template "$QUERY_TESTDATA_DIR/update_client.gno.tmpl" "$WORKDIR/update_client.gno" \
  -e "s/@COMETBLS_ID@/$COMETBLS_ID/g"
maketx_run "$WORKDIR/update_client.gno" "$WORKDIR/update_client.log"
UPDATE_HEIGHT=$(grep -m1 '^update_height ' "$WORKDIR/update_client.log" | awk '{print $2}')
if [[ -z "$UPDATE_HEIGHT" ]]; then
  echo "FAIL: update_height not captured"
  cat "$WORKDIR/update_client.log"
  exit 1
fi
echo ">> update_height=$UPDATE_HEIGHT"

echo ">> Phase 5: ConnectionOpenInit (Section 3)"
render_template "$QUERY_TESTDATA_DIR/conn_init.gno.tmpl" "$WORKDIR/conn_init.gno" \
  -e "s/@COMETBLS_ID@/$COMETBLS_ID/g"
maketx_run "$WORKDIR/conn_init.gno" "$WORKDIR/conn_init.log"
CONNECTION_ID=$(sed -nE 's/.*"key":"connection_id","value":"([0-9]+)".*/\1/p' "$WORKDIR/conn_init.log" | head -n1)
if [[ -z "$CONNECTION_ID" ]]; then
  echo "FAIL: connection_id not captured"
  cat "$WORKDIR/conn_init.log"
  exit 1
fi
echo ">> connection_id=$CONNECTION_ID"

echo ">> Phase 6: CreateStateLensClient (Section 1.2)"
maketx_run "$QUERY_TESTDATA_DIR/create_statelens.gno" "$WORKDIR/create_statelens.log"
STATELENS_ID=$(sed -nE 's/.*"key":"client_id","value":"([0-9]+)".*/\1/p' "$WORKDIR/create_statelens.log" | head -n1)
if [[ -z "$STATELENS_ID" ]]; then
  echo "FAIL: statelens_client_id not captured"
  cat "$WORKDIR/create_statelens.log"
  exit 1
fi
echo ">> statelens_client_id=$STATELENS_ID"

echo ">> SKIP Sections 4-6 (ConnectionOpen{Try,Ack,Confirm}): need Union counterparty proofs"
echo ">> SKIP Section 7 (ChannelOpenInit): needs an established connection"
echo ">> SKIP Sections 8-10 (ChannelOpen{Try,Ack,Confirm}): need Union counterparty proofs"
echo ">> SKIP mock ZKGM channel pair + BatchSend: maketx run cannot import testing/e2e helper realm"

echo ">> Phase 8: qeval probes"

render_template "$QUERY_TESTDATA_DIR/qeval_cases.tsv.tmpl" "$WORKDIR/qeval_cases.tsv" \
  -e "s/@COMETBLS_ID@/$COMETBLS_ID/g" \
  -e "s/@STATELENS_ID@/$STATELENS_ID/g" \
  -e "s/@CONNECTION_ID@/$CONNECTION_ID/g" \
  -e "s/@UPDATE_HEIGHT@/$UPDATE_HEIGHT/g"

while IFS=$'\t' read -r mode label expr expected; do
  [[ -z "$mode" || "$mode" == \#* ]] && continue

  case "$mode" in
    nonempty)
      probe_qeval_nonempty "$label" "$expr"
      ;;
    exact)
      [[ "$expected" == "__EMPTY__" ]] && expected=""
      probe_qeval "$label" "$expr" "$expected"
      ;;
    *)
      echo "FAIL: unknown qeval case mode '$mode' for '$label'"
      exit 1
      ;;
  esac
done <"$WORKDIR/qeval_cases.tsv"

echo "all qeval smoke assertions passed"
