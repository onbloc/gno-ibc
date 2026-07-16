# Gno → Union Voyager E2E

This harness proves one deterministic path:

```text
Gno PacketSend → Union packet_recv → Union write_ack → Gno PacketAck
```

The tested inputs are pinned in `.gno-version` and `.env.example`; Compose uses
those commits as the local Gno and Voyager image tags.

## Prerequisites

- Docker Compose
- the Union Voyager checkout at the commit above (`UNION_VOYAGER_DIR`)
- Union's devnet running on RPC `26657`, EVM RPC `8545`, and beacon API `9596`
- the configured Union core and ZKGM contracts

Start and deploy the pinned Union checkout:

```sh
. e2e/union/.env.example
git -C "$UNION_VOYAGER_DIR" checkout "$UNION_COMMIT"
NO_BLOCKSCOUT=true "$UNION_VOYAGER_DIR/networks/run-linux-devnet.sh"
cd "$UNION_VOYAGER_DIR"
nix run .#cosmwasm-scripts.union-devnet.deploy-manager -- \
  --initial-admin union1jk9psyhvgkrt2cumz8eytll2244m2nnz4yt2g2 --allow-dirty
nix run .#cosmwasm-scripts.union-devnet.deploy -- --allow-dirty
nix run .#cosmwasm-scripts.union-devnet.whitelist-relayers -- \
  union1jk9psyhvgkrt2cumz8eytll2244m2nnz4yt2g2
```

The Gno ↔ Union packet test validates its configured topology before sending.
The direct Union ↔ Ethereum test uses separately created client, connection,
and channel IDs and never reuses a topology with a mismatched counterparty,
port, owner, or version. The current contract addresses are in
`voyager-config.gno-union.jsonc`.

## Build and start

```sh
cd e2e/union
cp .env.example .env
docker compose --env-file ../../.gno-version --env-file .env build gno voyager
docker compose --env-file ../../.gno-version --env-file .env up -d gno tx-indexer postgres voyager
```

The Gno Docker build reads `GNO_REPO` and `GNO_COMMIT` directly from the root
`.gno-version`; there is no floating fallback.

## Deterministic Gno setup

The setup services are independently rerunnable. Use `run --rm`, not attached
`up`:

```sh
docker compose --env-file ../../.gno-version --env-file .env --profile setup run --rm gno-whitelist
docker compose --env-file ../../.gno-version --env-file .env --profile setup run --rm gno-bootstrap
docker compose --env-file ../../.gno-version --env-file .env --profile setup run --rm gno-admin-recovery
```

`gno-bootstrap` installs the core and ZKGM implementations, registers the app,
and registers both light clients. `gno-admin-recovery` creates and validates
Gno connection `5` and channel `3`; a mismatched existing record fails before
state is written.

The Voyager Gno transaction key in the checked-in config and the test mnemonic
in `.env.example` both derive to `g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5`;
the setup derives that address before granting `RelayerRole`.

## Deterministic Union EVM light-client setup

The direct Union ↔ Ethereum link requires `trusted/evm/mpt` on the Union core.
The setup is independently rerunnable and exits without broadcasting when the
registered implementation and code already exist:

```sh
e2e/union/setup-union-evm.sh
```

If the pinned artifact has not been built, the script stops and prints the
exact pinned build command. Contract deployment and client registration remain
a setup operation; packet tests never perform them implicitly.

## Run the packet test

Pre-encode the ZKGM operand as described in the repository `AGENTS.md`, then:

```sh
RUN_PACKET_TESTS=1 \
GNO_PACKET_OPERAND_HEX=<hex> \
GNO_PACKET_SEND_COINS=1ugnot \
GNO_COMPOSE_DIR=. \
GOWORK=off GOCACHE=/private/tmp/gno-ibc-e2e-go-cache \
go test -v . -run '^TestGnoToUnionPacketRelay$'
```

For the direct Union → Ethereum lifecycle, generate and review the
`TokenOrderV2` instruction and predicted wrapped-token address first, then run:

```sh
RUN_PACKET_TESTS=1 \
UNION_EVM_INSTRUCTION_HEX=<hex> \
EVM_WRAPPED_TOKEN=<predicted-address> \
GOWORK=off GOCACHE=/private/tmp/gno-ibc-e2e-go-cache \
go test -v . -run '^TestUnionToEthereumPacketRelay$'
```

The test captures Voyager queue/done/failed baselines, ignores historical
failures, and checks exactly one receive/write-ack/ack for the packet hash. If
receive stalls or Voyager reports the known stale Gno client error, it performs
one bounded `force_update_client` for Union client `1` and retries the block.
Future timeout jobs may remain in Voyager's ready queue, so completion is
proved by packet events, new done rows, and the absence of new failed rows.

## Troubleshooting

```sh
docker compose --env-file ../../.gno-version --env-file .env logs voyager
docker exec union-voyager-1 ./voyager \
  -c /config/voyager-config.gno-union.jsonc queue stats
docker exec union-voyager-1 ./voyager \
  -c /config/voyager-config.gno-union.jsonc queue query-failed
curl -fsS http://localhost:48546/graphql/query \
  -H 'content-type: application/json' \
  --data '{"query":"{ latestBlockHeight }"}'
```

Clean up every run with:

```sh
docker compose --env-file ../../.gno-version --env-file .env down -v --remove-orphans
```

The canonical gnokey query examples are in
`gno.land/r/onbloc/ibc/gnokey_tx_queries.md`.
