# Gno <-> Union <-> EVM Minimal E2E

This harness keeps Union in Arion/Nix and runs only the Gno side plus the Gno
tx-indexer in Docker Compose. That avoids reimplementing Union's existing
devnet in another compose file.

## 1. Start the minimized Union devnet

From `/Users/notjoon/union`:

```sh
NO_BLOCKSCOUT=true ./networks/run-linux-devnet.sh
```

Expected host ports:

- Union RPC: `http://localhost:26657`
- EVM RPC: `http://localhost:8545`
- Beacon API: `http://localhost:9596`
- Postgres: `localhost:5432`

Deploy the Union CosmWasm IBC stack once after the devnet is up:

```sh
cd /Users/notjoon/union
nix run .#cosmwasm-scripts.union-devnet.deploy
```

Without this, `uniond query wasm list-code` returns no code and Voyager fails
with `no such contract` for the configured IBC host address.

## 2. Start Gno and the tx-indexer

From `/Users/notjoon/gno-ibc/e2e/union`:

```sh
docker compose up --build gno tx-indexer
```

Gno uses host port `16657` because Union already uses `26657`.
Create `.env` only if you want to override the defaults from `.env.example`.

## 3. Run readiness tests

```sh
GOWORK=off GOCACHE=/private/tmp/gno-ibc-go-cache go test -v -run 'Ready|Readiness'
```

This verifies:

- Gno RPC is reachable.
- Union RPC is reachable.
- Geth JSON-RPC is reachable.
- Lodestar beacon API is reachable.
- Gno tx-indexer GraphQL is reachable.
- Postgres is reachable when `POSTGRES_ADDR=localhost:5432` is set.

## 4. Grant the Gno relayer role

```sh
docker compose --profile setup up gno-whitelist
```

This grants `access.RelayerRole` on the local Gno Union access realm. It does
not create IBC clients/channels yet.

## 5. Start Voyager

Voyager runs from the `union-voyager` checkout and uses the Gno-aware config in
this directory. Build the Voyager plugin binaries first if `target/debug/*` does
not exist yet.

```sh
cd /Users/notjoon/union-voyager
RUSTC_BOOTSTRAP=1 cargo build \
  --bin voyager \
  --bin voyager-client-bootstrap-module-cometbls \
  --bin voyager-client-bootstrap-module-gno \
  --bin voyager-client-module-cometbls \
  --bin voyager-client-module-gno \
  --bin voyager-client-update-plugin-cometbls \
  --bin voyager-client-update-plugin-gno \
  --bin voyager-event-source-plugin-cosmwasm \
  --bin voyager-event-source-plugin-gno \
  --bin voyager-finality-module-cometbls \
  --bin voyager-finality-module-gno \
  --bin voyager-plugin-packet-timeout \
  --bin voyager-plugin-transaction-batch \
  --bin voyager-proof-module-cosmwasm \
  --bin voyager-proof-module-gno \
  --bin voyager-state-module-cosmwasm \
  --bin voyager-state-module-gno \
  --bin voyager-transaction-plugin-cosmos \
  --bin voyager-transaction-plugin-gno

cd /Users/notjoon/gno-ibc/e2e/union
./run-voyager.sh start
```

In another terminal, seed indexing and client creation:

```sh
cd /Users/notjoon/gno-ibc/e2e/union
./run-voyager.sh index union-devnet-1 -e
./run-voyager.sh index dev -e
./run-voyager.sh msg create-client --on union-devnet-1 --tracking dev \
  --ibc-interface ibc-cosmwasm --ibc-spec-id ibc-union --client-type gno -e
./run-voyager.sh msg create-client --on dev --tracking union-devnet-1 \
  --ibc-interface ibc-gno --ibc-spec-id ibc-union --client-type cometbls -e
```

`devnet-compose` in `/Users/notjoon/union-voyager` can also launch Gno now. Set
`VOYAGER_CONFIG=/Users/notjoon/gno-ibc/e2e/union/voyager-config.gno-union.jsonc`
and select `Gno` plus `Union`.

## 6. Packet tests

After Voyager opens a channel, export the channel and operand values, then run:

```sh
RUN_PACKET_TESTS=1 \
GNO_PACKET_CHANNEL_ID=<channel-id> \
GNO_PACKET_OPERAND_HEX=<pre-encoded-token-order> \
GOWORK=off GOCACHE=/private/tmp/gno-ibc-go-cache \
go test -v -run Packet
```

## 7. Memory check

```sh
docker stats
```

The expected minimized steady-state set is:

- 1 Union validator
- geth
- lodestar with 1 beacon validator
- forge only during deploy
- small Postgres
- Gno
- tx-indexer

Blockscout is disabled by `NO_BLOCKSCOUT=true`.
