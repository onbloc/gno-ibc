#!/usr/bin/env bash
set -euo pipefail

EXPECTED_HIT="0x0100000000000000000000000000000000000000000000000000000000000000"

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

trap cleanup_smoke_env EXIT
setup_smoke_chain
QUERY_TESTDATA_DIR="$SMOKE_TESTDATA_DIR/query"

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
COMETBLS_ID=$(grep -m1 '^cometbls_client_id ' "$WORKDIR/create_cometbls.log" | awk '{print $2}')
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
CONNECTION_ID=$(grep -m1 '^connection_id ' "$WORKDIR/conn_init.log" | awk '{print $2}')
if [[ -z "$CONNECTION_ID" ]]; then
  echo "FAIL: connection_id not captured"
  cat "$WORKDIR/conn_init.log"
  exit 1
fi
echo ">> connection_id=$CONNECTION_ID"

echo ">> Phase 6: CreateStateLensClient (Section 1.2)"
maketx_run "$QUERY_TESTDATA_DIR/create_statelens.gno" "$WORKDIR/create_statelens.log"
STATELENS_ID=$(grep -m1 '^statelens_client_id ' "$WORKDIR/create_statelens.log" | awk '{print $2}')
if [[ -z "$STATELENS_ID" ]]; then
  echo "FAIL: statelens_client_id not captured"
  cat "$WORKDIR/create_statelens.log"
  exit 1
fi
echo ">> statelens_client_id=$STATELENS_ID"

echo ">> SKIP Sections 4-6 (ConnectionOpen{Try,Ack,Confirm}): need Union counterparty proofs"
echo ">> SKIP Section 7 (ChannelOpenInit): depends on open connection, covered by mock path"
echo ">> SKIP Sections 8-10 (ChannelOpen{Try,Ack,Confirm}): need Union counterparty proofs"

echo ">> Phase 7: mock ZKGM channel pair + BatchSend"
maketx_run "$QUERY_TESTDATA_DIR/mock_channels.gno" "$WORKDIR/mock_channels.log"
MOCK_SOURCE=$(grep -m1 '^mock_source ' "$WORKDIR/mock_channels.log" | awk '{print $2}')
MOCK_DEST=$(grep -m1 '^mock_destination ' "$WORKDIR/mock_channels.log" | awk '{print $2}')
if [[ -z "$MOCK_SOURCE" || -z "$MOCK_DEST" ]]; then
  echo "FAIL: mock channel ids not captured"
  cat "$WORKDIR/mock_channels.log"
  exit 1
fi
echo ">> mock_source=$MOCK_SOURCE mock_destination=$MOCK_DEST"

render_template "$QUERY_TESTDATA_DIR/send_batch.gno.tmpl" "$WORKDIR/send.gno" \
  -e "s/@MOCK_SOURCE@/$MOCK_SOURCE/g" \
  -e "s/@MOCK_DEST@/$MOCK_DEST/g"
maketx_run "$WORKDIR/send.gno" "$WORKDIR/send.log"
BATCH_HASH=$(grep -m1 '^batch_hash ' "$WORKDIR/send.log" | awk '{print $2}')
if [[ -z "$BATCH_HASH" ]]; then
  echo "FAIL: batch_hash not captured"
  cat "$WORKDIR/send.log"
  exit 1
fi
echo ">> batch_hash=$BATCH_HASH"
BATCH_HASH_LIT=$(hex_to_h256_lit "$BATCH_HASH")

echo ">> Phase 8: qeval probes"

probe_qeval_nonempty "GetClientType(cometbls_id=$COMETBLS_ID)" \
  "gno.land/r/core/ibc/v1/core.GetClientType($COMETBLS_ID)"

probe_qeval_nonempty "GetClientType(statelens_id=$STATELENS_ID)" \
  "gno.land/r/core/ibc/v1/core.GetClientType($STATELENS_ID)"

probe_qeval "GetClientType(9999) miss" \
  "gno.land/r/core/ibc/v1/core.GetClientType(9999)" \
  ""

probe_qeval_nonempty "QueryClientState(cometbls_id=$COMETBLS_ID)" \
  "gno.land/r/core/ibc/v1/core.QueryClientState($COMETBLS_ID)"

probe_qeval "QueryClientState(9999) miss" \
  "gno.land/r/core/ibc/v1/core.QueryClientState(9999)" \
  ""

probe_qeval_nonempty "QueryConsensusState(cometbls_id=$COMETBLS_ID, height=$UPDATE_HEIGHT)" \
  "gno.land/r/core/ibc/v1/core.QueryConsensusState($COMETBLS_ID, $UPDATE_HEIGHT)"

probe_qeval_nonempty "QueryConnection(connection_id=$CONNECTION_ID)" \
  "gno.land/r/core/ibc/v1/core.QueryConnection($CONNECTION_ID)"

probe_qeval "QueryConnection(9999) miss" \
  "gno.land/r/core/ibc/v1/core.QueryConnection(9999)" \
  ""

probe_qeval_nonempty "QueryChannel(mock_source=$MOCK_SOURCE)" \
  "gno.land/r/core/ibc/v1/core.QueryChannel($MOCK_SOURCE)"

probe_qeval "QueryChannel(9999) miss" \
  "gno.land/r/core/ibc/v1/core.QueryChannel(9999)" \
  ""

probe_qeval "QueryBatchPackets(batchHash) baseline" \
  "gno.land/r/core/ibc/v1/core.QueryBatchPackets(${BATCH_HASH_LIT})" \
  "$EXPECTED_HIT"

probe_qeval "QueryCommitmentAtPath(BatchPacketsPath(batchHash)) composed" \
  "gno.land/r/core/ibc/v1/core.QueryCommitmentAtPath(BatchPacketsPath(${BATCH_HASH_LIT}))" \
  "$EXPECTED_HIT"

probe_qeval "QueryCommitmentAtPath(H256{}) miss" \
  'gno.land/r/core/ibc/v1/core.QueryCommitmentAtPath(H256{})' \
  ""

probe_qeval "QueryReceiptAtPath(H256{}) miss" \
  'gno.land/r/core/ibc/v1/core.QueryReceiptAtPath(H256{})' \
  ""

echo "all qeval smoke assertions passed"
