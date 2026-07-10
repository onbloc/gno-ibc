# Gno <> Union <> EVM Local E2E

This harness runs local Gno plus the Gno tx-indexer from this repo and reuses
Union's official local devnet for Union, EVM, beacon, and Postgres. Set
`UNION_VOYAGER_DIR` to your `union-voyager` checkout; examples below assume
that variable is set. The Union side follows the official Union repo docs and
E2E flow:

- `$UNION_VOYAGER_DIR/networks/README.md`
- `$UNION_VOYAGER_DIR/cosmwasm/cosmwasm.nix`
- `$UNION_VOYAGER_DIR/e2e/e2e.nix`

The current Voyager config is for:

- Gno chain id: `dev`
- Union chain id: `union-devnet-1`
- EVM chain id: `32382`

Compose has working defaults. To override them locally, copy `.env.example` to
`.env`; do not inject the whole example file into containers.

## 0. Rebuild rule

Do not rebuild Voyager for RPC, queue, contract, or client creation failures.
Rebuild only when one of these is true:

- `e2e/union/voyager-build.Dockerfile` changed.
- `$UNION_VOYAGER_DIR` source changed and the new binary is needed.
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

From `$UNION_VOYAGER_DIR`:

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
cd "$UNION_VOYAGER_DIR"
nix run .#cosmwasm-scripts.union-devnet.deploy-manager -- \
  --initial-admin union1jk9psyhvgkrt2cumz8eytll2244m2nnz4yt2g2 \
  --allow-dirty
nix run .#cosmwasm-scripts.union-devnet.deploy -- --allow-dirty
```

On macOS, if the Nix deploy fails because it builds for Darwin, run it inside a
Linux Nix container and proxy the container's localhost to the host Union RPC:

```sh
docker run --rm -it \
  -v "$UNION_VOYAGER_DIR":/work \
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
cd "$UNION_VOYAGER_DIR"
nix run .#uniond -- query wasm contract \
  union1nk3nes4ef6vcjan5tz6stf9g8p08q2kgqysx6q5exxh89zakp0msq5z79t \
  --node http://127.0.0.1:26657
```

If that address does not exist after a fresh redeploy, update
`e2e/union/voyager-config.gno-union.jsonc` with the new deploy output before
starting Voyager.

Whitelist the Voyager Union signer as a relayer. This is the official Union
deployer command for granting the `RELAYER` role. Do not pass `--allow-dirty`
after the package name; this subcommand treats it as an app argument and fails.

```sh
cd "$UNION_VOYAGER_DIR"
nix run .#cosmwasm-scripts.union-devnet.whitelist-relayers -- \
  union1jk9psyhvgkrt2cumz8eytll2244m2nnz4yt2g2
```

On macOS, run the same command inside the Linux Nix container used above, with
the `socat` RPC proxy already running.

## 3. Start Gno and the tx-indexer

From `e2e/union`:

```sh
docker compose up --no-build -d gno tx-indexer
docker compose --profile setup up --no-build gno-whitelist
```

Gno uses host port `16657` because Union uses `26657`. If the Gno image does
not exist yet or the Gno Dockerfile changed, build it once and rerun the
`--no-build` commands above:

```sh
docker compose build gno
```

After `gno-whitelist`, initialize the Gno Union realms. `gno-whitelist` grants
the Voyager Gno relayer role, but a fresh chain still needs the core/ZKGM
implementations activated and light clients registered:

```sh
docker exec union-gno-1 bash -lc 'set -euo pipefail
printf "%s\n\n" "${ADMIN_MNEMONIC:-${TEST_MNEMONIC}}" | gnokey add admin --recover --insecure-password-stdin --force >/dev/null
run_call() {
  printf "\n" | gnokey maketx call -gas-fee 1000000ugnot -gas-wanted 90000000 -broadcast -chainid dev -remote localhost:26657 -insecure-password-stdin "$@" admin
}
run_call -pkgpath gno.land/r/onbloc/ibc/union/access -func GrantRole -args 1 -args g1ntuwmgjxxymp232hs92wtnkcelkul9f3t388cj
run_call -pkgpath gno.land/r/onbloc/ibc/union/access -func GrantRole -args 1 -args g1kzk926hsc9wcqsgluckdk2vglr2ge9m3fyglpw
run_call -pkgpath gno.land/r/onbloc/ibc/union/core -func UpdateImpl -args gno.land/r/onbloc/ibc/union/core/v1
run_call -pkgpath gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm -func UpdateImpl -args gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1
run_call -pkgpath gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm -func RegisterCoreApp
run_call -pkgpath gno.land/r/onbloc/ibc/union/lightclients/cometbls -func RegisterClient
run_call -pkgpath gno.land/r/onbloc/ibc/union/lightclients/statelensics23mpt -func RegisterClient
'
```

## 4. Build Voyager image, only when needed

If the rebuild rule in step 0 says a rebuild is required:

```sh
cd e2e/union
docker compose --profile voyager-build build voyager-build
```

The compose file intentionally builds with:

- Voyager source context: `${UNION_VOYAGER_DIR:-../../../union-voyager}`
- Dockerfile: `e2e/union/voyager-build.Dockerfile`

This avoids accidentally building `$UNION_VOYAGER_DIR/voyager-build.Dockerfile`.

## 5. Readiness check

Use explicit `127.0.0.1` host URLs. The sandbox can resolve `localhost` through
IPv6 first and produce false negatives.

```sh
cd e2e/union
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
cd e2e/union
docker compose --profile voyager up --no-build -d postgres voyager
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

Verify the Gno <> Union clients:

```sh
docker exec union-voyager-1 ./voyager -c /config/voyager-config.gno-union.jsonc \
  rpc client-info union-devnet-1 1
docker exec union-voyager-1 ./voyager -c /config/voyager-config.gno-union.jsonc \
  rpc client-info dev 1
docker exec union-gno-1 gnokey query vm/qeval -remote localhost:26657 \
  -data 'gno.land/r/onbloc/ibc/union/core.GetClientType(1)'
```

Expected client-info:

```text
{"client_type":"gno","ibc_interface":"ibc-cosmwasm"}
{"client_type":"cometbls","ibc_interface":"ibc-gno"}
```

The CosmWasm event source must keep `"index_trivial_events": true` in
`voyager-config.gno-union.jsonc`; otherwise Union `wasm-create_client` is
parsed but skipped as a trivial event. If the Union client exists on-chain but
the `done` table has no `chain_id: union-devnet-1` `create_client` event, reindex
the create-client block directly:

```sh
docker exec union-voyager-1 ./voyager -c /config/voyager-config.gno-union.jsonc \
  queue enqueue '{"@type":"call","@value":{"@type":"plugin","@value":{"plugin":"voyager-event-source-plugin-cosmwasm/union-devnet-1","message":{"@type":"fetch_block","@value":{"height":"1-550"}}}}}'
```

Then check DB reflection:

```sh
docker exec union-postgres-1 psql -U postgres -d postgres -c \
  "select id, created_at, item::text from done where item::text like '%\"chain_id\": \"union-devnet-1\"%' and item::text like '%create_client%' order by id desc limit 5;"
```

## 8. Connection and channel handshake

Union <> Gno connection proofs require Galois. Do not use the local Docker
prover unless Docker has enough memory for proof generation; a 7.65 GiB Docker
VM was confirmed to OOM-kill `galoisd` with exit code `137` after receiving a
proof request.

The local config should use the external prover:

```json
"prover_endpoints": ["https://galois.union.build:443"]
```

Check it from the host before waiting on Voyager retries:

```sh
curl -I --max-time 10 https://galois.union.build:443
```

An HTTP `415` with `content-type: application/grpc` is enough; it means the
gRPC server is reachable and rejected the non-gRPC curl request. If the config
was changed, restart Voyager without rebuilding:

```sh
cd e2e/union
docker compose --profile voyager up -d --force-recreate --no-build voyager
```

After `connection_open_init` is enqueued, verify the CometBLS proof work
cleared and the Gno connection exists:

```sh
docker exec union-postgres-1 psql -U postgres -d postgres -c \
  "select id, attempt, handle_at from queue where item::text like '%fetch_prove_request%' order by id desc limit 3;"
docker exec union-voyager-1 ./voyager -c /config/voyager-config.gno-union.jsonc queue query-failed
docker exec union-gno-1 gnokey query vm/qeval -remote localhost:26657 \
  -data 'gno.land/r/onbloc/ibc/union/core.QueryConnection(1)'
```

Expected state before PacketSend:

- No `fetch_prove_request` rows left for the connection proof.
- `queue query-failed` returns `[]`.
- `QueryConnection(1)` returns a non-empty string.
- `QueryChannel(1)` must also be non-empty before PacketSend tests.

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

Useful source paths in `$UNION_VOYAGER_DIR`:

- `lib/voyager-core/src/lib.rs`: `Call::Plugin` queue handling.
- `lib/voyager-core/src/context.rs`: plugin lookup and `PluginNotFound`.
- `voyager/plugins/transaction/evm/src/main.rs`: EVM transaction plugin name
  and `SubmitTxHook`.
- `voyager/src/main.rs`: `msg create-client` builds `Call::SubmitTx`.

Requeueing the same failed direct plugin item is expected to fail again until
that Voyager runtime/context issue is fixed.

## 9. Packet tests

After clients and channels exist, export the channel and operand values, then
run:

```sh
RUN_PACKET_TESTS=1 \
GNO_PACKET_CHANNEL_ID=<channel-id> \
GNO_PACKET_OPERAND_HEX=<pre-encoded-token-order> \
GOWORK=off GOCACHE=/private/tmp/gno-ibc-go-cache \
go test -v -run Packet
```

## 10. PacketSend watcher

Use the watcher to observe Gno `PacketSend` events from the tx-indexer while
Voyager is running. It does not submit acknowledgements or enqueue queue work.

```sh
cd e2e/union
GOWORK=off GOCACHE=/private/tmp/gno-ibc-go-cache go run ./cmd/packet-watch \
  --indexer http://127.0.0.1:48546/graphql/query \
  --source-channel <channel-id>
```

For a one-shot check:

```sh
GOWORK=off GOCACHE=/private/tmp/gno-ibc-go-cache go run ./cmd/packet-watch --once --source-channel 1
```
