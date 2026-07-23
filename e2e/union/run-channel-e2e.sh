#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
template="$script_dir/config.jsonc.template"
env_file=${ENV_FILE:-"$script_dir/.env"}
apply=0
resume=0
erc20_to_gno=0
voyager_bin=${VOYAGER_BIN:-}

usage() { echo "usage: $0 [--resume] [--apply] [--erc20-to-gno]" >&2; }

for arg in "$@"; do
  case $arg in
    --apply) apply=1 ;;
    --resume) resume=1 ;;
    --erc20-to-gno) erc20_to_gno=1 ;;
    *) usage; exit 2 ;;
  esac
done
(( $# <= 3 )) || { usage; exit 2; }
((!erc20_to_gno || apply)) || { echo "--erc20-to-gno requires --apply" >&2; exit 2; }

for command in git jq mktemp stat; do
  command -v "$command" >/dev/null || { echo "missing required command: $command" >&2; exit 2; }
done
[[ -r $env_file ]] || { echo "missing environment file: $env_file" >&2; exit 2; }
env_mode=$(stat -f '%Lp' "$env_file" 2>/dev/null || stat -c '%a' "$env_file" 2>/dev/null) || {
  echo "cannot inspect environment file permissions" >&2
  exit 2
}
if [[ ! $env_mode =~ ^[0-7]{3,4}$ ]] || ! (((8#$env_mode & 077) == 0)); then
  echo "environment file must not be accessible by group or other users" >&2
  exit 2
fi
set -a
# shellcheck disable=SC1090
source "$env_file"
set +a

required=(
  UNION_CHAIN_ID EVM_CHAIN_ID GNO_CHAIN_ID UNION_VOYAGER_DIR
  UNION_VOYAGER_REVISION
  UNION_IBC_HOST_CONTRACT EVM_IBC_HANDLER
  EVM_MULTICALL EVM_COMETBLS_CLIENT_IMPL EVM_PROOF_LENS_CLIENT_IMPL
  GNO_IBC_CORE_REALM GNO_ZKGM_PORT
  EVM_ZKGM_CONTRACT GALOIS_PROVER_ENDPOINT
  UNION_RPC_URL EVM_RPC_URL GNO_RPC_URL GNO_TX_INDEXER_RPC_URL
  VOYAGER_DATABASE_URL TRUSTED_MPT_PRIVATE_KEY UNION_PRIVATE_KEY
  EVM_PRIVATE_KEY GNO_PRIVATE_KEY
)
for name in "${required[@]}"; do
  [[ -n ${!name:-} ]] || { echo "missing required environment variable: $name" >&2; exit 2; }
done
if ((erc20_to_gno)); then
  EVM_PACKET_RPC_URL=${EVM_PACKET_RPC_URL:-$EVM_RPC_URL}
  GNO_PACKET_RPC_URL=${GNO_PACKET_RPC_URL:-$GNO_RPC_URL}
  GNO_PACKET_INDEXER_RPC_URL=${GNO_PACKET_INDEXER_RPC_URL:-$GNO_TX_INDEXER_RPC_URL}
  for name in EVM_TEST_ERC20 GNO_RECIPIENT EVM_TEST_AMOUNT; do
    [[ -n ${!name:-} ]] || { echo "missing required environment variable: $name" >&2; exit 2; }
  done
  [[ $EVM_TEST_ERC20 =~ ^0x[0-9a-fA-F]{40}$ ]] || {
    echo "EVM_TEST_ERC20 must be a 20-byte hex address" >&2
    exit 2
  }
  [[ $GNO_RECIPIENT =~ ^g1[0-9a-z]{38}$ ]] || {
    echo "GNO_RECIPIENT must be a Gno bech32 address" >&2
    exit 2
  }
  [[ $EVM_TEST_AMOUNT =~ ^[1-9][0-9]*000000000000$ ]] || {
    echo "EVM_TEST_AMOUNT must be positive and divisible by 10^12" >&2
    exit 2
  }
  packet_ledger_amount=${EVM_TEST_AMOUNT%000000000000}
  # shellcheck disable=SC2071 # Equal-length decimal strings are compared lexically.
  if ((${#packet_ledger_amount} > 19)) ||
    { ((${#packet_ledger_amount} == 19)) && [[ $packet_ledger_amount > 9223372036854775807 ]]; }; then
    echo "EVM_TEST_AMOUNT after 10^12 scaling must fit Gno int64" >&2
    exit 2
  fi
  for name in EVM_PACKET_RPC_URL GNO_PACKET_RPC_URL GNO_PACKET_INDEXER_RPC_URL; do
    case ${!name} in
      *$'\n'*|*'"'*|*\\*)
        echo "$name contains a character unsupported by the private runtime config" >&2
        exit 2
        ;;
    esac
  done
fi
[[ $GNO_ZKGM_PORT =~ ^gno\.land/r/[A-Za-z0-9_./-]+$ ]] || {
  echo "GNO_ZKGM_PORT must be a gno.land/r/... realm path" >&2
  exit 2
}
for name in EVM_IBC_HANDLER EVM_MULTICALL EVM_ZKGM_CONTRACT \
  EVM_COMETBLS_CLIENT_IMPL EVM_PROOF_LENS_CLIENT_IMPL; do
  [[ ${!name} =~ ^0x[0-9a-fA-F]{40}$ ]] || {
    echo "$name must be a 20-byte hex address" >&2
    exit 2
  }
done
[[ $EVM_CHAIN_ID =~ ^[1-9][0-9]*$ ]] || {
  echo "EVM_CHAIN_ID must be a positive decimal integer" >&2
  exit 2
}
[[ $UNION_CHAIN_ID == union-devnet-1 && $GNO_CHAIN_ID == dev.ibc ]] || {
  echo "UNION_CHAIN_ID and GNO_CHAIN_ID must be union-devnet-1 and dev.ibc" >&2
  exit 2
}
[[ $UNION_VOYAGER_REVISION =~ ^[0-9a-f]{40}$ ]] || {
  echo "UNION_VOYAGER_REVISION must be a lowercase 40-character commit SHA" >&2
  exit 2
}
voyager_revision=$(git -C "$UNION_VOYAGER_DIR" rev-parse HEAD 2>/dev/null) || {
  echo "UNION_VOYAGER_DIR is not a readable git checkout" >&2
  exit 2
}
[[ $voyager_revision == "$UNION_VOYAGER_REVISION" ]] || {
  echo "union-voyager checkout does not match UNION_VOYAGER_REVISION" >&2
  exit 2
}
[[ -z $(git -C "$UNION_VOYAGER_DIR" status --porcelain) ]] || {
  echo "union-voyager checkout must be clean" >&2
  exit 2
}
for name in TRUSTED_MPT_PRIVATE_KEY UNION_PRIVATE_KEY EVM_PRIVATE_KEY GNO_PRIVATE_KEY; do
  [[ ${!name} =~ ^0x[0-9a-fA-F]{64}$ ]] || {
    echo "$name must be a 0x-prefixed 32-byte private key" >&2
    exit 2
  }
done

evm_ibc_handler_lc=$(tr '[:upper:]' '[:lower:]' <<<"$EVM_IBC_HANDLER")
evm_multicall_lc=$(tr '[:upper:]' '[:lower:]' <<<"$EVM_MULTICALL")
evm_zkgm_lc=$(tr '[:upper:]' '[:lower:]' <<<"$EVM_ZKGM_CONTRACT")
evm_cometbls_impl_lc=$(tr '[:upper:]' '[:lower:]' <<<"$EVM_COMETBLS_CLIENT_IMPL")
evm_proof_lens_impl_lc=$(tr '[:upper:]' '[:lower:]' <<<"$EVM_PROOF_LENS_CLIENT_IMPL")
evm_address_fingerprint=$(printf '%s\0%s\0%s\0%s\0%s\0' \
  "$evm_ibc_handler_lc" "$evm_multicall_lc" "$evm_zkgm_lc" \
  "$evm_cometbls_impl_lc" "$evm_proof_lens_impl_lc" |
  git hash-object --stdin)

client_configs() {
  jq -cn --arg ids "$1" '$ids | if . == "" then [] else split(",") | map(tonumber | {
    client_id: ., min_batch_size: 1, max_batch_size: 5,
    max_wait_time: {nanos: 0, secs: 10}
  }) end'
}

runtime_dir=$(mktemp -d "${TMPDIR:-/tmp}/union-channel-e2e.XXXXXX")
rendered_config="$runtime_dir/config.jsonc"
voyager_log="$runtime_dir/voyager.log"
repaired_failed_file="$runtime_dir/repaired-failed-ids"
packet_cast_error="$runtime_dir/cast.stderr"
packet_gnokey_error="$runtime_dir/gnokey.stderr"
packet_curl_error="$runtime_dir/curl.stderr"
packet_gnokey_config="$runtime_dir/gnokey.toml"
packet_curl_config="$runtime_dir/curl.conf"
artifact_dir=${E2E_ARTIFACT_DIR:-"$script_dir/channel-e2e-artifacts"}
state_file=${E2E_STATE_FILE:-"$artifact_dir/state.json"}
bootstrap_file="$artifact_dir/bootstrap-in-progress.json"
artifact_marker="$artifact_dir/.union-channel-e2e-artifacts"
voyager_pid=
voyager_container=
voyager_container_bin=
voyager_image=${VOYAGER_IMAGE:-"union-voyager-e2e:${UNION_VOYAGER_REVISION:0:12}"}
voyager_image_ready=0
voyager_config_path=/run/voyager/config.jsonc
VOYAGER_BIN_DIR=/output/release
export VOYAGER_BIN_DIR
cleanup() {
  status=$?
  trap - EXIT INT TERM
  stop_voyager 2>/dev/null || true
  rm -f "$rendered_config" "$voyager_log" "$packet_cast_error" "$packet_gnokey_error" \
    "$packet_curl_error" "$packet_gnokey_config" "$packet_curl_config" "$repaired_failed_file"
  rmdir "$runtime_dir" 2>/dev/null || true
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
umask 077
: >"$repaired_failed_file"

if ((erc20_to_gno)); then
  printf 'remote = "%s"\n' "$GNO_PACKET_RPC_URL" >"$packet_gnokey_config"
  printf 'silent\nshow-error\nfail\nheader = "content-type: application/json"\nurl = "%s"\n' \
    "$GNO_PACKET_INDEXER_RPC_URL" >"$packet_curl_config"
  chmod 600 "$packet_gnokey_config" "$packet_curl_config"
fi

render_config() {
  local plain_configs proof_configs
  plain_configs=$(client_configs "$1")
  proof_configs=$(client_configs "$2")
  jq \
    --argjson plain "$plain_configs" \
    --argjson proof "$proof_configs" '
    walk(if type == "string" then
      gsub("^__VOYAGER_BIN_DIR__"; $ENV.VOYAGER_BIN_DIR)
      | if . == "__EVM_CHAIN_ID__" then $ENV.EVM_CHAIN_ID
        elif . == "__UNION_IBC_HOST_CONTRACT__" then $ENV.UNION_IBC_HOST_CONTRACT
        elif . == "__EVM_IBC_HANDLER__" then $ENV.EVM_IBC_HANDLER
        elif . == "__EVM_MULTICALL__" then $ENV.EVM_MULTICALL
        elif . == "__GNO_IBC_CORE_REALM__" then $ENV.GNO_IBC_CORE_REALM
        elif . == "__GALOIS_PROVER_ENDPOINT__" then $ENV.GALOIS_PROVER_ENDPOINT
        elif . == "__UNION_RPC_URL__" then $ENV.UNION_RPC_URL
        elif . == "__EVM_RPC_URL__" then $ENV.EVM_RPC_URL
        elif . == "__GNO_RPC_URL__" then $ENV.GNO_RPC_URL
        elif . == "__GNO_TX_INDEXER_RPC_URL__" then $ENV.GNO_TX_INDEXER_RPC_URL
        elif . == "__VOYAGER_DATABASE_URL__" then $ENV.VOYAGER_DATABASE_URL
        elif . == "__TRUSTED_MPT_PRIVATE_KEY__" then $ENV.TRUSTED_MPT_PRIVATE_KEY
        elif . == "__UNION_PRIVATE_KEY__" then $ENV.UNION_PRIVATE_KEY
        elif . == "__EVM_PRIVATE_KEY__" then $ENV.EVM_PRIVATE_KEY
        elif . == "__GNO_PRIVATE_KEY__" then $ENV.GNO_PRIVATE_KEY
        else . end
    else . end)
    | .plugins |= map(
        if (.path | endswith("voyager-plugin-transaction-batch")) and .config.chain_id == $ENV.EVM_CHAIN_ID
        then .config.client_configs = $plain
        elif (.path | endswith("voyager-plugin-transaction-batch-proof-lens")) and .config.chain_id == $ENV.EVM_CHAIN_ID
        then .config.client_configs = $proof
        else . end
      )
    ' "$template" >"$rendered_config"
  chmod 600 "$rendered_config"
}

render_config "" ""

if grep -Eq '__[A-Z0-9_]+__' "$rendered_config"; then
  echo "rendered config contains an unresolved placeholder" >&2
  exit 1
fi
jq -e --arg evm "$EVM_CHAIN_ID" '
  ([.modules.state[].info.chain_id] | sort | unique) == (["dev.ibc","union-devnet-1",$evm] | sort)
  and ([.modules.client[].info | [.client_type,.ibc_interface]] | sort) == ([
    ["cometbls","ibc-gno"],
    ["cometbls","ibc-solidity"],
    ["gno","ibc-cosmwasm"],
    ["proof-lens","ibc-solidity"],
    ["state-lens/ics23/mpt","ibc-gno"],
    ["trusted/evm/mpt","ibc-cosmwasm"]
  ] | sort)
  and ([.plugins[] | select((.path | endswith("voyager-plugin-transaction-batch")) and .config.chain_id == $evm) | .config.client_configs[].client_id] as $plain
    | [.plugins[] | select((.path | endswith("voyager-plugin-transaction-batch-proof-lens")) and .config.chain_id == $evm) | .config.client_configs[].client_id] as $proof
    | (($plain | length) == 0 and ($proof | length) == 0) or
      (($plain | length) > 0 and ($proof | length) > 0 and (($plain - $proof) | length) == ($plain | length)))
' "$rendered_config" >/dev/null

tracked=("$script_dir/.env.example" "$script_dir/README.md" "$template" \
  "$script_dir/run-channel-e2e.sh" "$script_dir/run-channel-e2e-test.sh" \
  "$script_dir/voyager-build.Dockerfile")
if grep -Eq '0x[0-9a-fA-F]{64}' "${tracked[@]}" || grep -Eq '[[:alpha:]][[:alnum:]+.-]*://[^/@[:space:]]+:[^/@[:space:]]+@' "${tracked[@]}"; then
  echo "tracked E2E files contain a raw private key or credential-bearing URL" >&2
  exit 1
fi

echo "Voyager config render and preflight passed"
if ((!apply)); then
  if ((resume)); then
    :
  else
  echo "dry preflight only; broadcasting requires --apply"
  exit 0
  fi
fi

if [[ -n $voyager_bin ]]; then
  [[ -x $voyager_bin ]] || { echo "Voyager binary is not executable: $voyager_bin" >&2; exit 2; }
else
  command -v docker >/dev/null || { echo "missing required command: docker" >&2; exit 2; }
  [[ -r $script_dir/voyager-build.Dockerfile ]] || {
    echo "missing Voyager Dockerfile: $script_dir/voyager-build.Dockerfile" >&2
    exit 2
  }
fi
if ((erc20_to_gno)); then
  for command in cast curl gnokey; do
    command -v "$command" >/dev/null || { echo "missing required packet command: $command" >&2; exit 2; }
  done
fi
poll_seconds=${VOYAGER_POLL_SECONDS:-2}
# Local beacon finality can take two epochs before EVM events become queryable.
timeout_seconds=${VOYAGER_TIMEOUT_SECONDS:-900}
evm_refresh_seconds=${VOYAGER_EVM_REFRESH_SECONDS:-60}
command_timeout_seconds=${VOYAGER_COMMAND_TIMEOUT_SECONDS:-120}
stop_timeout_seconds=${VOYAGER_STOP_TIMEOUT_SECONDS:-10}
timeout_bin=${TIMEOUT_BIN:-}
[[ -n $timeout_bin ]] || timeout_bin=$(command -v timeout || command -v gtimeout || true)
[[ -x $timeout_bin ]] || { echo "missing required command: timeout (GNU coreutils)" >&2; exit 2; }
[[ $poll_seconds =~ ^[0-9]+$ && $timeout_seconds =~ ^[1-9][0-9]*$ &&
  $command_timeout_seconds =~ ^[1-9][0-9]*$ && $stop_timeout_seconds =~ ^[1-9][0-9]*$ ]] || {
  echo "Voyager poll and timeout values must be non-negative integers" >&2
  exit 2
}

voyager() {
  if [[ -n $voyager_bin ]]; then
    "$timeout_bin" --kill-after="${stop_timeout_seconds}s" "$command_timeout_seconds" \
      "$voyager_bin" -c "$rendered_config" "$@"
  else
    # Keep CLI stdout machine-readable while the daemon retains its diagnostic filter.
    "$timeout_bin" --kill-after="${stop_timeout_seconds}s" "$command_timeout_seconds" \
      docker exec --env RUST_LOG= "$voyager_container" \
      "$voyager_container_bin" -c "$voyager_config_path" "$@"
  fi
}

voyager_enqueue() {
  local attempt output
  for ((attempt = 1; attempt <= 5; attempt += 1)); do
    if output=$(voyager "$@" 2>&1); then
      return 0
    fi
    if [[ $output != *"deadlock detected"* ]]; then
      echo "Voyager enqueue failed" >&2
      return 1
    fi
    # PostgreSQL aborts the deadlocked enqueue transaction, so retrying cannot duplicate its work.
    echo "Voyager enqueue deadlocked; retrying ($attempt/5)" >&2
    sleep "$poll_seconds"
  done
  echo "Voyager enqueue remained deadlocked after 5 attempts" >&2
  return 1
}

voyager_queue_query() {
  local attempt output
  for ((attempt = 1; attempt <= 5; attempt += 1)); do
    if output=$(voyager queue "$@" 2>&1); then
      printf '%s\n' "$output"
      return 0
    fi
    [[ $output == *"deadlock detected"* ]] || { echo "Voyager queue query failed" >&2; return 1; }
    # Queue reads can deadlock with workers immediately after a restart.
    echo "Voyager queue query deadlocked; retrying ($attempt/5)" >&2
    sleep "$poll_seconds"
  done
  echo "Voyager queue query remained deadlocked after 5 attempts" >&2
  return 1
}

stop_voyager() {
  local deadline
  if [[ -n ${voyager_container:-} ]]; then
    if ! docker stop --timeout "$stop_timeout_seconds" "$voyager_container" >/dev/null; then
      echo "failed to stop Voyager container" >&2
      return 1
    fi
    if ! docker rm "$voyager_container" >/dev/null; then
      echo "failed to remove Voyager container" >&2
      return 1
    fi
    voyager_container=
    voyager_container_bin=
    return
  fi
  [[ -n ${voyager_pid:-} ]] || return
  if kill -0 "$voyager_pid" 2>/dev/null; then
    kill "$voyager_pid" 2>/dev/null || true
    deadline=$((SECONDS + stop_timeout_seconds))
    while kill -0 "$voyager_pid" 2>/dev/null && ((SECONDS < deadline)); do sleep 1; done
    kill -KILL "$voyager_pid" 2>/dev/null || true
  fi
  wait "$voyager_pid" 2>/dev/null || true
  voyager_pid=
}

ensure_voyager_image() {
  local image_revision
  # Restarts reuse the image built earlier in the same run.
  ((voyager_image_ready == 0)) || return 0
  echo "building Voyager image from $UNION_VOYAGER_REVISION" >&2
  docker build \
    --file "$script_dir/voyager-build.Dockerfile" \
    --build-arg "UNION_COMMIT=$UNION_VOYAGER_REVISION" \
    --tag "$voyager_image" \
    "$UNION_VOYAGER_DIR"
  image_revision=$(docker image inspect --format \
    '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$voyager_image")
  [[ $image_revision == "$UNION_VOYAGER_REVISION" ]] || {
    echo "Voyager image revision label does not match the pinned checkout" >&2
    return 1
  }
  voyager_image_ready=1
}

start_voyager() {
  local deadline=$((SECONDS + timeout_seconds)) container_name
  if [[ -n $voyager_bin ]]; then
    "$voyager_bin" -c "$rendered_config" start >"$voyager_log" 2>&1 &
    voyager_pid=$!
  else
    ensure_voyager_image
    voyager_container_bin=$(docker image inspect --format '{{index .Config.Entrypoint 0}}' "$voyager_image")
    [[ -n $voyager_container_bin ]] || { echo "Voyager image has no entrypoint" >&2; return 1; }
    container_name="union-channel-e2e-$$"
    # Child modules inherit this filter, so dropped transaction errors remain observable.
    docker run --detach --name "$container_name" \
      --env "RUST_LOG=${VOYAGER_RUST_LOG:-warn}" \
      --mount "type=bind,src=$rendered_config,dst=$voyager_config_path,readonly" \
      "$voyager_image" -c "$voyager_config_path" start >/dev/null
    voyager_container=$container_name
  fi
  until voyager rpc info >/dev/null 2>&1; do
    if [[ -n $voyager_bin ]]; then
      kill -0 "$voyager_pid" 2>/dev/null || { echo "Voyager exited while starting" >&2; return 1; }
    elif [[ $(docker inspect --format '{{.State.Running}}' "$voyager_container" 2>/dev/null) != true ]]; then
      echo "Voyager container exited while starting" >&2
      return 1
    fi
    ((SECONDS < deadline)) || { echo "Voyager RPC was not ready within ${timeout_seconds}s" >&2; return 1; }
    sleep "$poll_seconds"
  done
}

failed_work_id() {
  voyager_queue_query query-failed --per-page 1 | jq -er 'if length == 0 then 0 else .[0].id end'
}

unrepaired_failed_work_id() {
  voyager_queue_query query-failed --per-page 100 | jq -er \
    --slurpfile repaired "$repaired_failed_file" --argjson baseline "$failed_work_baseline" '
    [.[] | .id |= tonumber | .id as $failed_id
      | select($failed_id > $baseline and ($repaired | index($failed_id)) == null)]
    | if length == 0 then $baseline else (map(.id) | max) end
  '
}

record_repaired_failed_work() {
  local id=$1 repaired
  while IFS= read -r repaired; do [[ $repaired == "$id" ]] && return; done <"$repaired_failed_file"
  printf '%s\n' "$id" >>"$repaired_failed_file"
}

client_info() {
  local output
  # Missing clients are reported as null, an empty/garbled type, or an RPC error depending on the backend.
  if ! output=$(voyager rpc client-info "$1" "$2" 2>&1); then
    [[ $output == *client*"not found"* ]] && return 1
    echo "client-info query failed for $1 client $2" >&2
    return 2
  fi
  if jq -e '. == null or (type == "object" and (.client_type | type == "string") and
    (.client_type == "" or (.client_type | test("client not found"; "i"))))' \
    <<<"$output" >/dev/null 2>&1; then
    return 1
  elif jq -e 'type == "object" and (.client_type | type == "string" and length > 0) and
    (.ibc_interface | type == "string" and length > 0)' \
    <<<"$output" >/dev/null 2>&1; then
    echo "$output"
  else
    echo "malformed client-info response for $1 client $2" >&2
    return 2
  fi
}

client_meta() {
  local output
  output=$(voyager rpc client-meta "$1" "$2") || return 2
  if jq -e 'type == "object" and (.counterparty_chain_id | type == "string") and
    (.counterparty_height | type == "string")' <<<"$output" >/dev/null 2>&1; then
    echo "$output"
  elif jq -e '. == null' <<<"$output" >/dev/null 2>&1; then
    return 1
  else
    echo "malformed client-meta response for $1 client $2" >&2
    return 2
  fi
}

client_state() {
  local output
  output=$(voyager rpc client-state "$1" "$2" --decode) || return 2
  if jq -e '.state == null' <<<"$output" >/dev/null 2>&1; then
    return 1
  elif jq -e 'type == "object" and (.state | type == "object")' <<<"$output" >/dev/null 2>&1; then
    echo "$output"
  else
    echo "malformed decoded client-state response for $1 client $2" >&2
    return 2
  fi
}

latest_finalized_height() {
  voyager rpc latest-height "$1" --finalized | jq -er \
    'select(type == "string" and test("^[1-9][0-9]*$"))'
}

next_client_id() {
  local chain=$1 id=1 result
  while :; do
    if client_info "$chain" "$id" >/dev/null; then
      ((id += 1))
    else
      result=$?
      ((result == 1)) || return "$result"
      echo "$id"
      return
    fi
  done
}

requeue_failed_client_events() {
  local chain=$1 client_id=$2 client_type=$3 failed failed_ids failed_id
  # Resume verification has no bootstrap work to repair.
  [[ -n ${failed_work_baseline:-} ]] || return 0
  failed=$(voyager_queue_query query-failed --per-page 100) || return 2
  failed_ids=$(jq -r --slurpfile repaired "$repaired_failed_file" \
    --arg chain "$chain" --arg type "$client_type" \
    --argjson client "$client_id" --argjson baseline "$failed_work_baseline" '
    .[]
    | select((.id | tonumber) > $baseline)
    | (.id | tonumber) as $failed_id
    | select(($repaired | index($failed_id)) == null)
    | . as $failed
    | .item."@value"."@value" as $plugin
    | select(($plugin.plugin // "") | endswith("/" + $chain))
    | $plugin.message."@value".event as $event
    | select($event."@type" == "create_client")
    | select(($event."@value".client_id | tonumber) == $client)
    | select($event."@value".client_type == $type)
    | $failed.id
  ' <<<"$failed") || return 2
  if [[ -n $failed_ids ]]; then
    # A failed create event proves the transaction committed; restart to clear stale chain reads.
    stop_voyager || return 2
    start_voyager || return 2
  fi
  for failed_id in $failed_ids; do
    # The event can race the newly committed client state; retry only this exact failed event.
    echo "requeueing failed create-client event $failed_id for $chain client $client_id" >&2
    voyager_enqueue queue query-failed-by-id "$failed_id" -e || return 2
    record_repaired_failed_work "$failed_id"
  done
}

wait_client() {
  local chain=$1 id=$2 type=$3 interface=$4 counterparty=$5
  local deadline=$((SECONDS + timeout_seconds)) info meta result
  local evm_refreshes=0 next_evm_refresh=$((SECONDS + evm_refresh_seconds))
  while ((SECONDS < deadline)); do
    requeue_failed_client_events "$chain" "$id" "$type" || return 2
    if info=$(client_info "$chain" "$id"); then
      if ! jq -e --arg type "$type" --arg interface "$interface" \
        '.client_type == $type and .ibc_interface == $interface' <<<"$info" >/dev/null; then
        echo "client allocation race: expected $chain client $id to be $type/$interface, got $info" >&2
        return 1
      fi
      if meta=$(client_meta "$chain" "$id"); then
        if ! jq -e --arg counterparty "$counterparty" \
          '.counterparty_chain_id == $counterparty' <<<"$meta" >/dev/null; then
          echo "client allocation race: expected $chain client $id to track $counterparty, got $meta" >&2
          return 1
        fi
        echo "$id"
        return
      else
        result=$?
        ((result == 1)) || return "$result"
      fi
    else
      result=$?
      ((result == 1)) || return "$result"
    fi
    if [[ $chain == "$EVM_CHAIN_ID" ]] && ((evm_refreshes < 3 && SECONDS >= next_evm_refresh)); then
      # The pinned EVM state module can retain an empty clientTypes read across finality.
      echo "refreshing Voyager after stale $chain client $id read ($((evm_refreshes + 1))/3)" >&2
      stop_voyager || return 2
      start_voyager || return 2
      ((evm_refreshes += 1))
      next_evm_refresh=$((SECONDS + evm_refresh_seconds))
    fi
    sleep "$poll_seconds"
  done
  echo "$chain client $id was not visible within ${timeout_seconds}s" >&2
  return 1
}

require_lens_state() {
  local chain=$1 id=$2 l1=$3 l2=$4 l2_chain=$5
  local deadline=$((SECONDS + timeout_seconds)) response result
  while ((SECONDS < deadline)); do
    if response=$(client_state "$chain" "$id"); then
      jq -e --argjson l1 "$l1" --argjson l2 "$l2" --arg l2_chain "$l2_chain" '
        (.state | if has("@value") then ."@value" else . end) as $state
        | ($state | type == "object")
        and (($state.l1_client_id | tonumber) == $l1)
        and (($state.l2_client_id | tonumber) == $l2)
        and ($state.l2_chain_id == $l2_chain)
      ' <<<"$response" >/dev/null || {
        echo "Lens relation mismatch for $chain client $id" >&2
        return 1
      }
      return
    else
      result=$?
      ((result == 1)) || return "$result"
    fi
    sleep "$poll_seconds"
  done
  echo "$chain Lens client $id state was not visible within ${timeout_seconds}s" >&2
  return 1
}

create_client_at() {
  local chain=$1 counterparty=$2 type=$3 interface=$4 id=$5
  shift 5
  [[ $(next_client_id "$chain") == "$id" ]] || {
    echo "client allocation changed: expected $chain client ID $id" >&2
    return 1
  }
  echo "creating $type client at expected $chain client ID $id" >&2
  voyager_enqueue msg create-client --on "$chain" --tracking "$counterparty" \
    --ibc-interface "$interface" --client-type "$type" "$@" -e
  wait_client "$chain" "$id" "$type" "$interface" "$counterparty"
}

ensure_client() {
  local chain=$1 counterparty=$2 type=$3 interface=$4 id
  shift 4
  id=$(next_client_id "$chain")
  create_client_at "$chain" "$counterparty" "$type" "$interface" "$id" "$@"
}

meta_height() {
  client_meta "$1" "$2" | jq -er \
    '.counterparty_height | select(type == "string" and test("^([1-9][0-9]*-)?[1-9][0-9]*$"))'
}

ibc_state() {
  local output
  output=$(voyager rpc ibc-state "$1" "{\"$2\":{\"${2}_id\":$3}}") || return 2
  jq -e 'type == "object" and has("state") and (.state == null or (.state | type == "object"))' \
    <<<"$output" >/dev/null || { echo "malformed $2 state for $1 ID $3" >&2; return 2; }
  echo "$output"
}

next_ibc_id() {
  local chain=$1 kind=$2 id=1 response result
  while :; do
    if response=$(ibc_state "$chain" "$kind" "$id"); then
      :
    else
      result=$?
      return "$result"
    fi
    [[ $(jq -r '.state == null' <<<"$response") == true ]] && { echo "$id"; return; }
    ((id += 1))
  done
}

wait_connection() {
  local chain=$1 id=$2 client=$3 counterparty_client=$4 counterparty_connection=$5
  local deadline=$((SECONDS + timeout_seconds)) response
  while ((SECONDS < deadline)); do
    response=$(ibc_state "$chain" connection "$id") || return
    if [[ $(jq -r '.state == null' <<<"$response") == true ]]; then sleep "$poll_seconds"; continue; fi
    jq -e --argjson client "$client" --argjson cp_client "$counterparty_client" '
      (.state.client_id | tonumber) == $client and
      (.state.counterparty_client_id | tonumber) == $cp_client
    ' <<<"$response" >/dev/null || { echo "connection allocation race: unexpected $chain connection $id" >&2; return 1; }
    if [[ $(jq -r '.state.state | ascii_downcase' <<<"$response") == open ]]; then
      jq -e --argjson cp "$counterparty_connection" '(.state.counterparty_connection_id | tonumber) == $cp' \
        <<<"$response" >/dev/null || { echo "connection allocation race: wrong counterparty for open $chain connection $id" >&2; return 1; }
      echo "$response"
      return
    fi
    sleep "$poll_seconds"
  done
  echo "$chain connection $id did not open within ${timeout_seconds}s" >&2
  return 1
}

wait_channel() {
  local chain=$1 id=$2 connection=$3 counterparty_channel=$4 counterparty_port=$5
  local deadline=$((SECONDS + timeout_seconds)) response
  while ((SECONDS < deadline)); do
    response=$(ibc_state "$chain" channel "$id") || return
    if [[ $(jq -r '.state == null' <<<"$response") == true ]]; then sleep "$poll_seconds"; continue; fi
    jq -e --argjson connection "$connection" --arg port "$counterparty_port" --arg version ucs03-zkgm-0 '
      (.state.connection_id | tonumber) == $connection and
      (.state.counterparty_port_id | ascii_downcase) == ($port | ascii_downcase) and
      .state.version == $version
    ' <<<"$response" >/dev/null || { echo "channel allocation race: unexpected $chain channel $id" >&2; return 1; }
    if [[ $(jq -r '.state.state | ascii_downcase' <<<"$response") == open ]]; then
      jq -e --argjson cp "$counterparty_channel" '(.state.counterparty_channel_id | tonumber) == $cp' \
        <<<"$response" >/dev/null || { echo "channel allocation race: wrong counterparty for open $chain channel $id" >&2; return 1; }
      echo "$response"
      return
    fi
    sleep "$poll_seconds"
  done
  echo "$chain channel $id did not open within ${timeout_seconds}s" >&2
  return 1
}

connection_slot_present() {
  local chain=$1 id=$2 client=$3 counterparty_client=$4 response
  response=$(ibc_state "$chain" connection "$id") || return 2
  [[ $(jq -r '.state == null' <<<"$response") == true ]] && return 1
  jq -e --argjson client "$client" --argjson cp_client "$counterparty_client" '
    (.state.client_id | tonumber) == $client and
    (.state.counterparty_client_id | tonumber) == $cp_client
  ' <<<"$response" >/dev/null || {
    echo "connection allocation race: unexpected $chain connection $id" >&2
    return 2
  }
}

channel_slot_present() {
  local chain=$1 id=$2 connection=$3 counterparty_port=$4 response
  response=$(ibc_state "$chain" channel "$id") || return 2
  [[ $(jq -r '.state == null' <<<"$response") == true ]] && return 1
  jq -e --argjson connection "$connection" --arg port "$counterparty_port" '
    (.state.connection_id | tonumber) == $connection and
    (.state.counterparty_port_id | ascii_downcase) == ($port | ascii_downcase) and
    .state.version == "ucs03-zkgm-0"
  ' <<<"$response" >/dev/null || {
    echo "channel allocation race: unexpected $chain channel $id" >&2
    return 2
  }
}

verify_six_clients() {
  wait_client "$GNO_CHAIN_ID" "$gno_union_client_id" cometbls ibc-gno "$UNION_CHAIN_ID" >/dev/null
  wait_client "$UNION_CHAIN_ID" "$union_gno_client_id" gno ibc-cosmwasm "$GNO_CHAIN_ID" >/dev/null
  wait_client "$UNION_CHAIN_ID" "$union_evm_client_id" trusted/evm/mpt ibc-cosmwasm "$EVM_CHAIN_ID" >/dev/null
  wait_client "$EVM_CHAIN_ID" "$evm_union_client_id" cometbls ibc-solidity "$UNION_CHAIN_ID" >/dev/null
  wait_client "$GNO_CHAIN_ID" "$gno_evm_client_id" state-lens/ics23/mpt ibc-gno "$EVM_CHAIN_ID" >/dev/null
  wait_client "$EVM_CHAIN_ID" "$evm_gno_client_id" proof-lens ibc-solidity "$GNO_CHAIN_ID" >/dev/null
  require_lens_state "$GNO_CHAIN_ID" "$gno_evm_client_id" \
    "$gno_union_client_id" "$union_evm_client_id" "$EVM_CHAIN_ID"
  require_lens_state "$EVM_CHAIN_ID" "$evm_gno_client_id" \
    "$evm_union_client_id" "$union_gno_client_id" "$GNO_CHAIN_ID"
}

packet_command() {
  "$timeout_bin" --kill-after="${stop_timeout_seconds}s" "$command_timeout_seconds" "$@"
}

packet_cast() {
  if ! ETH_RPC_URL="$EVM_PACKET_RPC_URL" packet_command cast "$@" 2>"$packet_cast_error"; then
    echo "packet cast command failed: ${1:-unknown}" >&2
    return 1
  fi
}

packet_gnokey() {
  if ! packet_command gnokey -config "$packet_gnokey_config" "$@" 2>"$packet_gnokey_error"; then
    echo "packet gnokey command failed" >&2
    return 1
  fi
}

packet_curl() {
  if ! packet_command curl --config "$packet_curl_config" --data-binary @- \
    2>"$packet_curl_error" <<<"$1"; then
    echo "packet indexer request failed" >&2
    return 1
  fi
}

decimal_sub() {
  local left=$1 right=$2 borrow=0 digit out='' i
  while [[ $left == 0* && $left != 0 ]]; do left=${left#0}; done
  while [[ $right == 0* && $right != 0 ]]; do right=${right#0}; done
  if ((${#left} < ${#right})) || { ((${#left} == ${#right})) && [[ $left < $right ]]; }; then
    return 1
  fi
  right=$(printf '%*s' "${#left}" "$right")
  right=${right// /0}
  for ((i = ${#left} - 1; i >= 0; i -= 1)); do
    digit=$((10#${left:i:1} - 10#${right:i:1} - borrow))
    if ((digit < 0)); then digit=$((digit + 10)); borrow=1; else borrow=0; fi
    out=$digit$out
  done
  while [[ $out == 0* && $out != 0 ]]; do out=${out#0}; done
  echo "${out:-0}"
}

erc20_balance() {
  local value
  value=$(packet_cast call "$packet_token" 'balanceOf(address)(uint256)' "$1")
  value=${value%% *}
  [[ $value =~ ^[0-9]+$ ]] || { echo "malformed ERC20 balance: $value" >&2; return 1; }
  echo "$value"
}

gno_voucher_balance() {
  local expression output
  expression="$GNO_ZKGM_PORT.VoucherBalanceOf(\"$packet_voucher\",address(\"$packet_recipient\"))"
  output=$(packet_gnokey query vm/qeval -data "$expression")
  [[ $output =~ \(([0-9]+)[[:space:]]+int64\) ]] || {
    echo "malformed Gno voucher balance" >&2
    return 1
  }
  echo "${BASH_REMATCH[1]}"
}

gno_packet_events() {
  local event=$1 hash=$2 query body response
  query=$(printf '{ getTransactions(where: { success: { eq: true } response: { events: { GnoEvent: { type: { eq: "%s" } pkg_path: { eq: "%s" } _and: [{ attrs: { key: { eq: "packet_hash" } value: { eq: "%s" } } }] } } } } order: { heightAndIndex: DESC }) { hash block_height response { events { ... on GnoEvent { type pkg_path attrs { key value } } } } } }' \
    "$event" "$GNO_IBC_CORE_REALM" "$hash")
  body=$(jq -cn --arg query "$query" '{query:$query}')
  response=$(packet_curl "$body")
  jq -e '.errors == null and (.data.getTransactions == null or (.data.getTransactions | type == "array"))' \
    <<<"$response" >/dev/null || {
    echo "malformed Gno indexer response for $event" >&2
    return 1
  }
  jq -c --arg event "$event" --arg hash "$hash" '[(.data.getTransactions // [])[] as $tx
    | $tx.response.events[]
    | select(.type==$event and any(.attrs[]; .key=="packet_hash" and .value==$hash))
    | {tx_hash:$tx.hash,attrs:.attrs}]' <<<"$response"
}

wait_evm_packet_ack() {
  local filter=$1 deadline=$((SECONDS + timeout_seconds)) logs count latest
  while ((SECONDS < deadline)); do
    logs=$(packet_cast rpc eth_getLogs "$filter") || return
    count=$(jq -er 'if type=="array" then length else error("not an array") end' <<<"$logs") || {
      echo "malformed EVM PacketAck log response" >&2
      return 1
    }
    latest=$(failed_work_id)
    [[ $latest == "$packet_failed_baseline" ]] || {
      echo "Voyager recorded new failed work while waiting for EVM PacketAck" >&2
      return 1
    }
    if ((count == 1)); then echo "$logs"; return; fi
    ((count == 0)) || { echo "EVM PacketAck count=$count, want exactly one" >&2; return 1; }
    sleep "$poll_seconds"
  done
  echo "EVM PacketAck was not visible within ${timeout_seconds}s" >&2
  return 1
}

wait_gno_packet_event() {
  local event=$1 deadline=$((SECONDS + timeout_seconds)) events count latest
  while ((SECONDS < deadline)); do
    events=$(gno_packet_events "$event" "$packet_hash") || return
    count=$(jq -r length <<<"$events")
    if ((count == 1)); then jq -c '.[0]' <<<"$events"; return; fi
    ((count == 0)) || { echo "Gno $event count=$count, want exactly one" >&2; return 1; }
    latest=$(failed_work_id)
    [[ $latest == "$packet_failed_baseline" ]] || {
      echo "Voyager recorded new failed work while waiting for $event" >&2
      return 1
    }
    sleep "$poll_seconds"
  done
  echo "Gno $event was not visible within ${timeout_seconds}s" >&2
  return 1
}

success_ack() {
  local ack=${1#0x}
  [[ ${#ack} -ge 64 && ${ack:0:62} == "$(printf '%062d' 0)" && ${ack:62:2} == 01 ]]
}

set_packet_phase() {
  packet_state=$(jq -c --arg phase "$1" '.phase=$phase' <<<"$packet_state")
  write_state "$1"
  phase=$1
}

write_packet_artifact() {
  local tmp
  tmp=$(mktemp "$artifact_dir/.packet-summary.XXXXXX")
  jq -n --arg token "$packet_token" --arg sender "$packet_sender" --arg escrow "$evm_zkgm_lc" \
    --arg recipient "$packet_recipient" --arg voucher "$packet_voucher" --arg hash "$packet_hash" \
    --arg send_tx "$packet_send_tx" --arg recv_tx "$packet_gno_recv_tx" --arg ack_tx "$packet_evm_ack_tx" \
    --arg sc "$evm_channel_id" --arg gc "$gno_channel_id" --arg amount "$packet_amount" \
    --arg sender_delta "$packet_sender_delta" --arg escrow_delta "$packet_escrow_delta" \
    --arg recipient_delta "$packet_recipient_delta" --arg failed_before "$packet_failed_baseline" \
    --arg failed_after "$packet_failed_final" '
    {phase:"packet-complete",token:$token,sender:$sender,escrow:$escrow,recipient:$recipient,
     voucher:$voucher,packet_hash:$hash,transactions:{send:$send_tx,gno_receive:$recv_tx,evm_ack:$ack_tx},
     channels:{evm:($sc|tonumber),gno:($gc|tonumber)},amounts:{sent_18_decimals:$amount,
       sender_delta:$sender_delta,escrow_delta:$escrow_delta,recipient_delta_6_decimals:$recipient_delta},
     failed_work:{baseline:($failed_before|tonumber),final:($failed_after|tonumber)}}
  ' >"$tmp"
  chmod 600 "$tmp"
  if grep -Eq '[[:alpha:]][[:alnum:]+.-]*://[^/@[:space:]]+:[^/@[:space:]]+@' "$tmp" ||
    grep -Fq "$TRUSTED_MPT_PRIVATE_KEY" "$tmp" || grep -Fq "$UNION_PRIVATE_KEY" "$tmp" ||
    grep -Fq "$EVM_PRIVATE_KEY" "$tmp" || grep -Fq "$GNO_PRIVATE_KEY" "$tmp"; then
    echo "packet artifact secret scan failed" >&2
    rm -f "$tmp"
    return 1
  fi
  mv -f "$tmp" "$artifact_dir/packet-summary.json"
}

write_state() {
  local tmp repaired
  tmp=$(mktemp "$artifact_dir/.state.XXXXXX")
  repaired=$(jq -Rsc 'split("\n") | map(select(length > 0) | tonumber)' "$repaired_failed_file")
  if ! jq -n --arg phase "$1" --arg revision "$UNION_VOYAGER_REVISION" \
    --arg union "$UNION_CHAIN_ID" --arg evm "$EVM_CHAIN_ID" --arg gno "$GNO_CHAIN_ID" \
    --arg evm_fingerprint "$evm_address_fingerprint" \
    --arg gno_port "$GNO_ZKGM_PORT" --arg evm_port "$evm_zkgm_lc" \
    --arg baseline "$failed_work_baseline" --arg final "${failed_work_final:-}" --argjson repaired "$repaired" \
    --arg gu "$gno_union_client_id" --arg ug "$union_gno_client_id" \
    --arg us "$union_evm_client_id" --arg su "$evm_union_client_id" \
    --arg gs "$gno_evm_client_id" --arg sg "$evm_gno_client_id" \
    --arg gc "${gno_connection_id:-}" --arg sc "${evm_connection_id:-}" \
    --arg gh "${gno_channel_id:-}" --arg sh "${evm_channel_id:-}" \
    --arg plain "$plain_csv" --arg proof "$proof_csv" --argjson packet "${packet_state:-null}" '
    {phase:$phase,voyager_revision:$revision,chains:{union:$union,evm:$evm,gno:$gno},
     evm_topology:{chain_id:$evm,address_fingerprint:$evm_fingerprint},
     ports:{gno:$gno_port,evm:$evm_port},version:"ucs03-zkgm-0",
     failed_work:{baseline:($baseline|tonumber),final:(if $final=="" then null else ($final|tonumber) end),
       repaired:$repaired},
     clients:{gno_union:($gu|tonumber),union_gno:($ug|tonumber),union_evm:($us|tonumber),
       evm_union:($su|tonumber),gno_evm:($gs|tonumber),evm_gno:($sg|tonumber)},
     allowlists:{plain:$plain,proof_lens:$proof}}
    + (if $gc=="" then {} else {connections:{gno:($gc|tonumber),evm:($sc|tonumber)}} end)
    + (if $gh=="" then {} else {channels:{gno:($gh|tonumber),evm:($sh|tonumber)}} end)
    + (if $packet==null then {} else {packet:$packet} end)
  ' >"$tmp"; then rm -f "$tmp"; return 1; fi
  chmod 600 "$tmp"
  if ! jq -e '(.phase|type)=="string" and (.clients|type)=="object" and (.failed_work.baseline|numbers)' "$tmp" >/dev/null; then
    rm -f "$tmp"
    return 1
  fi
  mv -f "$tmp" "$state_file"
}

write_bootstrap_checkpoint() {
  local payload
  payload=$(jq -n --arg revision "$UNION_VOYAGER_REVISION" \
    --arg union "$UNION_CHAIN_ID" --arg evm "$EVM_CHAIN_ID" --arg gno "$GNO_CHAIN_ID" \
    --arg evm_fingerprint "$evm_address_fingerprint" \
    '{phase:"bootstrap-in-progress",voyager_revision:$revision,
      chains:{union:$union,evm:$evm,gno:$gno},
      evm_topology:{chain_id:$evm,address_fingerprint:$evm_fingerprint}}')
  jq -e '.phase=="bootstrap-in-progress" and (.voyager_revision|type)=="string"' \
    <<<"$payload" >/dev/null
  if ! (set -o noclobber; printf '%s\n' "$payload" >"$bootstrap_file") 2>/dev/null; then
    echo "bootstrap checkpoint already exists; refusing to enqueue clients again" >&2
    return 1
  fi
  chmod 600 "$bootstrap_file"
}

write_artifacts() {
  local tmp files file
  tmp=$(mktemp -d "$artifact_dir/.artifacts.XXXXXX")
  chmod 700 "$tmp"
  files=(gno-connection.json evm-connection.json gno-channel.json evm-channel.json commands.json summary.json)
  printf '%s\n' "$gno_connection_state" >"$tmp/gno-connection.json"
  printf '%s\n' "$evm_connection_state" >"$tmp/evm-connection.json"
  printf '%s\n' "$gno_channel_state" >"$tmp/gno-channel.json"
  printf '%s\n' "$evm_channel_state" >"$tmp/evm-channel.json"
  jq -n --arg connection "$connection_op" --arg channel "$channel_op" \
    '{connection_open_init:($connection|fromjson),channel_open_init:($channel|fromjson)}' >"$tmp/commands.json"
  jq '{phase,chains,evm_topology,ports,version,failed_work,clients,connections,channels}' "$state_file" >"$tmp/summary.json"
  chmod 600 "${files[@]/#/$tmp/}"
  if grep -Eq '0x[0-9a-fA-F]{64}([^0-9a-fA-F]|$)|[[:alpha:]][[:alnum:]+.-]*://[^/@[:space:]]+:[^/@[:space:]]+@' "${files[@]/#/$tmp/}"; then
    echo "artifact secret scan failed" >&2
    rm -f "${files[@]/#/$tmp/}"
    rmdir "$tmp"
    return 1
  fi
  for file in "${files[@]}"; do mv -f "$tmp/$file" "$artifact_dir/$file"; done
  rmdir "$tmp"
}

prepare_artifact_dir() {
  local repo_root
  repo_root=$(git rev-parse --show-toplevel)
  [[ $state_file == "$artifact_dir/state.json" ]] || { echo "E2E_STATE_FILE must be E2E_ARTIFACT_DIR/state.json" >&2; return 2; }
  [[ $artifact_dir != "$repo_root" && $artifact_dir != "$script_dir" && ! -L $artifact_dir ]] || {
    echo "unsafe E2E_ARTIFACT_DIR: $artifact_dir" >&2; return 2; }
  if [[ -e $artifact_dir ]]; then
    [[ -d $artifact_dir && -f $artifact_marker && ! -L $artifact_marker ]] || {
      echo "existing artifact directory is not owned by this runner: $artifact_dir" >&2; return 2; }
    [[ $(<"$artifact_marker") == union-channel-e2e-artifacts ]] || { echo "invalid artifact marker" >&2; return 2; }
  else
    mkdir -p "$artifact_dir"
    chmod 700 "$artifact_dir"
    printf '%s\n' union-channel-e2e-artifacts >"$artifact_marker"
    chmod 600 "$artifact_marker"
  fi
  [[ ! -L $state_file ]] || { echo "resume state must not be a symlink" >&2; return 2; }
  [[ ! -L $bootstrap_file ]] || { echo "bootstrap checkpoint must not be a symlink" >&2; return 2; }
}

gno_port_hex=0x$(printf %s "$GNO_ZKGM_PORT" | od -An -tx1 | tr -d ' \n')
prepare_artifact_dir

if ((resume)); then
  [[ -r $state_file ]] || { echo "missing resume state: $state_file" >&2; exit 2; }
  state_mode=$(stat -f '%Lp' "$state_file" 2>/dev/null || stat -c '%a' "$state_file")
  if [[ $state_mode != 600 ]]; then
    echo "resume state must be mode 0600" >&2
    exit 2
  fi
  jq -e --arg revision "$UNION_VOYAGER_REVISION" --arg union "$UNION_CHAIN_ID" --arg gno "$GNO_CHAIN_ID" --arg evm "$EVM_CHAIN_ID" \
    --arg evm_fingerprint "$evm_address_fingerprint" --arg gp "$GNO_ZKGM_PORT" --arg sp "$evm_zkgm_lc" '
    .voyager_revision==$revision and .chains.union==$union and .chains.gno==$gno and .chains.evm==$evm and
    .evm_topology=={chain_id:$evm,address_fingerprint:$evm_fingerprint} and
    .ports.gno==$gp and (.ports.evm|ascii_downcase)==$sp and .version=="ucs03-zkgm-0" and
    (.clients|type)=="object"
  ' "$state_file" >/dev/null || { echo "resume state does not match this topology" >&2; exit 2; }
  gno_union_client_id=$(jq -er '.clients.gno_union|numbers' "$state_file")
  union_gno_client_id=$(jq -er '.clients.union_gno|numbers' "$state_file")
  union_evm_client_id=$(jq -er '.clients.union_evm|numbers' "$state_file")
  evm_union_client_id=$(jq -er '.clients.evm_union|numbers' "$state_file")
  gno_evm_client_id=$(jq -er '.clients.gno_evm|numbers' "$state_file")
  evm_gno_client_id=$(jq -er '.clients.evm_gno|numbers' "$state_file")
  plain_csv=$(jq -r .allowlists.plain "$state_file") proof_csv=$(jq -r .allowlists.proof_lens "$state_file")
  phase=$(jq -r .phase "$state_file")
  render_config "$plain_csv" "$proof_csv"
  start_voyager
  verify_six_clients
  gno_connection_id=$(jq -r '.connections.gno // empty' "$state_file")
  evm_connection_id=$(jq -r '.connections.evm // empty' "$state_file")
  gno_channel_id=$(jq -r '.channels.gno // empty' "$state_file")
  evm_channel_id=$(jq -r '.channels.evm // empty' "$state_file")
  packet_state=$(jq -c '.packet // null' "$state_file")
  [[ $packet_state != null ]] || packet_state=
  failed_work_baseline=$(jq -r 'if .phase=="complete" or (.phase|startswith("packet-")) then .failed_work.final else .failed_work.baseline end' "$state_file")
  jq -r '.failed_work.repaired[]?' "$state_file" >"$repaired_failed_file"
else
  [[ ! -e $state_file ]] || {
    echo "state already exists; use --resume to reuse its client IDs or choose a new E2E_ARTIFACT_DIR" >&2
    exit 2
  }
  [[ ! -e $bootstrap_file ]] || {
    echo "bootstrap checkpoint already exists; refusing to enqueue clients again" >&2
    exit 2
  }
  start_voyager
  failed_work_baseline=$(failed_work_id)
  echo "Voyager failed-work baseline ID: $failed_work_baseline"

  bootstrap_plain_id=$(next_client_id "$EVM_CHAIN_ID")
  bootstrap_proof_id=$((bootstrap_plain_id + 1))
  render_config "$bootstrap_plain_id" "$bootstrap_proof_id"
  stop_voyager
  start_voyager
  write_bootstrap_checkpoint

evm_index_from=$(latest_finalized_height "$EVM_CHAIN_ID")
for chain in "$UNION_CHAIN_ID" "$GNO_CHAIN_ID"; do
  echo "indexing $chain"
  voyager_enqueue index "$chain" -e
done

gno_union_client_id=$(ensure_client "$GNO_CHAIN_ID" "$UNION_CHAIN_ID" cometbls ibc-gno)
union_gno_client_id=$(ensure_client "$UNION_CHAIN_ID" "$GNO_CHAIN_ID" gno ibc-cosmwasm)
union_evm_client_id=$(ensure_client "$UNION_CHAIN_ID" "$EVM_CHAIN_ID" trusted/evm/mpt ibc-cosmwasm)
evm_union_client_id=$(create_client_at "$EVM_CHAIN_ID" "$UNION_CHAIN_ID" cometbls ibc-solidity \
  "$bootstrap_plain_id")

state_lens_height=$(meta_height "$UNION_CHAIN_ID" "$union_evm_client_id")
state_lens_config=$(jq -cn \
  --arg host "$GNO_CHAIN_ID" --argjson l1 "$gno_union_client_id" --argjson l2 "$union_evm_client_id" \
  '{l1_client_id:$l1,host_chain_id:$host,l2_client_id:$l2,timestamp_offset:88,state_root_offset:0,storage_root_offset:32}')
gno_evm_client_id=$(ensure_client "$GNO_CHAIN_ID" "$EVM_CHAIN_ID" state-lens/ics23/mpt ibc-gno \
  --config "$state_lens_config" --height "$state_lens_height")
require_lens_state "$GNO_CHAIN_ID" "$gno_evm_client_id" \
  "$gno_union_client_id" "$union_evm_client_id" "$EVM_CHAIN_ID"

proof_lens_height=$(meta_height "$UNION_CHAIN_ID" "$union_gno_client_id")
proof_lens_config=$(jq -cn \
  --arg host "$EVM_CHAIN_ID" --argjson l1 "$evm_union_client_id" --argjson l2 "$union_gno_client_id" \
  '{l1_client_id:$l1,host_chain_id:$host,l2_client_id:$l2,timestamp_offset:24}')
evm_gno_client_id=$(create_client_at "$EVM_CHAIN_ID" "$GNO_CHAIN_ID" proof-lens ibc-solidity \
  "$bootstrap_proof_id" --config "$proof_lens_config" --height "$proof_lens_height")
require_lens_state "$EVM_CHAIN_ID" "$evm_gno_client_id" \
  "$evm_union_client_id" "$union_gno_client_id" "$GNO_CHAIN_ID"

# Local beacon finality can lead geth briefly; index the saved range only after both EVM clients settle.
echo "indexing $EVM_CHAIN_ID from finalized height $evm_index_from"
voyager_enqueue index "$EVM_CHAIN_ID" --from "$evm_index_from" -e

evm_next=$(next_client_id "$EVM_CHAIN_ID")
plain_ids=()
proof_ids=()
for ((id = 1; id < evm_next; id += 1)); do
  info=$(client_info "$EVM_CHAIN_ID" "$id") || { echo "cannot inspect EVM client $id" >&2; exit 1; }
  if [[ $(jq -r '.client_type' <<<"$info") == proof-lens ]]; then
    proof_ids+=("$id")
  else
    plain_ids+=("$id")
  fi
done
(( ${#plain_ids[@]} > 0 && ${#proof_ids[@]} > 0 )) || {
  echo "EVM plain and Proof Lens client allowlists must both be non-empty" >&2
  exit 1
}
plain_csv=$(IFS=,; echo "${plain_ids[*]}")
proof_csv=$(IFS=,; echo "${proof_ids[*]}")
render_config "$plain_csv" "$proof_csv"
stop_voyager
start_voyager

verify_six_clients
echo "six clients verified; EVM plain IDs=$plain_csv Proof Lens IDs=$proof_csv"

gno_connection_id=$(next_ibc_id "$GNO_CHAIN_ID" connection)
evm_connection_id=$(next_ibc_id "$EVM_CHAIN_ID" connection)
write_state connection-submitting
rm -f "$bootstrap_file"
phase='connection-submitting'
connection_enqueue_now=1
fi

connection_op=$(jq -cn --arg chain "$EVM_CHAIN_ID" --argjson local "$evm_gno_client_id" \
  --argjson remote "$gno_evm_client_id" '{"@type":"call","@value":{"@type":"submit_tx","@value":{
  chain_id:$chain,datagrams:[{ibc_spec_id:"ibc-union",datagram:{"@type":"connection_open_init",
  "@value":{client_id:$local,counterparty_client_id:$remote}}}]}}}')

[[ -n ${gno_connection_id:-} && -n ${evm_connection_id:-} ]] || {
  echo "saved state has no connection IDs; verification-only resume will not broadcast" >&2
  exit 1
}
if [[ $phase == connection-submitting || $phase == connection-prepared ]]; then
  if (( ${connection_enqueue_now:-0} )); then
    voyager_enqueue q e "$connection_op"
    write_state connection-submitted
    phase='connection-submitted'
  else
    gno_present=0
    evm_present=0
    if connection_slot_present "$GNO_CHAIN_ID" "$gno_connection_id" "$gno_evm_client_id" "$evm_gno_client_id"; then
      gno_present=1
    else
      result=$?
      ((result == 1)) || exit "$result"
    fi
    if connection_slot_present "$EVM_CHAIN_ID" "$evm_connection_id" "$evm_gno_client_id" "$gno_evm_client_id"; then
      evm_present=1
    else
      result=$?
      ((result == 1)) || exit "$result"
    fi
    if ((gno_present || evm_present)); then
      write_state connection-submitted
      phase='connection-submitted'
    else
      echo "connection submission is ambiguous; refusing to enqueue it again" >&2
      exit 1
    fi
  fi
fi

gno_connection_state=$(wait_connection "$GNO_CHAIN_ID" "$gno_connection_id" "$gno_evm_client_id" \
  "$evm_gno_client_id" "$evm_connection_id")
evm_connection_state=$(wait_connection "$EVM_CHAIN_ID" "$evm_connection_id" "$evm_gno_client_id" \
  "$gno_evm_client_id" "$gno_connection_id")

if [[ -z ${gno_channel_id:-} || -z ${evm_channel_id:-} ]]; then
  ((apply)) || { echo "saved state has no channel IDs; --resume will not broadcast" >&2; exit 1; }
  gno_channel_id=$(next_ibc_id "$GNO_CHAIN_ID" channel)
  evm_channel_id=$(next_ibc_id "$EVM_CHAIN_ID" channel)
  write_state channel-submitting
  phase='channel-submitting'
  channel_enqueue_now=1
fi
channel_op=$(jq -cn --arg chain "$GNO_CHAIN_ID" --arg port "$gno_port_hex" --arg cp_port "$evm_zkgm_lc" \
  --argjson connection "$gno_connection_id" '{"@type":"call","@value":{"@type":"submit_tx","@value":{
  chain_id:$chain,datagrams:[{ibc_spec_id:"ibc-union",datagram:{"@type":"channel_open_init","@value":{
  port_id:$port,counterparty_port_id:$cp_port,connection_id:$connection,version:"ucs03-zkgm-0"}}}]}}}')
if [[ $phase == channel-submitting || $phase == channel-prepared ]]; then
  if (( ${channel_enqueue_now:-0} )); then
    voyager_enqueue q e "$channel_op"
    write_state channel-submitted
    phase='channel-submitted'
  else
    gno_present=0
    evm_present=0
    if channel_slot_present "$GNO_CHAIN_ID" "$gno_channel_id" "$gno_connection_id" "$evm_zkgm_lc"; then
      gno_present=1
    else
      result=$?
      ((result == 1)) || exit "$result"
    fi
    if channel_slot_present "$EVM_CHAIN_ID" "$evm_channel_id" "$evm_connection_id" "$gno_port_hex"; then
      evm_present=1
    else
      result=$?
      ((result == 1)) || exit "$result"
    fi
    if ((gno_present || evm_present)); then
      write_state channel-submitted
      phase='channel-submitted'
    else
      echo "channel submission is ambiguous; refusing to enqueue it again" >&2
      exit 1
    fi
  fi
fi
gno_channel_state=$(wait_channel "$GNO_CHAIN_ID" "$gno_channel_id" "$gno_connection_id" \
  "$evm_channel_id" "$evm_zkgm_lc")
evm_channel_state=$(wait_channel "$EVM_CHAIN_ID" "$evm_channel_id" "$evm_connection_id" \
  "$gno_channel_id" "$gno_port_hex")
failed_work_final=$(unrepaired_failed_work_id)
if [[ $failed_work_final != "$failed_work_baseline" ]]; then
  write_state failed-work
  write_artifacts
  echo "Voyager recorded new failed work after ID $failed_work_baseline (latest $failed_work_final)" >&2
  exit 1
fi
if [[ $phase != packet-* ]]; then
  write_state complete
  phase=complete
  write_artifacts
fi
echo "connection/channel verified; artifacts: $artifact_dir"

((erc20_to_gno)) || exit 0
[[ $phase == complete || $phase == packet-* ]] || {
  echo "ERC20 packet requires a verified complete connection/channel state" >&2
  exit 1
}

if [[ $phase == complete ]]; then
  packet_token=$(tr '[:upper:]' '[:lower:]' <<<"$EVM_TEST_ERC20")
  packet_recipient=$GNO_RECIPIENT
  packet_amount=$EVM_TEST_AMOUNT
  packet_sender=$(packet_cast wallet address --private-key "$EVM_PRIVATE_KEY")
  packet_sender=$(tr '[:upper:]' '[:lower:]' <<<"$packet_sender")
  [[ $packet_sender =~ ^0x[0-9a-f]{40}$ ]] || { echo "cannot derive EVM sender" >&2; exit 1; }
  token_code=$(packet_cast code "$packet_token")
  [[ $token_code =~ ^0x[0-9a-fA-F]+$ && $token_code != 0x ]] || {
    echo "EVM_TEST_ERC20 has no deployed code" >&2
    exit 1
  }
  token_decimals=$(packet_cast call "$packet_token" 'decimals()(uint8)')
  token_decimals=${token_decimals%% *}
  [[ $token_decimals == 18 ]] || { echo "EVM_TEST_ERC20 must report 18 decimals" >&2; exit 1; }

  packet_salt=$(packet_cast keccak "0x$(printf %s \
    "$packet_sender:$packet_amount:$(date +%s):$$:${runtime_dir##*.}" | od -An -tx1 | tr -d ' \n')")
  packet_tag=${packet_salt:2}
  packet_initializer=$(packet_cast abi-encode 'f(string,string,uint8)' \
    "Union E2E ${packet_tag:0:32}" "UE${packet_tag:0:6}" 18)
  packet_metadata=$(packet_cast abi-encode 'f(bytes,bytes)' 0x6772633230 "$packet_initializer")
  packet_metadata_image=$(packet_cast keccak "$packet_metadata")
  packet_prediction=$(packet_cast abi-encode 'f(uint256,uint32,bytes,uint256)' \
    0 "$gno_channel_id" "$packet_token" "$packet_metadata_image")
  packet_voucher_hash=$(packet_cast keccak "$packet_prediction")
  packet_voucher=ibc/${packet_voucher_hash:2:40}
  packet_failed_baseline=$(failed_work_id)
  packet_state=$(jq -cn --arg token "$packet_token" --arg sender "$packet_sender" \
    --arg recipient "$packet_recipient" --arg amount "$packet_amount" --arg voucher "$packet_voucher" \
    --arg salt "$packet_salt" --arg tag "$packet_tag" --arg failed "$packet_failed_baseline" \
    '{phase:"packet-mint-submitting",token:$token,sender:$sender,recipient:$recipient,amount:$amount,
      voucher:$voucher,salt:$salt,tag:$tag,failed_work_baseline:($failed|tonumber)}')
  set_packet_phase packet-mint-submitting
  packet_mint_now=1
else
  jq -e --arg token "$(tr '[:upper:]' '[:lower:]' <<<"$EVM_TEST_ERC20")" \
    --arg recipient "$GNO_RECIPIENT" --arg amount "$EVM_TEST_AMOUNT" '
    .token==$token and .recipient==$recipient and .amount==$amount and
    (.sender|test("^0x[0-9a-f]{40}$")) and (.voucher|test("^ibc/[0-9a-fA-F]{40}$"))
  ' <<<"$packet_state" >/dev/null || { echo "saved packet state does not match packet settings" >&2; exit 2; }
  packet_token=$(jq -r .token <<<"$packet_state")
  packet_sender=$(jq -r .sender <<<"$packet_state")
  packet_recipient=$(jq -r .recipient <<<"$packet_state")
  packet_amount=$(jq -r .amount <<<"$packet_state")
  packet_voucher=$(jq -r .voucher <<<"$packet_state")
  packet_salt=$(jq -r .salt <<<"$packet_state")
  packet_tag=$(jq -r .tag <<<"$packet_state")
  [[ $packet_tag =~ ^[0-9a-fA-F]{64}$ ]] || { echo "saved packet tag is malformed" >&2; exit 2; }
  packet_initializer=$(packet_cast abi-encode 'f(string,string,uint8)' \
    "Union E2E ${packet_tag:0:32}" "UE${packet_tag:0:6}" 18)
  packet_metadata=$(packet_cast abi-encode 'f(bytes,bytes)' 0x6772633230 "$packet_initializer")
  packet_failed_baseline=$(jq -r .failed_work_baseline <<<"$packet_state")
fi

if [[ $phase == packet-mint-submitting ]]; then
  ((${packet_mint_now:-0})) || {
    echo "ERC20 mint submission is ambiguous; refusing to mint again" >&2
    exit 1
  }
  mint_receipt=$(packet_cast send "$packet_token" \
    'mint(address,uint256)' "$packet_sender" "$packet_amount" --private-key "$EVM_PRIVATE_KEY" --json)
  jq -e '.status=="0x1" and (.transactionHash|test("^0x[0-9a-fA-F]{64}$"))' <<<"$mint_receipt" >/dev/null || {
    echo "ERC20 mint transaction failed" >&2
    exit 1
  }
  packet_state=$(jq -c --arg tx "$(jq -r .transactionHash <<<"$mint_receipt")" '.mint_tx=$tx' <<<"$packet_state")
  set_packet_phase packet-mint-submitted
fi

if [[ $phase == packet-mint-submitted ]]; then
  set_packet_phase packet-approve-submitting
  packet_approve_now=1
fi
if [[ $phase == packet-approve-submitting ]]; then
  ((${packet_approve_now:-0})) || {
    echo "ERC20 approval submission is ambiguous; refusing to approve again" >&2
    exit 1
  }
  approve_receipt=$(packet_cast send "$packet_token" \
    'approve(address,uint256)' "$evm_zkgm_lc" "$packet_amount" --private-key "$EVM_PRIVATE_KEY" --json)
  jq -e '.status=="0x1" and (.transactionHash|test("^0x[0-9a-fA-F]{64}$"))' <<<"$approve_receipt" >/dev/null || {
    echo "ERC20 approve transaction failed" >&2
    exit 1
  }
  packet_state=$(jq -c --arg tx "$(jq -r .transactionHash <<<"$approve_receipt")" '.approve_tx=$tx' <<<"$packet_state")
  set_packet_phase packet-approve-submitted
fi

if [[ $phase == packet-approve-submitted ]]; then
  packet_sender_before=$(erc20_balance "$packet_sender")
  packet_escrow_before=$(erc20_balance "$evm_zkgm_lc")
  packet_recipient_before=$(gno_voucher_balance)
  packet_evm_from_block=$(packet_cast block-number)
  [[ $packet_evm_from_block =~ ^[0-9]+$ ]] || { echo "malformed EVM block number" >&2; exit 1; }
  packet_state=$(jq -c --arg sender "$packet_sender_before" --arg escrow "$packet_escrow_before" \
    --arg recipient "$packet_recipient_before" --arg block "$packet_evm_from_block" \
    '.balances_before={sender:$sender,escrow:$escrow,recipient:$recipient}|.evm_from_block=($block|tonumber)' <<<"$packet_state")
  set_packet_phase packet-send-submitting
  packet_send_now=1
fi
if [[ $phase == packet-send-submitting ]]; then
  ((${packet_send_now:-0})) || {
    echo "ERC20 packet submission is ambiguous; refusing to send again" >&2
    exit 1
  }
  packet_sender_before=$(jq -r .balances_before.sender <<<"$packet_state")
  packet_escrow_before=$(jq -r .balances_before.escrow <<<"$packet_state")
  packet_recipient_before=$(jq -r .balances_before.recipient <<<"$packet_state")
  packet_evm_from_block=$(jq -r .evm_from_block <<<"$packet_state")
  packet_receiver_hex=0x$(printf %s "$packet_recipient" | od -An -tx1 | tr -d ' \n')
  packet_quote_hex=0x$(printf %s "$packet_voucher" | od -An -tx1 | tr -d ' \n')
  packet_operand=$(packet_cast abi-encode 'f(bytes,bytes,bytes,uint256,bytes,uint256,uint8,bytes)' \
    "$packet_sender" "$packet_receiver_hex" "$packet_token" "$packet_amount" "$packet_quote_hex" \
    "$packet_amount" 0 "$packet_metadata")
  packet_timeout_timestamp=$((($(date +%s) + 3600) * 1000000000))
  send_receipt=$(packet_cast send "$evm_zkgm_lc" \
    'send(uint32,uint64,uint64,bytes32,(uint8,uint8,bytes))' "$evm_channel_id" 0 \
    "$packet_timeout_timestamp" "$packet_salt" "(2,3,$packet_operand)" \
    --private-key "$EVM_PRIVATE_KEY" --json)
  jq -e '.status=="0x1" and (.transactionHash|test("^0x[0-9a-fA-F]{64}$"))' <<<"$send_receipt" >/dev/null || {
    echo "ERC20 packet transaction failed" >&2
    exit 1
  }
  packet_send_tx=$(jq -r .transactionHash <<<"$send_receipt")
  packet_send_topic=0x635b5d234fe7abddfb29b6c8498780a31
  packet_send_topic+=75c9002c537f20a3d1bf9d0e625b5fe
  packet_hash=$(jq -er --arg handler "$EVM_IBC_HANDLER" --arg topic "$packet_send_topic" '
    [.logs[] | select((.address|ascii_downcase)==($handler|ascii_downcase) and
      (.topics[0]|ascii_downcase)==($topic|ascii_downcase)) | .topics[2]]
    | if length==1 then .[0] else error("PacketSend count is not one") end
  ' <<<"$send_receipt")
  [[ $packet_hash =~ ^0x[0-9a-fA-F]{64}$ ]] || { echo "malformed PacketSend hash" >&2; exit 1; }
  packet_state=$(jq -c --arg tx "$packet_send_tx" --arg hash "$packet_hash" \
    '.send_tx=$tx|.packet_hash=$hash' <<<"$packet_state")
  set_packet_phase packet-send-submitted
fi

packet_send_tx=$(jq -r .send_tx <<<"$packet_state")
packet_hash=$(jq -r .packet_hash <<<"$packet_state")
packet_sender_before=$(jq -r .balances_before.sender <<<"$packet_state")
packet_escrow_before=$(jq -r .balances_before.escrow <<<"$packet_state")
packet_recipient_before=$(jq -r .balances_before.recipient <<<"$packet_state")
packet_evm_from_block=$(jq -r .evm_from_block <<<"$packet_state")

gno_recv=$(wait_gno_packet_event PacketRecv)
gno_write=$(wait_gno_packet_event WriteAck)
packet_gno_recv_tx=$(jq -r .tx_hash <<<"$gno_recv")
[[ $packet_gno_recv_tx == "$(jq -r .tx_hash <<<"$gno_write")" ]] || {
  echo "Gno PacketRecv and WriteAck transactions differ" >&2
  exit 1
}
gno_ack=$(jq -r '[.attrs[] | select(.key=="acknowledgement" or (.key|startswith("acknowledgement["))) | .value] | join("")' <<<"$gno_write")

packet_from_hex=$(printf '0x%x' "$packet_evm_from_block")
packet_channel_topic=$(printf '0x%064x' "$evm_channel_id")
packet_ack_topic=0x41d958a7d93b50b1f7541c6fc345d0c
packet_ack_topic+=4657b1e83497baa562c866611ac1f69bb
ack_filter=$(jq -cn --arg address "$EVM_IBC_HANDLER" --arg from "$packet_from_hex" \
  --arg topic "$packet_ack_topic" \
  --arg channel "$packet_channel_topic" --arg hash "$packet_hash" \
  '{address:$address,fromBlock:$from,toBlock:"latest",topics:[$topic,$channel,$hash]}')
evm_acks=$(wait_evm_packet_ack "$ack_filter")
packet_evm_ack_tx=$(jq -r '.[0].transactionHash' <<<"$evm_acks")
evm_ack=$(packet_cast decode-abi 'f()(bytes)' "$(jq -r '.[0].data' <<<"$evm_acks")" --json | jq -er '.[0]')
gno_success=0
evm_success=0
success_ack "$gno_ack" && gno_success=1
success_ack "$evm_ack" && evm_success=1
[[ $gno_success == "$evm_success" ]] || { echo "Gno and EVM acknowledgement results differ" >&2; exit 1; }

packet_commitment_path=$(packet_cast abi-encode 'f(uint256,bytes32)' 4 "$packet_hash")
packet_commitment_key=$(packet_cast keccak "$packet_commitment_path")
packet_commitment=$(packet_cast call "$EVM_IBC_HANDLER" 'commitments(bytes32)(bytes32)' "$packet_commitment_key")
packet_commitment_cleared=0x02$(printf '%062d' 0)
packet_commitment=$(tr '[:upper:]' '[:lower:]' <<<"$packet_commitment")
[[ $packet_commitment == "$packet_commitment_cleared" ]] || {
  echo "EVM packet commitment is still active" >&2
  exit 1
}

packet_sender_after=$(erc20_balance "$packet_sender")
packet_escrow_after=$(erc20_balance "$evm_zkgm_lc")
packet_recipient_after=$(gno_voucher_balance)
packet_sender_delta=$(decimal_sub "$packet_sender_before" "$packet_sender_after") || {
  echo "ERC20 sender balance increased unexpectedly" >&2; exit 1; }
packet_escrow_delta=$(decimal_sub "$packet_escrow_after" "$packet_escrow_before") || {
  echo "ERC20 escrow balance decreased unexpectedly" >&2; exit 1; }
packet_recipient_delta=$((packet_recipient_after - packet_recipient_before))
packet_recipient_expected=${packet_amount%000000000000}
if ((gno_success)); then
  [[ $packet_sender_delta == "$packet_amount" && $packet_escrow_delta == "$packet_amount" &&
    $packet_recipient_delta == "$packet_recipient_expected" ]] || {
    echo "packet balance deltas do not match the sent amount" >&2
    exit 1
  }
else
  [[ $packet_sender_delta == 0 && $packet_escrow_delta == 0 && $packet_recipient_delta == 0 ]] || {
    echo "packet failure did not refund the escrowed ERC20" >&2
    exit 1
  }
fi
packet_failed_final=$(failed_work_id)
[[ $packet_failed_final == "$packet_failed_baseline" ]] || {
  echo "Voyager recorded new failed work during the ERC20 packet" >&2
  exit 1
}
if ((!gno_success)); then
  echo "packet failure acknowledgement and escrow refund verified" >&2
  exit 1
fi
packet_state=$(jq -c --arg recv "$packet_gno_recv_tx" --arg ack "$packet_evm_ack_tx" \
  --arg sender "$packet_sender_delta" --arg escrow "$packet_escrow_delta" \
  --arg recipient "$packet_recipient_delta" --arg failed "$packet_failed_final" \
  '.gno_receive_tx=$recv|.evm_ack_tx=$ack|.balance_deltas={sender:$sender,escrow:$escrow,recipient:$recipient}
   |.failed_work_final=($failed|tonumber)' <<<"$packet_state")
set_packet_phase packet-complete
write_packet_artifact
echo "EVM ERC20 to Gno packet verified; artifact: $artifact_dir/packet-summary.json"
