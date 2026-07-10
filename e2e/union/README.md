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

For the CI-style Gno -> Union packet relay path, start from clean local
volumes and run the focused test with the validated local ids:

```sh
docker compose -f e2e/union/docker-compose.yml down -v --remove-orphans

RUN_PACKET_TESTS=1 \
GNO_PACKET_CONNECTION_ID=5 \
GNO_PACKET_CHANNEL_ID=3 \
UNION_PACKET_CONNECTION_ID=3 \
UNION_PACKET_CHANNEL_ID=2 \
UNION_GNO_CLIENT_ID=4 \
GNO_PACKET_OPERAND_HEX=<pre-encoded-token-order> \
GNO_PACKET_SEND_COINS=1ugnot \
GNO_COMPOSE_DIR=e2e/union \
GOWORK=off GOCACHE=/private/tmp/gno-ibc-go-cache \
go test -v ./e2e/union -run TestGnoToUnionPacketRelay
```

`TestGnoToUnionPacketRelay` broadcasts `SendRaw`, waits for `PacketSend`, and
deterministically enqueues the matching Gno and Union blocks before asserting
the final Gno `PacketAck`.

For the local admin recovery setup path, run the setup service with the known
local ids:

```sh
cd e2e/union
GNO_CLIENT_ID=1 \
UNION_CLIENT_ID=4 \
GNO_PACKET_CONNECTION_ID=5 \
UNION_PACKET_CONNECTION_ID=3 \
GNO_PACKET_CHANNEL_ID=3 \
UNION_PACKET_CHANNEL_ID=2 \
docker compose --profile setup up --no-build gno-admin-recovery
```

This only recovers the Gno side; if the Union-side channel does not already
exist on a fresh devnet, this setup alone is not enough.

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

## 11. PacketSend -> Ack 확인

Use this flow once both sides have an open connection and channel. The current
validated local path is Gno channel `3` -> Union channel `2`.

Capture DB baselines before sending a packet. Treat old failed rows as
historical; only rows above the baseline matter for the current run.

```sh
docker ps --filter name=union-voyager --format 'table {{.Names}}\t{{.Status}}'

docker exec union-postgres-1 psql -U postgres -d postgres -c \
"select max(id) as queue_max from queue;
 select max(id) as done_max from done;
 select max(id) as failed_max from failed;
 select count(*) as queue_count from queue;
 select count(*) filter (where handle_at <= now()) as ready_count from queue;"

docker exec union-postgres-1 psql -U postgres -d postgres -c \
"select id, created_at, left(item::text, 2000) as item
 from failed
 order by id desc
 limit 10;"

docker exec union-gno-1 gnokey query vm/qeval -remote localhost:26657 \
  -data 'gno.land/r/onbloc/ibc/union/core.QueryChannel(<gno-channel-id>)'
```

Start a one-shot watcher before broadcasting `SendRaw`; it records the packet
hash and Gno block height.

```sh
cd e2e/union
GOWORK=off GOCACHE=/private/tmp/gno-ibc-go-cache \
go run ./cmd/packet-watch --once \
  --source-channel <gno-channel-id> \
  --destination-channel <union-channel-id>
```

Broadcast `SendRaw` from an EOA key. Do not use `gnokey maketx run` for native
token sends; the ZKGM realm checks `cur.Previous().IsUserCall()`.

```sh
docker exec union-gno-1 sh -lc 'printf "\n" | gnokey maketx call \
  -insecure-password-stdin \
  -pkgpath gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm \
  -func SendRaw \
  -args <gno-channel-id> \
  -args <timeout-timestamp-nanos> \
  -args <salt-hex-without-0x> \
  -args 2 \
  -args 3 \
  -args <operand-hex-without-0x> \
  -send <amount>ugnot \
  -gas-fee 5000000ugnot \
  -gas-wanted 200000000 \
  -broadcast \
  -chainid dev \
  -remote localhost:26657 \
  admin'
```

For deterministic CI-style processing, enqueue the single Gno block that
contains `PacketSend`:

```sh
docker exec union-voyager-1 ./voyager -c /config/voyager-config.gno-union.jsonc \
  queue enqueue \
  '{"@type":"call","@value":{"@type":"plugin","@value":{"plugin":"voyager-event-source-plugin-gno/dev","message":{"@type":"fetch_block","@value":{"height":"<gno-packet-send-height>"}}}}}'
```

Check only rows above the captured baselines. A healthy run creates
`packet_recv`, then Union emits `wasm-write_ack`, then Voyager creates a Gno
`packet_acknowledgement` submit.

```sh
docker exec union-postgres-1 psql -U postgres -d postgres -c \
"select id, created_at, left(item::text, 3000) as item
 from done
 where id > <BASE_DONE_ID>
   and (
     item::text like '%update_client%' or
     item::text like '%channel_open%' or
     item::text like '%packet_send%' or
     item::text like '%packet_recv%' or
     item::text like '%write_ack%' or
     item::text like '%acknowledgement%' or
     item::text like '%submit_transaction%'
   )
 order by id;"

docker exec union-postgres-1 psql -U postgres -d postgres -c \
"select id, created_at, left(item::text, 3000) as item, message
 from failed
 where id > <BASE_FAILED_ID>
 order by id;"
```

Verify the Union receive and write-ack tx:

```sh
docker exec full-dev-setup-union-0-1 uniond query txs \
  --query "wasm-packet_recv.packet_hash='<packet-hash>'" \
  --node tcp://localhost:26657 -o json --limit 3 --order_by desc

docker exec full-dev-setup-union-0-1 uniond query txs \
  --query "wasm-write_ack.packet_hash='<packet-hash>'" \
  --node tcp://localhost:26657 -o json --limit 3 --order_by desc
```

If Voyager does not automatically index the Union block that contains
`wasm-write_ack`, enqueue it:

```sh
docker exec union-voyager-1 ./voyager -c /config/voyager-config.gno-union.jsonc \
  queue enqueue \
  '{"@type":"call","@value":{"@type":"plugin","@value":{"plugin":"voyager-event-source-plugin-cosmwasm/union-devnet-1","message":{"@type":"fetch_block","@value":{"height":"1-<union-write-ack-height>"}}}}}'
```

Verify Gno received the acknowledgement:

```sh
curl -sS http://127.0.0.1:48546/graphql/query \
  -H 'content-type: application/json' \
  --data-binary '{"query":"{ getTransactions(where:{ success:{eq:true} response:{ events:{ GnoEvent:{ type:{eq:\"PacketAck\"} pkg_path:{eq:\"gno.land/r/onbloc/ibc/union/core\"} _and:[{ attrs:{ key:{eq:\"packet_hash\"} value:{eq:\"<packet-hash>\"} } }] } } } } order:{heightAndIndex:DESC}){ hash block_height response { events { ... on GnoEvent { type pkg_path attrs { key value } } } } } }"}'
```

Final checks:

```sh
docker exec union-voyager-1 ./voyager -c /config/voyager-config.gno-union.jsonc queue stats
docker exec union-voyager-1 ./voyager -c /config/voyager-config.gno-union.jsonc queue query-failed

docker exec union-gno-1 gnokey query vm/qeval -remote localhost:26657 \
  -data 'gno.land/r/onbloc/ibc/union/core.QueryChannel(<gno-channel-id>)'
```

Success means:

- Union `uniond query txs` shows a tx after the Gno PacketSend.
- The Union tx includes `wasm-packet_recv` or `wasm-intent_packet_recv`, and a
  `wasm-write_ack` for the same packet hash.
- Gno later shows the packet acknowledgement path, either as a Voyager done
  `packet_acknowledgement` / `submit_transaction` row or as a Gno
  `PacketAck` event for the same packet hash.
- `failed.id > <BASE_FAILED_ID>` is empty.
- `QueryChannel(<gno-channel-id>)` remains non-empty.

### Validated local run

The current local E2E run validated the full path with:

- Gno channel `3` -> Union channel `2`
- Packet hash
  `0x76c2926e67f6b246ed4f6d92faf82ab0d339c600856d5f8637ed98285750bf02`
- Gno `PacketSend` tx
  `zBq6fSuALZkmkb7ObbLKFMpuTwImMBF9z2tCippXz9g=` at height `9511`
- Union `packet_recv` tx
  `01A07D95622806E62A39689E02F051B4C893A010EC16314C233B2F66264C3B98`
  at height `14174`
- Gno `PacketAck` tx
  `t39lB9LE2/P4M9p9ozFrM/FgyyKB1D/XR8vqxwQUKOM=` at height `10432`

### Troubleshooting

If `packet_recv` simulation or broadcast fails with
`10-gno: new val set cannot be trusted`, the Union-side Gno client is too stale
for the packet proof height. For local E2E recovery, force-update the existing
Union client to the packet proof height, then retry `packet_recv`:

```sh
CREATE=$(docker exec union-voyager-1 ./voyager \
  -c /config/voyager-config.gno-union.jsonc \
  msg create-client --on union-devnet-1 --tracking dev \
  --ibc-interface ibc-cosmwasm --ibc-spec-id ibc-union --client-type gno \
  --height <gno-proof-height>)

MSG=$(printf '%s' "$CREATE" | jq -c \
  '{force_update_client:{client_id:<union-gno-client-id>, client_state_bytes: .["@value"]["@value"].datagrams[0].datagram["@value"].client_state_bytes, consensus_state_bytes: .["@value"]["@value"].datagrams[0].datagram["@value"].consensus_state_bytes}}')

docker exec full-dev-setup-union-0-1 uniond tx wasm execute \
  <union-core-contract> "$MSG" \
  --from voyager-relayer \
  --keyring-backend test \
  --home /.union \
  --chain-id union-devnet-1 \
  --node tcp://localhost:26657 \
  --gas 19000000 \
  --fees 19000000au \
  --yes \
  --broadcast-mode sync -o json
```

The validated local values were client `4`, proof height `9555`, and Union core
contract `union1nk3nes4ef6vcjan5tz6stf9g8p08q2kgqysx6q5exxh89zakp0msq5z79t`.

If Voyager creates a ready timeout or retry row while debugging, stop Voyager
first, then defer the row instead of deleting it:

```sh
docker exec union-postgres-1 psql -U postgres -d postgres -c \
"update queue
 set handle_at = now() + interval '24 hours'
 where handle_at <= now();"
```

If the test is still before PacketSend, verify that the ZKGM proxy realm is
deployed and registered with core:

```sh
docker exec union-gno-1 gnokey query vm/qeval -remote localhost:26657 \
  -data 'gno.land/r/onbloc/ibc/union/core.HasApp([]byte("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"))'
docker exec union-gno-1 gnokey query vm/qeval -remote localhost:26657 \
  -data 'gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm.ProxyPkgPath()'
```

If `HasApp` is false and the proxy qeval says `package not found`, the local
chain is blocked earlier than the connection/channel recovery. Deploy and
register the ZKGM proxy first; otherwise `ChannelOpenInit` panics with
`port not found, gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm`. The package
declarations under `apps/ucs03_zkgm` must match that path segment for manual
`gnokey maketx addpkg` deployments.

Once the ZKGM port is registered, the next blocker is connection/channel
creation before PacketSend. The Voyager CLI does not currently expose
`connection-open-init` or `channel-open-init`.

Use the existing Gno core recovery APIs for the shortest local path instead of
adding Voyager CLI commands first. Scenario filetests already use this pattern:

```gno
core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(gnoClientId, unionClientId))
core.ForceConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(connectionId, counterpartyConnectionId, nil, 0))
core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(portId, portId, connectionId, zkgm.Version, relayer))
core.ForceChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(channelId, zkgm.Version, counterpartyChannelId, nil, 0, relayer))
```

`ForceConnectionOpenAck` and `ForceChannelOpenAck` are admin-gated recovery
entrypoints. Run them only from the key that has the corresponding access
grants, then verify `QueryConnection(<id>)` and `QueryChannel(<id>)` are
non-empty before broadcasting PacketSend.

For the validated local run, Union channel `2` is open on Union connection `3`
and points back to Gno channel `3`; Union connection `3` points back to Gno
connection `5`. If reusing that state, verify Gno with `QueryConnection(5)` and
`QueryChannel(3)`.
