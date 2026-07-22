#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
voyager_dir=${UNION_VOYAGER_DIR:-$(cd "$script_dir/../../../union-voyager" && pwd -P)}
voyager_revision=$(git -C "$voyager_dir" rev-parse HEAD)
[[ $voyager_revision == 9024777562dcaa01613017cd0b958569b85e243e ]]
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/union-channel-e2e-test.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
trap 'echo "fake test failed at line $LINENO" >&2' ERR

fake="$test_dir/voyager"
state="$test_dir/clients.tsv"
connections="$test_dir/connections.tsv"
channels="$test_dir/channels.tsv"
log="$test_dir/calls.log"
env_file="$test_dir/env"
: >"$state"
: >"$connections"
: >"$channels"
: >"$log"

cat >"$fake" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == -c ]]; then
  jq -e --arg evm "$EVM_CHAIN_ID" '
    ([.. | objects | .chain_id? // empty | select(.==$evm)] | length) >= 10
  ' "$2" >/dev/null
  shift 2
fi
printf '%s\n' "$*" >>"$FAKE_DIR/calls.log"
cmd=${1:-}; shift || true
case $cmd in
  start) printf 'start\n' >>"$FAKE_DIR/starts"; trap 'exit 0' TERM INT; while :; do sleep 1; done ;;
  index) ;;
  queue)
    if [[ -s $FAKE_DIR/failed-id ]]; then jq -cn --argjson id "$(cat "$FAKE_DIR/failed-id")" '[{id:$id}]'; else echo '[]'; fi
    ;;
  rpc)
    sub=$1 chain=${2:-} id=${3:-}; row=$(awk -F '\t' -v c="$chain" -v i="$id" '$1==c && $2==i {print; exit}' "$FAKE_DIR/clients.tsv")
    case $sub in
      info) echo '{}' ;;
      client-info)
        [[ ! -e $FAKE_DIR/client-info-error ]] || exit 7
        [[ ! -e $FAKE_DIR/client-info-malformed ]] || { echo '[]'; exit 0; }
        client_count=$(awk 'END {print NR}' "$FAKE_DIR/clients.tsv")
        if [[ -z $row && $chain == 17000 && $id == 1 && $client_count == 3 &&
          -e $FAKE_DIR/race-before-evm-plain ]]; then
          printf '17000\t1\tintruder\tibc-solidity\tdev.ibc\t0\t0\t\tfinalized\n' >>"$FAKE_DIR/clients.tsv"
          row=$(tail -n 1 "$FAKE_DIR/clients.tsv")
        elif [[ -z $row && $chain == 17000 && $id == 2 && $client_count == 5 &&
          -e $FAKE_DIR/race-before-evm-proof ]]; then
          printf '17000\t2\tintruder\tibc-solidity\tdev.ibc\t0\t0\t\tfinalized\n' >>"$FAKE_DIR/clients.tsv"
          row=$(tail -n 1 "$FAKE_DIR/clients.tsv")
        fi
        if [[ -z $row ]]; then
          if [[ $chain == 17000 ]]; then
            echo '{"client_type":"","ibc_interface":"ibc-solidity"}'
          else
            echo null
          fi
          exit 0
        fi
        IFS=$'\t' read -r _ _ type interface _ _ _ _ _ <<<"$row"
        jq -cn --arg t "$type" --arg i "$interface" '{client_type:$t,ibc_interface:$i}'
        ;;
      client-meta)
        [[ -n $row ]] || { echo null; exit 0; }
        IFS=$'\t' read -r _ _ _ _ counterparty _ _ _ _ <<<"$row"
        height=100
        [[ $chain == union-devnet-1 && $counterparty == 17000 ]] && height=11276137
        [[ $chain == union-devnet-1 && $counterparty == dev.ibc ]] && height=300
        jq -cn --arg c "$counterparty" --arg h "$height" '{counterparty_chain_id:$c,counterparty_height:$h}'
        ;;
      client-state)
        [[ -n $row ]] || { echo '{"height":"1","state":null}'; exit 0; }
        IFS=$'\t' read -r _ _ _ _ _ l1 l2 l2chain _ <<<"$row"
        [[ -e $FAKE_DIR/bad-lens ]] && l1=$((l1 + 1))
        jq -cn --argjson l1 "$l1" --argjson l2 "$l2" --arg c "$l2chain" \
          '{height:"1",state:{l1_client_id:$l1,l2_client_id:$l2,l2_chain_id:$c}}'
        ;;
      ibc-state)
        query=$3 kind=$(jq -r 'keys[0]' <<<"$query")
        id=$(jq -r ".${kind}.${kind}_id" <<<"$query")
        file=$FAKE_DIR/${kind}s.tsv
        row=$(awk -F '\t' -v c="$chain" -v i="$id" '$1==c && $2==i {print; exit}' "$file")
        [[ -n $row ]] || { echo '{"state":null}'; exit 0; }
        if [[ $kind == connection ]]; then
          IFS=$'\t' read -r _ _ status client cp_client cp_id <<<"$row"
          [[ ! -e $FAKE_DIR/race-connection || $chain != dev.ibc ]] || client=$((client + 1))
          [[ ! -e $FAKE_DIR/wrong-counterparty-connection || $chain != dev.ibc ]] || cp_id=$((cp_id + 1))
          jq -cn --arg status "$status" --argjson client "$client" --argjson cp_client "$cp_client" --argjson cp_id "$cp_id" \
            '{state:{state:$status,client_id:$client,counterparty_client_id:$cp_client,counterparty_connection_id:$cp_id}}'
        else
          IFS=$'\t' read -r _ _ status connection cp_id cp_port version <<<"$row"
          [[ ! -e $FAKE_DIR/race-channel || $chain != dev.ibc ]] || cp_port=0xdead
          [[ ! -e $FAKE_DIR/wrong-counterparty-channel || $chain != dev.ibc ]] || cp_id=$((cp_id + 1))
          jq -cn --arg status "$status" --argjson connection "$connection" --argjson cp_id "$cp_id" \
            --arg cp_port "$cp_port" --arg version "$version" \
            '{state:{state:$status,connection_id:$connection,counterparty_channel_id:$cp_id,counterparty_port_id:$cp_port,version:$version}}'
        fi
        ;;
    esac
    ;;
  msg)
    [[ ! -e $FAKE_DIR/fail-first-client-create ]] || exit 9
    shift
    chain= counterparty= type= interface= config=null height=finalized
    while (($#)); do
      case $1 in
        --on) chain=$2; shift 2;; --tracking) counterparty=$2; shift 2;;
        --client-type) type=$2; shift 2;; --ibc-interface) interface=$2; shift 2;;
        --config) config=$2; shift 2;; --height) height=$2; shift 2;; *) shift;;
      esac
    done
    id=$(awk -F '\t' -v c="$chain" '$1==c {n++} END {print n+1}' "$FAKE_DIR/clients.tsv")
    l1=0 l2=0 l2chain=
    if [[ $config != null ]]; then
      l1=$(jq -r .l1_client_id <<<"$config") l2=$(jq -r .l2_client_id <<<"$config")
      l2chain=$counterparty
    fi
    if [[ -e $FAKE_DIR/race && $type == cometbls ]]; then type=intruder; rm "$FAKE_DIR/race"; fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$chain" "$id" "$type" "$interface" "$counterparty" "$l1" "$l2" "$l2chain" "$height" >>"$FAKE_DIR/clients.tsv"
    ;;
  q)
    op=${2:?}
    type=$(jq -r '."@value"."@value".datagrams[0].datagram."@type"' <<<"$op")
    value=$(jq -c '."@value"."@value".datagrams[0].datagram."@value"' <<<"$op")
    chain=$(jq -r '."@value"."@value".chain_id' <<<"$op")
    if [[ $type == connection_open_init ]]; then
      [[ $chain == "$EVM_CHAIN_ID" ]]
      local_client=$(jq -r .client_id <<<"$value") cp_client=$(jq -r .counterparty_client_id <<<"$value")
      printf '%s\t1\topen\t%s\t%s\t1\n' "$chain" "$local_client" "$cp_client" >>"$FAKE_DIR/connections.tsv"
      printf 'dev.ibc\t1\topen\t%s\t%s\t1\n' "$cp_client" "$local_client" >>"$FAKE_DIR/connections.tsv"
    else
      connection=$(jq -r .connection_id <<<"$value") port=$(jq -r .port_id <<<"$value")
      cp_port=$(jq -r .counterparty_port_id <<<"$value") version=$(jq -r .version <<<"$value")
      printf 'dev.ibc\t1\topen\t%s\t1\t%s\t%s\n' "$connection" "$cp_port" "$version" >>"$FAKE_DIR/channels.tsv"
      printf '17000\t1\topen\t1\t1\t%s\t%s\n' "$port" "$version" >>"$FAKE_DIR/channels.tsv"
      [[ ! -e $FAKE_DIR/inject-failed ]] || echo 1 >"$FAKE_DIR/failed-id"
    fi
    [[ ! -e $FAKE_DIR/crash-after-$type ]] || exit 99
    ;;
esac
FAKE
chmod 700 "$fake"

key() { printf '0x'; printf '%064d' 0; }
rpc_auth=user:password
cat >"$env_file" <<ENV
UNION_CHAIN_ID=union-devnet-1
EVM_CHAIN_ID=17000
GNO_CHAIN_ID=dev.ibc
UNION_VOYAGER_DIR=$voyager_dir
UNION_VOYAGER_REVISION=$voyager_revision
UNION_IBC_HOST_CONTRACT=union1fake
EVM_IBC_HANDLER=0x1111111111111111111111111111111111111111
EVM_MULTICALL=0x2222222222222222222222222222222222222222
EVM_COMETBLS_CLIENT_IMPL=0x3333333333333333333333333333333333333333
EVM_PROOF_LENS_CLIENT_IMPL=0x4444444444444444444444444444444444444444
GNO_IBC_CORE_REALM=gno.land/r/onbloc/ibc/union/core
GNO_ZKGM_PORT=gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm
EVM_ZKGM_CONTRACT=0x5fbe74a283f7954f10aa04c2edf55578811aeb03
GALOIS_PROVER_ENDPOINT=https://example.invalid
UNION_RPC_URL=http://localhost:1
EVM_RPC_URL=http://$rpc_auth@localhost:2
GNO_RPC_URL=http://$rpc_auth@localhost:3
GNO_TX_INDEXER_RPC_URL=http://$rpc_auth@localhost:4
VOYAGER_DATABASE_URL=postgres://localhost/test
TRUSTED_MPT_PRIVATE_KEY=$(key)
UNION_PRIVATE_KEY=$(key)
EVM_PRIVATE_KEY=$(key)
GNO_PRIVATE_KEY=$(key)
EVM_TEST_ERC20=0x1111111111111111111111111111111111111111
GNO_RECIPIENT=g1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
EVM_TEST_AMOUNT=\${TEST_PACKET_AMOUNT:-1000000000000}
E2E_ARTIFACT_DIR=\${TEST_ARTIFACT_DIR:-$test_dir/artifacts}
E2E_STATE_FILE=\${TEST_ARTIFACT_DIR:-$test_dir/artifacts}/state.json
ENV
chmod 600 "$env_file"

run_runner() {
  local args=(--apply)
  (($# == 0)) || args=("$@")
  ENV_FILE="$env_file" VOYAGER_BIN="$fake" FAKE_DIR="$test_dir" \
    VOYAGER_POLL_SECONDS=0 VOYAGER_TIMEOUT_SECONDS=3 VOYAGER_COMMAND_TIMEOUT_SECONDS=3 \
    VOYAGER_STOP_TIMEOUT_SECONDS=1 "$script_dir/run-channel-e2e.sh" "${args[@]}"
}

output=$(run_runner)
[[ $(grep -c '^index 17000 -e$' "$log") == 1 ]]
[[ $(cut -f3 "$state" | paste -sd, -) == 'cometbls,gno,trusted/evm/mpt,cometbls,state-lens/ics23/mpt,proof-lens' ]]
[[ $(wc -l <"$state" | tr -d ' ') == 6 && $(wc -l <"$test_dir/starts" | tr -d ' ') == 3 ]]
[[ $(awk -F '\t' '$3=="state-lens/ics23/mpt" {print $9}' "$state") == 11276137 ]]
[[ $(awk -F '\t' '$3=="proof-lens" {print $9}' "$state") == 300 ]]
[[ $output == *'EVM plain IDs=1 Proof Lens IDs=2'* ]]
[[ $(wc -l <"$connections" | tr -d ' ') == 2 && $(wc -l <"$channels" | tr -d ' ') == 2 ]]
[[ $(stat -f '%Lp' "$test_dir/artifacts/state.json" 2>/dev/null || stat -c '%a' "$test_dir/artifacts/state.json") == 600 ]]
jq -e '.phase=="complete" and .connections=={"gno":1,"evm":1} and .channels=={"gno":1,"evm":1}' \
  "$test_dir/artifacts/state.json" >/dev/null
jq -e '.chains.evm=="17000" and .evm_topology.chain_id=="17000" and
  (.evm_topology.address_fingerprint | test("^[0-9a-f]{40}$"))' \
  "$test_dir/artifacts/state.json" >/dev/null
cp "$connections" "$test_dir/connections.complete"
cp "$channels" "$test_dir/channels.complete"
cp "$state" "$test_dir/clients.complete"
cp "$test_dir/artifacts/state.json" "$test_dir/state.complete"

q_count=$(grep -c '^q e ' "$log")
output=$(run_runner --resume 2>&1)
[[ $(wc -l <"$state" | tr -d ' ') == 6 && $(grep -c '^q e ' "$log") == "$q_count" ]]

jq '.evm_topology.address_fingerprint="wrong"' "$test_dir/state.complete" >"$test_dir/artifacts/state.json"
chmod 600 "$test_dir/artifacts/state.json"
if run_runner --resume >"$test_dir/topology-mismatch.out" 2>&1; then
  echo 'mismatched EVM topology unexpectedly resumed' >&2
  exit 1
fi
grep -q 'resume state does not match this topology' "$test_dir/topology-mismatch.out"

for implementation in EVM_COMETBLS_CLIENT_IMPL EVM_PROOF_LENS_CLIENT_IMPL; do
  cp "$env_file" "$test_dir/env.original"
  sed "s/^${implementation}=.*/${implementation}=0x5555555555555555555555555555555555555555/" \
    "$env_file" >"$test_dir/env.changed"
  mv "$test_dir/env.changed" "$env_file"
  chmod 600 "$env_file"
  cp "$test_dir/state.complete" "$test_dir/artifacts/state.json"
  chmod 600 "$test_dir/artifacts/state.json"
  if run_runner --resume >"$test_dir/${implementation}.out" 2>&1; then
    echo "changed $implementation unexpectedly resumed" >&2
    exit 1
  fi
  grep -q 'resume state does not match this topology' "$test_dir/${implementation}.out"
  mv "$test_dir/env.original" "$env_file"
done

jq '.chains.sepolia=.chains.evm | del(.chains.evm,.evm_topology)' \
  "$test_dir/state.complete" >"$test_dir/artifacts/state.json"
chmod 600 "$test_dir/artifacts/state.json"
if run_runner --resume >"$test_dir/legacy-sepolia-state.out" 2>&1; then
  echo 'legacy Sepolia state unexpectedly resumed' >&2
  exit 1
fi
grep -q 'resume state does not match this topology' "$test_dir/legacy-sepolia-state.out"
cp "$test_dir/state.complete" "$test_dir/artifacts/state.json"
chmod 600 "$test_dir/artifacts/state.json"

for failure in connection channel; do
  touch "$test_dir/race-$failure"
  if run_runner --resume >"$test_dir/race-$failure.out" 2>&1; then echo "$failure race unexpectedly passed" >&2; exit 1; fi
  grep -q "$failure allocation race:" "$test_dir/race-$failure.out"
  rm "$test_dir/race-$failure"
done

for failure in connection channel; do
  touch "$test_dir/wrong-counterparty-$failure"
  if run_runner --resume >"$test_dir/wrong-$failure.out" 2>&1; then echo "$failure wrong counterparty unexpectedly passed" >&2; exit 1; fi
  grep -q "$failure allocation race: wrong counterparty" "$test_dir/wrong-$failure.out"
  rm "$test_dir/wrong-counterparty-$failure"
done

cp "$test_dir/artifacts/state.json" "$test_dir/checkpoint.json"
chmod 500 "$test_dir/artifacts"
if run_runner --resume >"$test_dir/atomic.out" 2>&1; then echo 'unwritable checkpoint unexpectedly passed' >&2; exit 1; fi
chmod 700 "$test_dir/artifacts"
cmp "$test_dir/checkpoint.json" "$test_dir/artifacts/state.json"
rm "$test_dir/checkpoint.json"

echo 1 >"$test_dir/failed-id"
if run_runner --resume >"$test_dir/failed.out" 2>&1; then echo 'new failed work unexpectedly passed' >&2; exit 1; fi
grep -q 'recorded new failed work' "$test_dir/failed.out"
jq -e '.phase=="failed-work" and .failed_work=={"baseline":0,"final":1}' "$test_dir/artifacts/state.json" >/dev/null
jq -e '.phase=="failed-work" and .failed_work.final==1' "$test_dir/artifacts/summary.json" >/dev/null
rm "$test_dir/failed-id"

q_before=$(grep -c '^q e ' "$log")
: >"$connections"
: >"$channels"
jq '.phase="connection-prepared" | del(.channels)' "$test_dir/artifacts/state.json" >"$test_dir/state.tmp"
chmod 600 "$test_dir/state.tmp" && mv "$test_dir/state.tmp" "$test_dir/artifacts/state.json"
if run_runner --resume --apply >"$test_dir/ambiguous.out" 2>&1; then echo 'ambiguous connection unexpectedly retried' >&2; exit 1; fi
grep -q 'connection submission is ambiguous' "$test_dir/ambiguous.out"
[[ $(grep -c '^q e ' "$log") == "$q_before" ]]

cp "$test_dir/connections.complete" "$connections"
cp "$test_dir/channels.complete" "$channels"
jq '.phase="connection-prepared"' "$test_dir/state.complete" >"$test_dir/state.tmp"
chmod 600 "$test_dir/state.tmp" && mv "$test_dir/state.tmp" "$test_dir/artifacts/state.json"
run_runner --resume --apply >/dev/null
[[ $(grep -c '^q e ' "$log") == "$q_before" ]]

: >"$channels"
jq '.phase="channel-prepared"' "$test_dir/state.complete" >"$test_dir/state.tmp"
chmod 600 "$test_dir/state.tmp" && mv "$test_dir/state.tmp" "$test_dir/artifacts/state.json"
if run_runner --resume --apply >"$test_dir/ambiguous-channel.out" 2>&1; then echo 'ambiguous channel unexpectedly retried' >&2; exit 1; fi
grep -q 'channel submission is ambiguous' "$test_dir/ambiguous-channel.out"
[[ $(grep -c '^q e ' "$log") == "$q_before" ]]

cp "$test_dir/channels.complete" "$channels"
jq '.phase="channel-prepared"' "$test_dir/state.complete" >"$test_dir/state.tmp"
chmod 600 "$test_dir/state.tmp" && mv "$test_dir/state.tmp" "$test_dir/artifacts/state.json"
run_runner --resume --apply >/dev/null
[[ $(grep -c '^q e ' "$log") == "$q_before" ]]

for failure in client-info-error client-info-malformed; do
  touch "$test_dir/$failure"
  if run_runner --resume >"$test_dir/$failure.out" 2>&1; then echo "$failure unexpectedly passed" >&2; exit 1; fi
  [[ $(wc -l <"$state" | tr -d ' ') == 6 ]]
  rm "$test_dir/$failure"
done

touch "$test_dir/bad-lens"
if run_runner --resume >"$test_dir/bad.out" 2>&1; then echo 'bad Lens relation unexpectedly passed' >&2; exit 1; fi
grep -q 'Lens relation mismatch' "$test_dir/bad.out"
rm "$test_dir/bad-lens"

export TEST_ARTIFACT_DIR="$test_dir/crash-artifacts"
: >"$connections"
: >"$channels"
q_before=$(grep -c '^q e ' "$log")
touch "$test_dir/crash-after-connection_open_init"
if run_runner >"$test_dir/crash-connection.out" 2>&1; then echo 'post-enqueue connection crash unexpectedly passed' >&2; exit 1; fi
rm "$test_dir/crash-after-connection_open_init"
[[ $(grep -c '^q e ' "$log") == $((q_before + 1)) ]]
[[ $(wc -l <"$state" | tr -d ' ') == 12 ]]
jq -e '.phase=="connection-submitting"' "$TEST_ARTIFACT_DIR/state.json" >/dev/null
run_runner --resume --apply >/dev/null
[[ $(grep -c '^q e ' "$log") == $((q_before + 1)) ]]

: >"$channels"
jq '.phase="connection-submitted" | del(.channels)' "$TEST_ARTIFACT_DIR/state.json" >"$test_dir/state.tmp"
chmod 600 "$test_dir/state.tmp" && mv "$test_dir/state.tmp" "$TEST_ARTIFACT_DIR/state.json"
q_before=$(grep -c '^q e ' "$log")
touch "$test_dir/crash-after-channel_open_init"
if run_runner --resume --apply >"$test_dir/crash-channel.out" 2>&1; then echo 'post-enqueue channel crash unexpectedly passed' >&2; exit 1; fi
rm "$test_dir/crash-after-channel_open_init"
[[ $(grep -c '^q e ' "$log") == $((q_before + 1)) ]]
jq -e '.phase=="channel-submitting"' "$TEST_ARTIFACT_DIR/state.json" >/dev/null
run_runner --resume --apply >/dev/null
[[ $(grep -c '^q e ' "$log") == $((q_before + 1)) ]]
unset TEST_ARTIFACT_DIR

: >"$state"
: >"$connections"
: >"$channels"
rm -rf "$test_dir/artifacts"
client_msgs=$(grep -c '^msg create-client ' "$log")
touch "$test_dir/fail-first-client-create"
if run_runner >"$test_dir/bootstrap-failure.out" 2>&1; then echo 'first client failure unexpectedly passed' >&2; exit 1; fi
rm "$test_dir/fail-first-client-create"
[[ $(grep -c '^msg create-client ' "$log") == $((client_msgs + 1)) ]]
[[ ! -e $test_dir/artifacts/state.json ]]
[[ $(stat -f '%Lp' "$test_dir/artifacts/bootstrap-in-progress.json" 2>/dev/null || \
  stat -c '%a' "$test_dir/artifacts/bootstrap-in-progress.json") == 600 ]]
client_msgs=$(grep -c '^msg create-client ' "$log")
if run_runner >"$test_dir/bootstrap-retry.out" 2>&1; then echo 'unsafe bootstrap retry unexpectedly passed' >&2; exit 1; fi
grep -q 'bootstrap checkpoint already exists' "$test_dir/bootstrap-retry.out"
[[ $(grep -c '^msg create-client ' "$log") == "$client_msgs" ]]

: >"$state"
: >"$connections"
: >"$channels"
rm -rf "$test_dir/artifacts"
evm_msgs=$(grep -c '^msg create-client --on 17000 ' "$log")
touch "$test_dir/race-before-evm-plain"
if run_runner >"$test_dir/evm-plain-race.out" 2>&1; then echo 'EVM plain pre-create race unexpectedly passed' >&2; exit 1; fi
grep -q 'client allocation changed: expected 17000 client ID 1' "$test_dir/evm-plain-race.out"
[[ $(grep -c '^msg create-client --on 17000 ' "$log") == "$evm_msgs" ]]
[[ $(awk -F '\t' '$1=="17000" && $3!="intruder" {n++} END {print n+0}' "$state") == 0 ]]
rm "$test_dir/race-before-evm-plain"

: >"$state"
: >"$connections"
: >"$channels"
rm -rf "$test_dir/artifacts"
evm_msgs=$(grep -c '^msg create-client --on 17000 ' "$log")
touch "$test_dir/race-before-evm-proof"
if run_runner >"$test_dir/evm-proof-race.out" 2>&1; then echo 'EVM Proof Lens pre-create race unexpectedly passed' >&2; exit 1; fi
grep -q 'client allocation changed: expected 17000 client ID 2' "$test_dir/evm-proof-race.out"
[[ $(grep -c '^msg create-client --on 17000 ' "$log") == $((evm_msgs + 1)) ]]
[[ $(awk -F '\t' '$1=="17000" && $3=="proof-lens" {n++} END {print n+0}' "$state") == 0 ]]
rm "$test_dir/race-before-evm-proof"

: >"$state"
: >"$connections"
: >"$channels"
rm -rf "$test_dir/artifacts"
touch "$test_dir/race"
if run_runner >"$test_dir/race.out" 2>&1; then echo 'allocation race unexpectedly passed' >&2; exit 1; fi
grep -q 'client allocation race:' "$test_dir/race.out"

fake_bin="$test_dir/fake-bin"
mkdir "$fake_bin"
cat >"$fake_bin/cast" <<'FAKE_CAST'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$FAKE_DIR/packet-calls.log"
[[ ${ETH_RPC_URL:-} == "$EVM_RPC_URL" ]] || { echo 'missing ETH_RPC_URL' >&2; exit 9; }
if [[ ${FAKE_PACKET_TOOL_ERROR:-} == cast ]]; then echo "cast failed at $EVM_RPC_URL" >&2; exit 9; fi
word() { printf '0x%064x\n' "$1"; }
ack_word() { printf '0x%062d01\n' 0; }
cmd=$1
shift
case $cmd in
  wallet) echo 0x2222222222222222222222222222222222222222 ;;
  code) echo 0x6000 ;;
  call)
    signature=$2
    case $signature in
      'decimals()(uint8)') echo 18 ;;
      'balanceOf(address)(uint256)')
        owner=$3
        owner=$(tr '[:upper:]' '[:lower:]' <<<"$owner")
        if [[ -e $FAKE_DIR/packet-sent ]]; then
          if [[ ${FAKE_BAD_DELTAS:-0} == 1 ]]; then echo "$EVM_TEST_AMOUNT"
          elif [[ $owner == 0x2222222222222222222222222222222222222222 ]]; then echo 0
          else echo "$EVM_TEST_AMOUNT"
          fi
        elif [[ $owner == 0x2222222222222222222222222222222222222222 ]]; then echo "$EVM_TEST_AMOUNT"
        else echo 0
        fi
        ;;
      'commitments(bytes32)(bytes32)') printf '0x02%062d\n' 0 ;;
      *) exit 2 ;;
    esac
    ;;
  abi-encode) echo 0x1234 ;;
  keccak) word 9 ;;
  block-number) echo 100 ;;
  send)
    signature=$2
    case $signature in
      'mint(address,uint256)') stage=mint; tx=1 ;;
      'approve(address,uint256)') stage=approve; tx=2 ;;
      'send(uint32,uint64,uint64,bytes32,(uint8,uint8,bytes))') stage=send; tx=3 ;;
      *) exit 2 ;;
    esac
    touch "$FAKE_DIR/packet-$stage"
    [[ $stage != send ]] || touch "$FAKE_DIR/packet-sent"
    if [[ ${FAKE_PACKET_FAIL_AFTER:-} == "$stage" ]]; then exit 99; fi
    tx_hash=$(word "$tx")
    if [[ $stage == send ]]; then
      packet_hash=$(word 9)
      topic=0x635b5d234fe7abddfb29b6c8498780a31
      topic+=75c9002c537f20a3d1bf9d0e625b5fe
      jq -cn --arg tx "$tx_hash" --arg handler "$EVM_IBC_HANDLER" --arg topic "$topic" --arg hash "$packet_hash" \
        '{status:"0x1",transactionHash:$tx,logs:[{address:$handler,topics:[$topic,"0x0",$hash],data:"0x"}]}'
      [[ ${FAKE_PACKET_INJECT_FAILED:-0} != 1 ]] || echo 1 >"$FAKE_DIR/failed-id"
    else
      jq -cn --arg tx "$tx_hash" '{status:"0x1",transactionHash:$tx,logs:[]}'
    fi
    ;;
  rpc)
    if [[ ! -e $FAKE_DIR/packet-ack-polled ]]; then
      touch "$FAKE_DIR/packet-ack-polled"
      echo '[]'
    else
      tx_hash=$(word 4)
      jq -cn --arg tx "$tx_hash" '[{transactionHash:$tx,data:"0x1234"}]'
    fi
    ;;
  decode-abi) ack=$(ack_word); jq -cn --arg ack "$ack" '[$ack]' ;;
  *) exit 2 ;;
esac
FAKE_CAST
cat >"$fake_bin/gnokey" <<'FAKE_GNOKEY'
#!/usr/bin/env bash
set -euo pipefail
printf 'gnokey %s\n' "$*" >>"$FAKE_DIR/packet-calls.log"
if [[ ${FAKE_PACKET_TOOL_ERROR:-} == gnokey ]]; then echo "gnokey failed at $GNO_RPC_URL" >&2; exit 9; fi
if [[ -e $FAKE_DIR/packet-sent ]]; then echo "(${EVM_TEST_AMOUNT%000000000000} int64)"; else echo '(0 int64)'; fi
FAKE_GNOKEY
cat >"$fake_bin/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
set -euo pipefail
printf 'curl %s\n' "$*" >>"$FAKE_DIR/packet-calls.log"
if [[ ${FAKE_PACKET_TOOL_ERROR:-} == curl ]]; then echo "curl failed at $GNO_TX_INDEXER_RPC_URL" >&2; exit 9; fi
body=$(cat)
args="$* $body"
if [[ $args == *PacketRecv* ]]; then event=PacketRecv; tx=5; ack=
else event=WriteAck; tx=5; ack=1
fi
packet_hash=$(printf '0x%064x' 9)
tx_hash=$(printf '0x%064x' "$tx")
attrs=$(jq -cn --arg hash "$packet_hash" '[{key:"packet_hash",value:$hash}]')
if [[ -n $ack ]]; then
  ack_value=$(printf '0x%062d01' 0)
  attrs=$(jq -cn --arg hash "$packet_hash" --arg ack "$ack_value" \
    '[{key:"packet_hash",value:$hash},{key:"acknowledgement",value:$ack}]')
fi
event_json=$(jq -cn --arg event "$event" --argjson attrs "$attrs" '{type:$event,pkg_path:"gno.land/r/onbloc/ibc/union/core",attrs:$attrs}')
row=$(jq -cn --arg tx "$tx_hash" --argjson event "$event_json" '{hash:$tx,block_height:101,response:{events:[$event]}}')
if [[ ${FAKE_DUPLICATE_GNO_EVENT:-0} == 1 ]]; then rows=$(jq -cn --argjson row "$row" '[$row,$row]')
else rows=$(jq -cn --argjson row "$row" '[$row]')
fi
jq -cn --argjson rows "$rows" '{data:{getTransactions:$rows},errors:null}'
FAKE_CURL
chmod 700 "$fake_bin/cast" "$fake_bin/gnokey" "$fake_bin/curl"

run_packet_runner() {
  PATH="$fake_bin:$PATH" run_runner "$@"
}

restore_packet_base() {
  export TEST_ARTIFACT_DIR=$1
  rm -rf "$TEST_ARTIFACT_DIR"
  mkdir -p "$TEST_ARTIFACT_DIR"
  printf '%s\n' union-channel-e2e-artifacts >"$TEST_ARTIFACT_DIR/.union-channel-e2e-artifacts"
  cp "$test_dir/state.complete" "$TEST_ARTIFACT_DIR/state.json"
  chmod 600 "$TEST_ARTIFACT_DIR/.union-channel-e2e-artifacts" "$TEST_ARTIFACT_DIR/state.json"
  cp "$test_dir/clients.complete" "$state"
  cp "$test_dir/connections.complete" "$connections"
  cp "$test_dir/channels.complete" "$channels"
  rm -f "$test_dir"/packet-{mint,approve,send,sent,ack-polled} "$test_dir/failed-id"
  : >"$test_dir/packet-calls.log"
}

if ENV_FILE="$env_file" "$script_dir/run-channel-e2e.sh" --erc20-to-gno >"$test_dir/packet-gate.out" 2>&1; then
  echo 'packet flag without apply unexpectedly passed' >&2
  exit 1
fi
grep -q -- '--erc20-to-gno requires --apply' "$test_dir/packet-gate.out"

restore_packet_base "$test_dir/packet-artifacts"
if TEST_PACKET_AMOUNT=1 run_packet_runner --resume --apply --erc20-to-gno >"$test_dir/packet-amount.out" 2>&1; then
  echo 'indivisible packet amount unexpectedly passed' >&2
  exit 1
fi
grep -q 'divisible by 10\^12' "$test_dir/packet-amount.out"

restore_packet_base "$test_dir/packet-overflow-artifacts"
if TEST_PACKET_AMOUNT=9223372036854775808000000000000 \
  run_packet_runner --resume --apply --erc20-to-gno >"$test_dir/packet-overflow.out" 2>&1; then
  echo 'overflowing packet amount unexpectedly passed' >&2
  exit 1
fi
grep -q 'must fit Gno int64' "$test_dir/packet-overflow.out"
[[ ! -s $test_dir/packet-calls.log ]]

restore_packet_base "$test_dir/packet-max-artifacts"
TEST_PACKET_AMOUNT=9223372036854775807000000000000 \
  run_packet_runner --resume --apply --erc20-to-gno >/dev/null
jq -e '.phase=="packet-complete" and .packet.balance_deltas.recipient=="9223372036854775807"' \
  "$TEST_ARTIFACT_DIR/state.json" >/dev/null

restore_packet_base "$test_dir/packet-artifacts"
run_packet_runner --resume --apply --erc20-to-gno >/dev/null
jq -e '.phase=="packet-complete" and .packet.phase=="packet-complete" and
  .packet.balance_deltas=={"sender":"1000000000000","escrow":"1000000000000","recipient":"1"}' \
  "$TEST_ARTIFACT_DIR/state.json" >/dev/null
jq -e '.phase=="packet-complete" and .channels=={"evm":1,"gno":1} and
  .amounts.sent_18_decimals=="1000000000000"' "$TEST_ARTIFACT_DIR/packet-summary.json" >/dev/null
grep -q 'abi-encode f(bytes,bytes,bytes,uint256,bytes,uint256,uint8,bytes)' "$test_dir/packet-calls.log"
grep -q 'send(uint32,uint64,uint64,bytes32,(uint8,uint8,bytes)) 1 0 ' "$test_dir/packet-calls.log"
[[ $(grep -c '^rpc eth_getLogs ' "$test_dir/packet-calls.log") -ge 2 ]]
if grep -q "$rpc_auth" "$test_dir/packet-calls.log"; then echo 'credential leaked to packet argv log' >&2; exit 1; fi
packet_writes=$(grep -Ec '^send .* (mint|approve|send)\(' "$test_dir/packet-calls.log")
run_packet_runner --resume --apply --erc20-to-gno >/dev/null
[[ $(grep -Ec '^send .* (mint|approve|send)\(' "$test_dir/packet-calls.log") == "$packet_writes" ]]

for tool in cast gnokey curl; do
  restore_packet_base "$test_dir/packet-$tool-error-artifacts"
  if FAKE_PACKET_TOOL_ERROR=$tool run_packet_runner --resume --apply --erc20-to-gno \
    >"$test_dir/packet-$tool-error.out" 2>&1; then
    echo "$tool credential error unexpectedly passed" >&2
    exit 1
  fi
  if grep -q "$rpc_auth" "$test_dir/packet-$tool-error.out"; then echo "$tool error leaked credentials" >&2; exit 1; fi
done

for stage in mint approve send; do
  restore_packet_base "$test_dir/packet-$stage-artifacts"
  if FAKE_PACKET_FAIL_AFTER=$stage run_packet_runner --resume --apply --erc20-to-gno >"$test_dir/packet-$stage-crash.out" 2>&1; then
    echo "packet $stage crash unexpectedly passed" >&2
    exit 1
  fi
  writes_before=$(grep -c "^send .* $stage(" "$test_dir/packet-calls.log")
  if run_packet_runner --resume --apply --erc20-to-gno >"$test_dir/packet-$stage-retry.out" 2>&1; then
    echo "ambiguous packet $stage retry unexpectedly passed" >&2
    exit 1
  fi
  grep -q 'submission is ambiguous' "$test_dir/packet-$stage-retry.out"
  [[ $(grep -c "^send .* $stage(" "$test_dir/packet-calls.log") == "$writes_before" ]]
done

restore_packet_base "$test_dir/packet-failed-artifacts"
if FAKE_PACKET_INJECT_FAILED=1 run_packet_runner --resume --apply --erc20-to-gno >"$test_dir/packet-failed.out" 2>&1; then
  echo 'packet failed-work injection unexpectedly passed' >&2
  exit 1
fi
grep -q 'new failed work' "$test_dir/packet-failed.out"

restore_packet_base "$test_dir/packet-duplicate-artifacts"
if FAKE_DUPLICATE_GNO_EVENT=1 run_packet_runner --resume --apply --erc20-to-gno >"$test_dir/packet-duplicate.out" 2>&1; then
  echo 'duplicate Gno packet event unexpectedly passed' >&2
  exit 1
fi
grep -q 'count=2, want exactly one' "$test_dir/packet-duplicate.out"

restore_packet_base "$test_dir/packet-delta-artifacts"
if FAKE_BAD_DELTAS=1 run_packet_runner --resume --apply --erc20-to-gno >"$test_dir/packet-delta.out" 2>&1; then
  echo 'bad packet balance delta unexpectedly passed' >&2
  exit 1
fi
grep -q 'balance deltas do not match' "$test_dir/packet-delta.out"
unset TEST_ARTIFACT_DIR

echo 'run-channel-e2e fake tests passed'
