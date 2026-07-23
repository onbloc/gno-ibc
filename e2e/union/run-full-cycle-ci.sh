#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=$(cd "$script_dir/../.." && pwd -P)
union_repo=${UNION_VOYAGER_DIR:-"$repo_root/../union-voyager"}
run_id=${GITHUB_RUN_ID:-local-$$}
attempt=${GITHUB_RUN_ATTEMPT:-1}
project_base="gno-union-e2e-${run_id}-${attempt}"
project_base=${project_base//_/-}
compose_project="${project_base}-gno"
union_project="${project_base}-union"
artifacts=${E2E_ARTIFACT_DIR:-"$repo_root/.e2e-artifacts/$project_base"}
runtime_dir=$(mktemp -d "${TMPDIR:-/tmp}/gno-union-e2e.XXXXXX")
union_started=0
compose_started=0

mkdir -p "$artifacts"
exec > >(tee "$artifacts/run.log") 2>&1

for command in cargo cast curl docker forge git go jq make openssl rsync; do
  command -v "$command" >/dev/null || { echo "missing required command: $command" >&2; exit 2; }
done
docker compose version >/dev/null

: "${EVM_CHAIN_ID:?set EVM_CHAIN_ID from the confirmed deployment}"
[[ $EVM_CHAIN_ID =~ ^[1-9][0-9]*$ ]] || { echo "EVM_CHAIN_ID must be a positive decimal integer" >&2; exit 2; }
for name in EVM_IBC_HANDLER EVM_MULTICALL EVM_ZKGM_CONTRACT EVM_ERC20_IMPL EVM_MANAGER EVM_RECIPIENT EVM_DEPLOYER; do
  [[ ${!name:-} =~ ^0x[0-9a-fA-F]{40}$ ]] || { echo "$name must be a confirmed 20-byte hex address" >&2; exit 2; }
done

make -C "$repo_root" vendor

default_test_mnemonic=$(sed -n 's/^TEST_MNEMONIC=//p' "$script_dir/.env.example")
[[ -n $default_test_mnemonic ]] || { echo "TEST_MNEMONIC is missing from .env.example" >&2; exit 2; }
export TEST_MNEMONIC=${TEST_MNEMONIC:-$default_test_mnemonic}
export ADMIN_MNEMONIC=${ADMIN_MNEMONIC:-$TEST_MNEMONIC}

compose() {
  docker compose --project-name "$compose_project" \
    --project-directory "$script_dir" --file "$script_dir/docker-compose.yml" \
    --env-file "$repo_root/.gno-version" --env-file "$script_dir/.env.example" "$@"
}

diagnostics() {
  set +e
  docker ps -a --filter "label=com.docker.compose.project=$compose_project" >"$artifacts/gno-containers.txt" 2>&1
  docker ps -a --filter "label=com.docker.compose.project=$union_project" >"$artifacts/union-containers.txt" 2>&1
  compose logs --no-color >"$artifacts/gno-compose.log" 2>&1
  while IFS= read -r container; do
    [[ -n $container ]] || continue
    docker logs "$container" >"$artifacts/$container.log" 2>&1
  done < <(docker ps -a --filter "label=com.docker.compose.project=$union_project" --format '{{.Names}}')
  if [[ -n ${VOYAGER_CONTAINER:-} ]]; then
    docker inspect --format '{{json .State}}' "$VOYAGER_CONTAINER" >"$artifacts/voyager-state.json" 2>&1
    docker logs "$VOYAGER_CONTAINER" >"$artifacts/voyager.log" 2>&1
    docker exec "$VOYAGER_CONTAINER" ./voyager -c /config/voyager-config.gno-union.jsonc queue stats \
      >"$artifacts/voyager-queue-stats.txt" 2>&1
    docker exec "$VOYAGER_CONTAINER" ./voyager -c /config/voyager-config.gno-union.jsonc queue query-failed \
      >"$artifacts/voyager-failed.txt" 2>&1
  fi
  if [[ -n ${POSTGRES_CONTAINER:-} ]]; then
    docker exec "$POSTGRES_CONTAINER" psql -U postgres -d postgres -At -c \
      "select id, attempt, handle_at - now(), left(item::text, 2000) from queue order by id limit 100" \
      >"$artifacts/voyager-queue.txt" 2>&1
  fi
  set -e
}

cleanup() {
  status=$?
  trap - EXIT INT TERM
  diagnostics
  if ((compose_started)); then
    compose --profile setup --profile voyager down -v --remove-orphans >/dev/null 2>&1 || true
  fi
  if ((union_started)); then
    DEVNET_PROJECT_NAME="$union_project" DEVNET_ACTION=down NO_BLOCKSCOUT=true \
      "$union_repo/networks/run-linux-devnet.sh" >/dev/null 2>&1 || true
  fi
  rm -f "$runtime_dir/voyager-config.jsonc" "$runtime_dir/clients.env" \
    "$runtime_dir/gno-evm.env"
  rmdir "$runtime_dir" 2>/dev/null || true
  exit "$status"
}
trap cleanup EXIT INT TERM

wait_http() {
  local label=$1 url=$2 deadline=$((SECONDS + 300))
  until curl --fail --silent --show-error "$url" >/dev/null 2>&1; do
    ((SECONDS < deadline)) || { echo "$label did not become ready: $url" >&2; return 1; }
    sleep 2
  done
}

wait_post() {
  local label=$1 url=$2 body=$3 deadline=$((SECONDS + 300))
  until curl --fail --silent --show-error -H 'content-type: application/json' -d "$body" "$url" >/dev/null 2>&1; do
    ((SECONDS < deadline)) || { echo "$label did not become ready: $url" >&2; return 1; }
    sleep 2
  done
}

wait_tcp() {
  local label=$1 host=$2 port=$3 deadline=$((SECONDS + 300))
  until (exec 3<>"/dev/tcp/$host/$port") 2>/dev/null; do
    ((SECONDS < deadline)) || { echo "$label did not open $host:$port" >&2; return 1; }
    sleep 2
  done
}

export COMPOSE_PROJECT_NAME="$compose_project"
export UNION_VOYAGER_DIR="$union_repo"
export VOYAGER_CONFIG="$runtime_dir/voyager-config.jsonc"
export NO_BLOCKSCOUT=true

expected_union_commit=$(sed -n 's/^UNION_COMMIT=//p' "$script_dir/.env.example")
actual_union_commit=$(git -C "$union_repo" rev-parse HEAD)
[[ $actual_union_commit == "$expected_union_commit" ]] || {
  echo "Union checkout is $actual_union_commit, want $expected_union_commit" >&2
  exit 1
}
[[ -z $(git -C "$union_repo" status --porcelain) ]] || {
  echo "Union checkout must be clean" >&2
  exit 1
}

echo "starting isolated Union/EVM devnet $union_project"
union_started=1
DEVNET_PROJECT_NAME="$union_project" DEVNET_ACTION=up "$union_repo/networks/run-linux-devnet.sh"
wait_http Union http://localhost:26657/status
wait_post EVM http://localhost:8545 '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}'
wait_http Beacon http://localhost:9596/eth/v1/beacon/headers/head

UNION_CONTAINER=$(docker ps --filter "label=com.docker.compose.project=$union_project" \
  --filter publish=26657 --format '{{.Names}}' | head -n 1)
[[ -n $UNION_CONTAINER ]] || { echo "could not discover isolated Union container" >&2; exit 1; }
EVM_CONTAINER=$(docker ps --filter "label=com.docker.compose.project=$union_project" \
  --filter publish=8545 --format '{{.Names}}' | head -n 1)
[[ -n $EVM_CONTAINER ]] || { echo "could not discover isolated EVM container" >&2; exit 1; }
export UNION_CONTAINER EVM_CONTAINER

if [[ -z ${TRUSTED_MPT_PRIVATE_KEY:-} ]]; then
  TRUSTED_MPT_PRIVATE_KEY="0x$(openssl rand -hex 32)"
  export TRUSTED_MPT_PRIVATE_KEY
fi
if [[ -z ${EVM_PRIVATE_KEY:-} ]]; then
  evm_raw_key=$(tr -d '[:space:]' <"$union_repo/networks/genesis/devnet-eth/dev-key0.prv")
  EVM_PRIVATE_KEY="0x${evm_raw_key#0x}"
  export EVM_PRIVATE_KEY
fi

echo "deploying pinned Union contracts"
"$union_repo/networks/run-linux-nix.sh" cosmwasm-scripts.union-devnet.deploy-manager \
  --initial-admin union1jk9psyhvgkrt2cumz8eytll2244m2nnz4yt2g2 --allow-dirty
"$union_repo/networks/run-linux-nix.sh" cosmwasm-scripts.union-devnet.deploy --allow-dirty
"$union_repo/networks/run-linux-nix.sh" cosmwasm-scripts.union-devnet.whitelist-relayers \
  union1jk9psyhvgkrt2cumz8eytll2244m2nnz4yt2g2

export UNION_CORE_CONTRACT=${UNION_CORE_CONTRACT:-union1nk3nes4ef6vcjan5tz6stf9g8p08q2kgqysx6q5exxh89zakp0msq5z79t}
export UNION_MANAGER_CONTRACT=${UNION_MANAGER_CONTRACT:-union1g8eayx25kmzmywzwq4uw44ftfpqxfz6qplnyutwqdzn92reavtmqltyh3e}
export UNION_ZKGM_CONTRACT=${UNION_ZKGM_CONTRACT:-union1rfz3ytg6l60wxk5rxsk27jvn2907cyav04sz8kde3xhmmf9nplxqr8y05c}
proof_lens_impl=$(cast call "$EVM_IBC_HANDLER" 'clientRegistry(string)(address)' proof-lens --rpc-url http://localhost:8545)
if [[ $proof_lens_impl == 0x0000000000000000000000000000000000000000 ]]; then
  echo "registering the pinned EVM Proof Lens implementation"
  "$union_repo/networks/run-linux-nix.sh" evm-scripts.devnet.script-register-clients \
    --deployer_pk "$EVM_DEPLOYER" \
    --sender_pk "$EVM_RECIPIENT"
  proof_lens_impl=$(cast call "$EVM_IBC_HANDLER" 'clientRegistry(string)(address)' proof-lens --rpc-url http://localhost:8545)
fi
[[ $proof_lens_impl != 0x0000000000000000000000000000000000000000 ]] || {
  echo "EVM proof-lens registry is empty after registration" >&2
  exit 1
}
[[ $(cast code "$proof_lens_impl" --rpc-url http://localhost:8545) != 0x ]] || {
  echo "EVM proof-lens registry address $proof_lens_impl has no code" >&2
  exit 1
}
export EVM_PROOF_LENS_IMPL=$proof_lens_impl

echo "building and verifying the pinned trusted-MPT artifact"
(
  cd "$union_repo"
  RUSTFLAGS='-C link-arg=-s -C target-cpu=mvp -C passes=adce,loop-deletion -Zlocation-detail=none' \
    cargo +nightly-2025-12-05 build -Z build-std=std,panic_abort --profile wasm-release \
      --target wasm32-unknown-unknown --no-default-features --lib -p trusted-mpt-light-client
)
UNION_SIGNER_HOME=home "$script_dir/setup-union-evm.sh"

echo "building and starting the isolated Gno/Voyager stack $compose_project"
voyager_image="union-voyager-build:$expected_union_commit"
if [[ -z ${REBUILD_VOYAGER:-} ]] && docker image inspect "$voyager_image" >/dev/null 2>&1; then
  echo "reusing cached Voyager image $voyager_image"
  compose --profile voyager build gno
else
  echo "building Voyager image $voyager_image"
  compose --profile voyager build gno voyager
fi
if [[ -z ${UNION_PRIVATE_KEY:-} ]]; then
  union_mnemonic=$(sed -n 's/^[[:space:]]*alice = "\(.*\)";/\1/p' \
    "$union_repo/networks/mkCosmosDevnet.nix")
  [[ -n $union_mnemonic ]] || { echo "could not discover the pinned Union devnet mnemonic" >&2; exit 2; }
  UNION_PRIVATE_KEY=$(printf '%s\n' "$union_mnemonic" | \
    compose run --rm --no-deps -T --entrypoint mnemonic-raw-key gno)
  export UNION_PRIVATE_KEY
fi
if [[ -z ${GNO_PRIVATE_KEY:-} ]]; then
  GNO_PRIVATE_KEY=$(printf '%s\n' "$TEST_MNEMONIC" | \
    compose run --rm --no-deps -T --entrypoint mnemonic-raw-key gno)
  export GNO_PRIVATE_KEY
fi
for name in TRUSTED_MPT_PRIVATE_KEY UNION_PRIVATE_KEY EVM_PRIVATE_KEY GNO_PRIVATE_KEY; do
  [[ ${!name} =~ ^0x[0-9a-fA-F]{64}$ ]] || { echo "could not derive a valid $name" >&2; exit 2; }
done
if [[ -n ${GITHUB_ACTIONS:-} ]]; then
  for name in TEST_MNEMONIC ADMIN_MNEMONIC TRUSTED_MPT_PRIVATE_KEY UNION_PRIVATE_KEY EVM_PRIVATE_KEY GNO_PRIVATE_KEY; do
    printf '::add-mask::%s\n' "${!name}"
  done
fi
VOYAGER_CONFIG_OUTPUT="$VOYAGER_CONFIG" "$script_dir/render-voyager-config.sh"
compose_started=1
compose --profile voyager up -d gno tx-indexer postgres
if [[ -z ${REBUILD_VOYAGER:-} ]] && docker image inspect "$voyager_image" >/dev/null 2>&1; then
  compose --profile voyager create --no-build voyager
else
  compose --profile voyager create voyager
fi
VOYAGER_CONTAINER=$(compose ps -q --all voyager)
docker network connect "$union_project" "$VOYAGER_CONTAINER"
export UNION_RPC_INTERNAL="http://$UNION_CONTAINER:26657"
export EVM_RPC_INTERNAL="http://$EVM_CONTAINER:8545"
VOYAGER_CONFIG_OUTPUT="$VOYAGER_CONFIG" "$script_dir/render-voyager-config.sh"
compose --profile voyager start voyager
wait_http Gno http://localhost:16657/status
wait_post Gno-indexer http://localhost:48546/graphql/query '{"query":"{ latestBlockHeight }"}'
wait_tcp Voyager localhost 7177

GNO_CONTAINER=$(compose ps -q gno)
POSTGRES_CONTAINER=$(compose ps -q postgres)
export GNO_CONTAINER VOYAGER_CONTAINER POSTGRES_CONTAINER

compose --profile setup run --rm gno-whitelist
compose --profile setup run --rm gno-bootstrap

export CLIENTS_ENV_FILE="$runtime_dir/clients.env"
"$script_dir/setup-clients.sh"
set -a
# shellcheck disable=SC1090
source "$CLIENTS_ENV_FILE"
set +a

# Continuous indexing is the only relay trigger for handshakes and packets.
for chain in "${GNO_CHAIN_ID:-dev}" "${UNION_CHAIN_ID:-union-devnet-1}" "$EVM_CHAIN_ID"; do
  docker exec "$VOYAGER_CONTAINER" ./voyager -c /config/voyager-config.gno-union.jsonc \
    index "$chain" --enqueue >/dev/null
done
export VOYAGER_INDEX_STARTED=1

export TOPOLOGY_ENV_FILE="$runtime_dir/gno-evm.env"
"$script_dir/setup-gno-evm-topology.sh"
set -a
# shellcheck disable=SC1090
source "$TOPOLOGY_ENV_FILE"
set +a

GNO_SENDER_ADDR=$(docker exec "$GNO_CONTAINER" gnokey list 2>&1 | \
  awk '/sender/ && match($0, /addr: [^ ]+/) { print substr($0, RSTART + 6, RLENGTH - 6); exit }')
[[ -n $GNO_SENDER_ADDR ]] || { echo "could not discover Gno sender address" >&2; exit 1; }
export GNO_SENDER_ADDR

export GNO_COMPOSE_DIR="$script_dir"
export GNO_RPC=http://localhost:16657
export GNO_INDEXER=http://localhost:48546/graphql/query
export UNION_RPC=http://localhost:26657
export EVM_RPC=http://localhost:8545
export BEACON_API=http://localhost:9596
export VOYAGER_CONFIG_PATH=/config/voyager-config.gno-union.jsonc
export RUN_PACKET_TESTS=1

go_test=(go test -count=1 -v .)
(
  cd "$script_dir"
  GOWORK=off "${go_test[@]}" -run '^(TestDevnetReadiness|TestGnoEVMDirectTopology)$'
  GOWORK=off "${go_test[@]}" -run '^TestGnoNativeToEVMProofLens$'
  GOWORK=off "${go_test[@]}" -run '^TestEVMERC20ToGnoStateLens$'
  GOWORK=off "${go_test[@]}" -run '^TestTokenOrderInitializeEscrowUnescrowLifecycle$'
  GOWORK=off "${go_test[@]}" -run '^TestNoForceEvents$'
)

failed_count=$(docker exec "$POSTGRES_CONTAINER" psql -U postgres -d postgres -At -c 'select count(*) from failed')
[[ $failed_count == 0 ]] || {
  echo "Voyager recorded $failed_count failed rows during the full-cycle run" >&2
  docker exec "$VOYAGER_CONTAINER" ./voyager -c /config/voyager-config.gno-union.jsonc queue query-failed >&2
  exit 1
}

echo "direct Gno-EVM Proof Lens and State Lens packets passed"
