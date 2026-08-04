# Union E2E

This runner manages Voyager and the IBC topology, but it does **not** deploy the chains, PostgreSQL, or smart contracts itself. For a completely fresh execution, prepare the external environment first in the following order.

The `Gno Union EVM full cycle` workflow performs that preparation on its
GitHub-hosted runner. It waits for the reusable image workflow, starts the
pinned Union/EVM devnet and PostgreSQL, deploys the Union stack from the
upstream direct-E2E deployment revision, starts Gno and its indexer, and
derives every contract address from deployment output or an on-chain registry.
Only private signing keys remain repository secrets; RPC endpoints and public
deployment values are created for each workflow run.

## Fresh Environment Setup

You need Docker, Nix, Foundry, `jq`, Go 1.26.x, and a clean checkout of `union-voyager` at the revision pinned in `.env.example`.

## Prebuilt Images

The scenario runner consumes a prebuilt Voyager image, and the Gno Compose
project consumes a prebuilt Gno image. Authenticate Docker to GHCR, then use
the same resolver locally and in CI:

```sh
export CR_PAT=<GitHub token with package access>
printf '%s' "$CR_PAT" | docker login ghcr.io -u <github-user> --password-stdin

export E2E_REGISTRY=ghcr.io
export E2E_IMAGE_NAMESPACE=onbloc
export E2E_IMAGE_TAG=$(git rev-parse HEAD)
export UNION_VOYAGER_DIR=../union-voyager
export UNION_VOYAGER_REVISION=82c70ec1ff84ec457e976ad94f38a5d5783b7836

GNO_IMAGE=$(e2e/union/ensure-image.sh gno)
VOYAGER_IMAGE=$(e2e/union/ensure-image.sh voyager)
export GNO_IMAGE VOYAGER_IMAGE
```

The resolver checks GHCR first, then the local Docker store, and builds only
when neither contains the immutable tag. Pass `--push` instead of the default
`--load` to publish a missing image and its BuildKit registry cache.

### 1. Isolate from Existing Environments

Use a new Docker project name for both Union/EVM and Gno. Do not reuse existing Docker volumes, `state.json`, or the artifact directory. Only run the following commands if you intend to actually tear down the existing environment.

```sh
cd "$UNION_VOYAGER_DIR"
DEVNET_ACTION=down \
DEVNET_PROJECT_NAME=<union-project> \
NO_BLOCKSCOUT=true \
./networks/run-linux-devnet.sh

docker compose -f e2e/union/gno-compose.yml \
  -p <gno-project> down -v --remove-orphans
```

### 2. Union and EVM

Run the `full-dev-setup` in `union-voyager` with the new project name. On macOS, use the Linux Nix wrapper.

```sh
cd "$UNION_VOYAGER_DIR"
git status --short
git rev-parse HEAD

DEVNET_PROJECT_NAME=<union-project> \
NO_BLOCKSCOUT=true \
./networks/run-linux-devnet.sh
```

`git status --short` must be empty, and the revision must match `UNION_VOYAGER_REVISION` in `.env.example`.

Wait until the Union RPC (`:26657`), EVM RPC (`:8545`), and beacon RPC (`:9596`) are all available. From the devnet deployment output, record the following values:

* Union IBC host
* EVM IBC handler, ZKGM, and Multicall
* EVM `cometbls` and `proof-lens` client implementations

Verify the two EVM implementations through the handler registry.

```sh
cast call <evm-handler> \
  'clientRegistry(string)(address)' cometbls \
  --rpc-url http://127.0.0.1:8545
cast call <evm-handler> \
  'clientRegistry(string)(address)' proof-lens \
  --rpc-url http://127.0.0.1:8545
```

Union must have the `trusted/evm/mpt` light client registered. If its address is empty, or if the EVM registry returns the zero address, do **not** start the runner. Instead, deploy and register it first using the deployment commands for the pinned `union-voyager` revision.

### 3. Gno and the Database

Resolve the Gno image for the current checkout and start the following services with fresh Docker volumes:

* `gnodev local -chain-id dev.ibc`
* Gno tx-indexer
* PostgreSQL for Voyager

Deploy the following realms to Gno, then invoke `gno.land/r/onbloc/ibc/union/testing/e2e_setup.Bootstrap` exactly once.

```text
gno.land/r/onbloc/ibc/union/access
gno.land/r/onbloc/ibc/union/core
gno.land/r/onbloc/ibc/union/core/v1
gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm
gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1
gno.land/r/onbloc/ibc/union/testing/e2e_setup
```

The included Compose project starts the prebuilt Gno image and transaction
indexer. Run its setup profile exactly once
for each fresh project to grant the required roles and invoke `Bootstrap`.

```sh
docker compose -f e2e/union/gno-compose.yml \
  -p <gno-project> up -d --wait

docker compose -f e2e/union/gno-compose.yml \
  -p <gno-project> --profile setup run --rm setup
```

Verify that the Gno RPC, tx-indexer GraphQL endpoint, and PostgreSQL are all reachable.

Since Voyager runs inside Docker, use `host.docker.internal:<port>` for host endpoints. Packet command endpoints may instead use `127.0.0.1:<port>` on the host.

### 4. Configure the Runner

```sh
cd e2e/union
install -m 600 .env.example .env
```

Populate `.env` with the chain IDs, endpoints, contract addresses, private keys, and PostgreSQL URL obtained above. Do not copy IDs or addresses from previous runs.

When running ERC20 scenarios, deploy `fixtures/TestERC20.sol` to the new EVM deployment and set its address in `EVM_TEST_ERC20`.

An example configuration using both Docker-internal and host endpoints is shown below.

```sh
UNION_RPC_URL=http://host.docker.internal:26657
EVM_RPC_URL=http://host.docker.internal:8545
GNO_RPC_URL=http://host.docker.internal:16657
GNO_TX_INDEXER_RPC_URL=http://host.docker.internal:48546/graphql/query
VOYAGER_DATABASE_URL=postgresql://<user>:<password>@host.docker.internal:<port>/<database>

UNION_PACKET_RPC_URL=http://127.0.0.1:26657
EVM_PACKET_RPC_URL=http://127.0.0.1:8545
GNO_PACKET_RPC_URL=http://127.0.0.1:16657
GNO_PACKET_INDEXER_RPC_URL=http://127.0.0.1:48546/graphql/query

E2E_ARTIFACT_DIR=./channel-e2e-artifacts-<run-id>
E2E_STATE_FILE=./channel-e2e-artifacts-<run-id>/state.json
```

### 5. Run the Scenarios

First, execute the read-only preflight. For a fresh environment, run the complete scenario suite **without** `--resume`.

```sh
./run-channel-e2e.sh
./run-channel-e2e.sh --apply \
  --forged-proof-rejection \
  --erc20-to-gno \
  --amount-boundaries \
  --gno-to-evm
```

After a successful run, inspect `summary.json` and the evidence generated for each scenario. Once the runner exits, no Voyager containers with the label `io.onbloc.gno-ibc.e2e.run` should remain.

To execute additional scenarios while keeping the same chains and deployment, preserve the existing `state.json` and `.env`, then specify only the new scenario flags.

```sh
./run-channel-e2e.sh --resume --apply --<new-scenario>
```

If the Gno realms, genesis, deployment addresses, or topology change, do **not** use `--resume`. Instead, create a new environment following the procedure above.

## Troubleshooting

* **`valid membership proof was rejected`**: The latest finalized EVM height may not yet have been stored in the Gno `gno_evm` client. The forged-proof runner enqueues a client update, waits until the stored consensus height reaches the target, and then generates the proof using the actual stored height.
* **`saved repaired failed-work ID is ahead of Voyager queue`**: The `state.json` file and the Voyager PostgreSQL database were created by different runs. Use the artifact directory and database endpoint from the same run, and never manually modify IDs in the state file.
* **`client type not found`** or **`IBC_UNION_ERR_ACCESS_MANAGED`**: Either the required Union light client has not been registered on the fresh chain, or the Voyager relayer has not been added to the allowlist. Complete the deployment and whitelist steps for the pinned `union-voyager` revision before restarting the runner.
* If the EVM handler registry returns the zero address, the `cometbls` or `proof-lens` implementation has not been deployed. Do not run any scenarios until all registry preflight checks return non-zero addresses.
