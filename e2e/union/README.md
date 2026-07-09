# Gno <> Union <> EVM Local E2E

This harness runs local Gno plus the Gno tx-indexer from this repo and reuses
Union's official local devnet for Union, EVM, beacon, and Postgres. The Union
side follows the official Union repo docs and E2E flow:

- `/Users/notjoon/union-voyager/networks/README.md`
- `/Users/notjoon/union-voyager/cosmwasm/cosmwasm.nix`
- `/Users/notjoon/union-voyager/e2e/e2e.nix`

The current Voyager config is for:

- Gno chain id: `dev`
- Union chain id: `union-devnet-1`
- EVM chain id: `32382`

## 0. Rebuild rule

Do not rebuild Voyager for RPC, queue, contract, or client creation failures.
Rebuild only when one of these is true:

- `e2e/union/voyager-build.Dockerfile` changed.
- `/Users/notjoon/union-voyager` source changed and the new binary is needed.
- A required binary is missing from `union-voyager-build:latest`.

Check the existing image first:

```sh
docker run --rm union-voyager-build:latest sh -lc \
  'test -x /output/voyager &&
   test -x /output/release/voyager-transaction-plugin-evm &&
   test -x /output/release/voyager-client-module-trusted-mpt &&
   test -x /output/release/voyager-proof-module-evm-mpt &&
   echo voyager-image-ok'
```

## 1. Start Union's official devnet

From `/Users/notjoon/union-voyager`:

```sh
NO_BLOCKSCOUT=true ./networks/run-linux-devnet.sh
```

Wait for these host ports:

- Union RPC: `http://127.0.0.1:26657`
- EVM RPC: `http://127.0.0.1:8545`
- Beacon API: `http://127.0.0.1:9596`
- Postgres: `127.0.0.1:5432`

## 2. Deploy Union CosmWasm contracts

Union's deploy package says the manager must be deployed before the full IBC
stack. On Linux, run:

```sh
cd /Users/notjoon/union-voyager
nix run .#cosmwasm-scripts.union-devnet.deploy-manager -- \
  --initial-admin union1jk9psyhvgkrt2cumz8eytll2244m2nnz4yt2g2 \
  --allow-dirty
nix run .#cosmwasm-scripts.union-devnet.deploy -- --allow-dirty
```

On macOS, if the Nix deploy fails because it builds for Darwin, run it inside a
Linux Nix container and proxy the container's localhost to the host Union RPC:

```sh
docker run --rm -it \
  -v /Users/notjoon/union-voyager:/work \
  -w /work \
  --add-host host.docker.internal:host-gateway \
  nixos/nix:latest \
  sh -lc 'nix --extra-experimental-features "nix-command flakes" shell nixpkgs#socat -c "
    socat TCP-LISTEN:26657,bind=127.0.0.1,fork,reuseaddr TCP:host.docker.internal:26657 &
    nix --extra-experimental-features \"nix-command flakes\" run .#cosmwasm-scripts.union-devnet.deploy-manager -- \
      --initial-admin union1jk9psyhvgkrt2cumz8eytll2244m2nnz4yt2g2 \
      --allow-dirty &&
    nix --extra-experimental-features \"nix-command flakes\" run .#cosmwasm-scripts.union-devnet.deploy -- --allow-dirty
  "'
```

The current local config expects these deployed addresses:

```json
{
  "core": "union1nk3nes4ef6vcjan5tz6stf9g8p08q2kgqysx6q5exxh89zakp0msq5z79t",
  "ucs03": "union1rfz3ytg6l60wxk5rxsk27jvn2907cyav04sz8kde3xhmmf9nplxqr8y05c"
}
```

Verify the core contract exists:

```sh
cd /Users/notjoon/union-voyager
nix run .#uniond -- query wasm contract \
  union1nk3nes4ef6vcjan5tz6stf9g8p08q2kgqysx6q5exxh89zakp0msq5z79t \
  --node http://127.0.0.1:26657
```

If that address does not exist after a fresh redeploy, update
`e2e/union/voyager-config.gno-union.jsonc` with the new deploy output before
starting Voyager.

## 3. Start Gno and the tx-indexer

From `/Users/notjoon/gno-ibc/e2e/union`:

```sh
docker compose up -d gno tx-indexer
docker compose --profile setup up gno-whitelist
```

Gno uses host port `16657` because Union uses `26657`. If the Gno image does
not exist yet or the Gno Dockerfile changed, build it once:

```sh
docker compose build gno
```

## 4. Build Voyager image, only when needed

If the rebuild rule in step 0 says a rebuild is required:

```sh
cd /Users/notjoon/gno-ibc/e2e/union
VOYAGER_CONFIG=/Users/notjoon/gno-ibc/e2e/union/voyager-config.gno-union.jsonc \
docker compose --profile voyager-build build voyager-build
```

The compose file intentionally builds with:

- context: `/Users/notjoon/union-voyager`
- Dockerfile: `/Users/notjoon/gno-ibc/e2e/union/voyager-build.Dockerfile`

This avoids accidentally building `/Users/notjoon/union-voyager/voyager-build.Dockerfile`.

## 5. Readiness check

Use explicit `127.0.0.1` host URLs. The sandbox can resolve `localhost` through
IPv6 first and produce false negatives.

```sh
cd /Users/notjoon/gno-ibc/e2e/union
GOWORK=off GOCACHE=/private/tmp/gno-ibc-go-cache \
GNO_RPC=http://127.0.0.1:16657 \
GNO_INDEXER=http://127.0.0.1:48546/graphql/query \
UNION_RPC=http://127.0.0.1:26657 \
EVM_RPC=http://127.0.0.1:8545 \
go test -v -run 'TestGnoReady|TestGnoIndexerReady|TestUnionReady|TestEVMReady'
```

`TestDevnetReadiness` also checks beacon
`/eth/v2/beacon/blocks/head`. Use it only after confirming the beacon API is
serving that endpoint:

```sh
curl -f http://127.0.0.1:9596/eth/v2/beacon/blocks/head
```

## 6. Start Voyager

```sh
cd /Users/notjoon/gno-ibc/e2e/union
VOYAGER_CONFIG=/Users/notjoon/gno-ibc/e2e/union/voyager-config.gno-union.jsonc \
docker compose --profile voyager up -d postgres voyager
docker compose logs -f voyager
```

Before enqueueing work, verify Voyager sees the EVM plugin:

```sh
docker exec union-voyager-1 \
  ./voyager -c /config/voyager-config.gno-union.jsonc \
  plugin info voyager-transaction-plugin-evm/32382
```

## 7. Seed indexes and clients

The Union official E2E seeds indexes first, then creates clients. For this
Gno + Union + EVM setup:

```sh
docker exec union-voyager-1 ./voyager -c /config/voyager-config.gno-union.jsonc \
  index union-devnet-1 -e
docker exec union-voyager-1 ./voyager -c /config/voyager-config.gno-union.jsonc \
  index dev -e
docker exec union-voyager-1 ./voyager -c /config/voyager-config.gno-union.jsonc \
  index 32382 -e

docker exec union-voyager-1 ./voyager -c /config/voyager-config.gno-union.jsonc \
  msg create-client --on union-devnet-1 --tracking dev \
  --ibc-interface ibc-cosmwasm --ibc-spec-id ibc-union --client-type gno -e
docker exec union-voyager-1 ./voyager -c /config/voyager-config.gno-union.jsonc \
  msg create-client --on dev --tracking union-devnet-1 \
  --ibc-interface ibc-gno --ibc-spec-id ibc-union --client-type cometbls -e
docker exec union-voyager-1 ./voyager -c /config/voyager-config.gno-union.jsonc \
  msg create-client --on union-devnet-1 --tracking 32382 \
  --ibc-interface ibc-cosmwasm --ibc-spec-id ibc-union --client-type trusted/evm/mpt -e
docker exec union-voyager-1 ./voyager -c /config/voyager-config.gno-union.jsonc \
  msg create-client --on 32382 --tracking union-devnet-1 \
  --ibc-interface ibc-solidity --ibc-spec-id ibc-union --client-type cometbls -e
```

Check queue state:

```sh
docker exec union-voyager-1 ./voyager -c /config/voyager-config.gno-union.jsonc queue stats
docker exec union-voyager-1 ./voyager -c /config/voyager-config.gno-union.jsonc queue query-failed
```

## Known issue: EVM transaction plugin lookup

The current run reached EVM-side Union cometbls client creation and then failed
inside Voyager's queue with:

```text
plugin `voyager-transaction-plugin-evm/32382` not found
```

Do not fix this by rebuilding the image. The image contains the EVM plugin and
startup logs show it is registered. The failed queue item is a direct
`Call::Plugin` for `voyager-transaction-plugin-evm/32382` generated after the
EVM transaction optimizer converts `SubmitTx` to `SubmitMulticall`.

Useful source paths in `/Users/notjoon/union-voyager`:

- `lib/voyager-core/src/lib.rs`: `Call::Plugin` queue handling.
- `lib/voyager-core/src/context.rs`: plugin lookup and `PluginNotFound`.
- `voyager/plugins/transaction/evm/src/main.rs`: EVM transaction plugin name
  and `SubmitTxHook`.
- `voyager/src/main.rs`: `msg create-client` builds `Call::SubmitTx`.

Requeueing the same failed direct plugin item is expected to fail again until
that Voyager runtime/context issue is fixed.

## 8. Packet tests

After clients and channels exist, export the channel and operand values, then
run:

```sh
RUN_PACKET_TESTS=1 \
GNO_PACKET_CHANNEL_ID=<channel-id> \
GNO_PACKET_OPERAND_HEX=<pre-encoded-token-order> \
GOWORK=off GOCACHE=/private/tmp/gno-ibc-go-cache \
go test -v -run Packet
```
