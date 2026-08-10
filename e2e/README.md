# Union E2E

This suite starts Voyager against disposable Gno, Union, and EVM devnets and
runs the scenarios listed by `e2e.py`. The
[`Gno Union EVM full cycle`](../../.github/workflows/gno-union-evm-full-cycle.yml)
workflow is the executable reference for a complete setup.

Never use the fixture keys in `config/devnet.json` on a persistent or externally
reachable network.

## Requirements

- Docker
- Nix
- Foundry
- Go 1.26.x
- A clean `union-voyager` checkout at the revision pinned in `config/devnet.json`

Validate the configuration before starting:

```sh
python3 e2e/provision.py validate
```

## Start a Fresh Environment

Use unique Docker project and artifact names. From the repository root:

```sh
set -a
source <(python3 e2e/provision.py export-env)
set +a

export UNION_VOYAGER_DIR=../union-voyager
export UNION_PROJECT=gno-union-e2e-local
export GNO_PROJECT=gno-union-e2e-gno-local
export E2E_DEPLOYMENT_DIR=$PWD/e2e/artifacts/deployment
export E2E_ARTIFACT_DIR=$PWD/e2e/artifacts
export E2E_CONFIG_FILE=$PWD/e2e/runner.json
```

Resolve the images. Authenticate to GHCR first when using private packages.
The resolver builds locally when an image is unavailable.

```sh
export E2E_REGISTRY=ghcr.io
export E2E_IMAGE_NAMESPACE=onbloc

GNO_IMAGE=$(.github/scripts/ensure-image.sh gno)
VOYAGER_IMAGE=$(.github/scripts/ensure-image.sh voyager)
UNION_DEPLOYER_IMAGE=$(.github/scripts/ensure-image.sh union-deployer)
export GNO_IMAGE VOYAGER_IMAGE UNION_DEPLOYER_IMAGE
```

Start the Union/EVM devnet and provision its contracts:

```sh
cd "$UNION_VOYAGER_DIR"
DEVNET_PROJECT_NAME="$UNION_PROJECT" NO_BLOCKSCOUT=true \
  ./networks/run-linux-devnet.sh
cd -

python3 e2e/provision.py deploy-union
set -a
source <(python3 e2e/provision.py configure-evm)
set +a
```

Start and bootstrap Gno, deploy the test token, and write `runner.json`:

```sh
docker compose -f e2e/gno/compose.yml \
  -p "$GNO_PROJECT" up -d --wait
docker compose -f e2e/gno/compose.yml \
  -p "$GNO_PROJECT" --profile setup run --rm setup

set -a
source <(python3 e2e/provision.py deploy-test-token)
set +a
python3 e2e/provision.py write-runner-config
```

`runner.json` contains private fixture keys and is created with mode `0600`.
Contract addresses are discovered from the current deployment; do not copy
addresses from a previous run.

## Run Scenarios

```sh
cd e2e
python3 e2e.py list
python3 e2e.py run
```

Pass scenario names to run a subset. `amount-boundaries` and `gno-to-evm`
automatically include their `erc20-to-gno` prerequisite.

```sh
python3 e2e.py run forged-proof-rejection amount-boundaries gno-to-evm
```

The timeout-refund scenarios pause a destination app and require a fresh,
unpaused environment. Relayer failover scenarios also require a fresh EVM
chain.

## Resume and Cleanup

Keep `runner.json`, `state.json`, the artifact directory, and the Voyager
database from the same run when adding scenarios to an existing topology:

```sh
python3 e2e.py run --resume <scenario>
```

Do not resume after a failed write scenario or after changing realms, genesis,
deployment addresses, or topology. Start a fresh environment instead.

To remove the disposable environment:

```sh
docker compose -f e2e/gno/compose.yml \
  -p "$GNO_PROJECT" down -v --remove-orphans

cd "$UNION_VOYAGER_DIR"
DEVNET_ACTION=down DEVNET_PROJECT_NAME="$UNION_PROJECT" NO_BLOCKSCOUT=true \
  ./networks/run-linux-devnet.sh
```
